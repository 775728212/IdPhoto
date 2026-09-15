import 'dart:typed_data';

import '../core/constants/bg_swatches.dart';
import '../core/utils/pixel_buffer.dart';

/// 换底色：把掩膜标记为背景的像素替换成目标底色。
///
/// 这里有两个容易出问题的点，都在下面单独处理了：
///
///  1. **去色溢（un-premultiply）**：抠图边缘的抗锯齿像素是
///     「前景色 ×(1-t) + 原底色 ×t」的混合结果。直接叠加新底色，
///     换成白底时边缘就会残留一圈蓝边。所以要先反解出真实前景色。
///
///  2. **过渡带比例估计**：反解需要知道 t。掩膜经过膨胀 + 羽化之后，
///     它的灰度值只是一个很粗糙的 t 估计 —— 偏大就会把边缘"烧"成
///     暖黄色描边，偏小则残留原底色。所以这里改成用**颜色投影**来解：
///     已知原始颜色 C、原背景色 B，再从最近的"确定前景"像素取到 F，
///     则 `alpha_fg = (C-B)·(F-B) / |F-B|²`，精度远高于羽化值。
class RecolorService {
  RecolorService._();

  /// [colorMatting] 打开时用颜色投影精修过渡带；[decontaminate] 控制是否反解前景色。
  /// 两者都关掉就是最朴素的"背景像素直接盖新底色"。
  static PixelBuffer apply({
    required PixelBuffer source,
    required Uint8List mask,
    required BgSwatch swatch,
    int originalBackgroundArgb = 0xFFFFFF,
    bool decontaminate = true,
    bool colorMatting = true,
    bool replaceFullyTransparent = true,
  }) {
    final int w = source.width;
    final int h = source.height;

    // 掩膜必须和图像同尺寸。这里用显式抛错而不是 assert —— 断言在
    // `dart run` / release 下默认关闭，尺寸错的掩膜只会静默按错误的
    // 偏移去读像素，产出一张"看着不对劲但也不报错"的图，很难排查。
    if (mask.length != source.pixelCount) {
      throw ArgumentError(
        '掩膜长度(${mask.length})与图像 ${w}x$h 不匹配，'
        '请确保掩膜是在同一张图上生成的',
      );
    }

    final PixelBuffer out = PixelBuffer.empty(w, h);
    final Uint8List src = source.rgba;
    final Uint8List dst = out.rgba;

    final int origBgR = (originalBackgroundArgb >> 16) & 0xFF;
    final int origBgG = (originalBackgroundArgb >> 8) & 0xFF;
    final int origBgB = originalBackgroundArgb & 0xFF;

    final bool transparent = swatch.transparent;
    final double invH = h > 1 ? 1.0 / (h - 1) : 0.0;

    // 最近前景色查表：只在需要反解时构建，构建失败（找不到任何确定前景）返回 null。
    final Uint8List? coreColors =
        (decontaminate && colorMatting) ? _nearestForegroundColors(source, mask) : null;

    for (int y = 0; y < h; y++) {
      final List<int> base = swatch.isGradient
          ? swatch.colorAt(y * invH)
          : <int>[swatch.r, swatch.g, swatch.b];
      final int newR = base[0];
      final int newG = base[1];
      final int newB = base[2];

      final int rowBase = y * w;
      for (int x = 0; x < w; x++) {
        final int idx = rowBase + x;
        final int i = idx << 2;
        final int m = mask[idx];

        if (m == 0) {
          // 确定的前景，原样保留。
          dst[i] = src[i];
          dst[i + 1] = src[i + 1];
          dst[i + 2] = src[i + 2];
          dst[i + 3] = src[i + 3];
          continue;
        }

        // 掩膜给出的前景占比（1 = 纯前景）。
        double inv = 1.0 - m / 255.0;

        if (coreColors != null) {
          // 颜色投影：把像素颜色投影到「原背景色 → 邻近前景色」这条线段上。
          final int dr = coreColors[i] - origBgR;
          final int dg = coreColors[i + 1] - origBgG;
          final int db = coreColors[i + 2] - origBgB;
          final int denom = dr * dr + dg * dg + db * db;
          if (denom > 256) {
            final int cr = src[i] - origBgR;
            final int cg = src[i + 1] - origBgG;
            final int cb = src[i + 2] - origBgB;
            final double projected =
                ((cr * dr + cg * dg + cb * db) / denom).clamp(0.0, 1.0);
            // 取较大者：掩膜负责判断"这里算不算背景"，投影负责给出
            // "背景占多少"。投影更大，说明膨胀把真正的前景吃掉了，还回去。
            if (projected > inv) inv = projected;
          }
        }

        final double a = 1.0 - inv; // 背景占比

        // 反解真实前景色
        int fr = src[i];
        int fg = src[i + 1];
        int fb = src[i + 2];
        if (decontaminate && inv > 0.05) {
          fr = ((src[i] - origBgR * a) / inv).round().clamp(0, 255);
          fg = ((src[i + 1] - origBgG * a) / inv).round().clamp(0, 255);
          fb = ((src[i + 2] - origBgB * a) / inv).round().clamp(0, 255);
        }

        if (transparent) {
          // 输出带 alpha 的前景，交回 PNG 保存
          dst[i] = inv <= 0.05 ? 0 : fr;
          dst[i + 1] = inv <= 0.05 ? 0 : fg;
          dst[i + 2] = inv <= 0.05 ? 0 : fb;
          dst[i + 3] = (inv * 255).round().clamp(0, 255);
        } else {
          if (a >= 1.0 && replaceFullyTransparent) {
            dst[i] = newR;
            dst[i + 1] = newG;
            dst[i + 2] = newB;
          } else {
            dst[i] = (fr * inv + newR * a).round().clamp(0, 255);
            dst[i + 1] = (fg * inv + newG * a).round().clamp(0, 255);
            dst[i + 2] = (fb * inv + newB * a).round().clamp(0, 255);
          }
          dst[i + 3] = 255;
        }
      }
    }
    return out;
  }

  /// 多源 BFS：从所有「确定前景」（mask == 0）的像素出发，把整张图标记成
  /// 「离它最近的那个前景核心像素的颜色」。
  ///
  /// 过渡带里的像素颜色 `C = F·(1-t) + B·t`，有了邻近的 F 和已知的 B，
  /// 就能反解出比羽化掩膜准得多的 t。整张图一次 BFS，O(w·h)。
  ///
  /// 找不到任何确定前景像素时返回 null，调用方退回原逻辑。
  static Uint8List? _nearestForegroundColors(PixelBuffer source, Uint8List mask) {
    final int w = source.width;
    final int h = source.height;
    final Uint8List src = source.rgba;

    final Uint8List colors = Uint8List(w * h * 4);
    final Uint8List visited = Uint8List(w * h);
    final Int32List queue = Int32List(w * h);
    int head = 0;
    int tail = 0;

    for (int i = 0; i < mask.length; i++) {
      if (mask[i] == 0) {
        visited[i] = 1;
        final int p = i << 2;
        colors[p] = src[p];
        colors[p + 1] = src[p + 1];
        colors[p + 2] = src[p + 2];
        queue[tail++] = i;
      }
    }
    if (tail == 0) return null;

    while (head < tail) {
      final int idx = queue[head++];
      final int p = idx << 2;
      final int cr = colors[p];
      final int cg = colors[p + 1];
      final int cb = colors[p + 2];
      final int x = idx % w;

      for (int k = 0; k < 4; k++) {
        int nIdx = -1;
        if (k == 0) {
          if (x > 0) nIdx = idx - 1;
        } else if (k == 1) {
          if (x < w - 1) nIdx = idx + 1;
        } else if (k == 2) {
          if (idx >= w) nIdx = idx - w;
        } else {
          if (idx < w * (h - 1)) nIdx = idx + w;
        }
        if (nIdx < 0 || visited[nIdx] != 0) continue;

        visited[nIdx] = 1;
        final int np = nIdx << 2;
        colors[np] = cr;
        colors[np + 1] = cg;
        colors[np + 2] = cb;
        queue[tail++] = nIdx;
      }
    }
    return colors;
  }

  /// 把带透明的图压到指定底色上（导出 JPEG 前调用，避免透明区域变黑）。
  static PixelBuffer flattenOn(PixelBuffer source, int argb) {
    final int r = (argb >> 16) & 0xFF;
    final int g = (argb >> 8) & 0xFF;
    final int b = argb & 0xFF;

    final PixelBuffer out = PixelBuffer.empty(source.width, source.height);
    final Uint8List src = source.rgba;
    final Uint8List dst = out.rgba;

    for (int i = 0; i < src.length; i += 4) {
      final int a = src[i + 3];
      if (a == 255) {
        dst[i] = src[i];
        dst[i + 1] = src[i + 1];
        dst[i + 2] = src[i + 2];
      } else {
        final int inv = 255 - a;
        dst[i] = (src[i] * a + r * inv) ~/ 255;
        dst[i + 1] = (src[i + 1] * a + g * inv) ~/ 255;
        dst[i + 2] = (src[i + 2] * a + b * inv) ~/ 255;
      }
      dst[i + 3] = 255;
    }
    return out;
  }
}
