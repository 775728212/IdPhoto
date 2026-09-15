import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/utils/pixel_buffer.dart';

/// 抠图参数。
class SegmentOptions {
  const SegmentOptions({
    this.tolerance = 34,
    this.edgeClean = 1,
    this.feather = 1,
    this.seedColor,
    this.localGrowth = true,
  });

  /// 颜色容差 0..100，越大越"激进"地把像素判为背景。
  final int tolerance;

  /// 去边缘杂色：把背景掩膜向外膨胀 N 像素，吃掉抠图边缘残留的底色。
  final int edgeClean;

  /// 边缘羽化半径（像素），让头发丝过渡自然。
  final int feather;

  /// 手动指定的背景色 0xRRGGBB；为空时自动从四角采样推断。
  final int? seedColor;

  /// 邻域生长：允许和"邻居颜色"比较而不是只和背景主色比较，
  /// 用于应对背景存在光照渐变（手机拍摄常见）的情况。
  final bool localGrowth;

  SegmentOptions copyWith({
    int? tolerance,
    int? edgeClean,
    int? feather,
    int? seedColor,
    bool? localGrowth,
    bool clearSeedColor = false,
  }) {
    return SegmentOptions(
      tolerance: tolerance ?? this.tolerance,
      edgeClean: edgeClean ?? this.edgeClean,
      feather: feather ?? this.feather,
      seedColor: clearSeedColor ? null : (seedColor ?? this.seedColor),
      localGrowth: localGrowth ?? this.localGrowth,
    );
  }
}

/// 抠图结果。`mask` 中 **0 = 前景（人像），255 = 背景**。
class MaskResult {
  const MaskResult({
    required this.mask,
    required this.width,
    required this.height,
    required this.backgroundArgb,
    required this.fallbackUsed,
  });

  final Uint8List mask;
  final int width;
  final int height;

  /// 实际使用的背景色 0xRRGGBB。
  final int backgroundArgb;

  /// 边界上完全找不到背景像素时退化为"全前景"。
  final bool fallbackUsed;

  int get r => (backgroundArgb >> 16) & 0xFF;
  int get g => (backgroundArgb >> 8) & 0xFF;
  int get b => backgroundArgb & 0xFF;

  /// 背景像素占比 0..1，用于判断抠图是否成功。
  double get coverage {
    if (mask.isEmpty) return 0;
    var bg = 0;
    for (int i = 0; i < mask.length; i++) {
      if (mask[i] > 127) bg++;
    }
    return bg / mask.length;
  }
}

/// 基于「边界洪水填充」的智能抠图。
///
/// 针对证件照这种「人像 + 相对干净背景」的场景，流程为：
///  1. 从四个角采样，用颜色直方图众数估计背景主色；
///  2. 以图像边界上所有"接近背景色"的像素为种子做洪水填充，
///     因此主体（通常延伸到底边）不会被误判为种子；
///  3. 填充时除与主色比较外，还可与邻居颜色比较，以应对灯光渐变；
///  4. 对掩膜做膨胀（去边缘杂色）与盒式模糊（羽化）。
class SegmentationService {
  SegmentationService._();

  /// 在后台 isolate 中计算掩膜，避免大图卡住 UI。
  ///
  /// 这里用 `dart:isolate` 而不是 `compute()`，是为了让整个 services 层
  /// 保持纯 Dart —— 不依赖 Flutter，核心算法可以用 `dart run` 直接跑起来验证。
  static Future<MaskResult> buildMask(
    PixelBuffer source,
    SegmentOptions options,
  ) async {
    try {
      return await Isolate.run(() => buildMaskSync(source, options));
    } catch (_) {
      // isolate 不可用（受限环境 / 消息不可发送）时退回主线程。
      return buildMaskSync(source, options);
    }
  }

  static MaskResult buildMaskSync(PixelBuffer source, SegmentOptions options) {
    final int w = source.width;
    final int h = source.height;
    final Uint8List rgba = source.rgba;

    final int bgColor = options.seedColor ?? estimateBackgroundColor(source);
    final int bgR = (bgColor >> 16) & 0xFF;
    final int bgG = (bgColor >> 8) & 0xFF;
    final int bgB = bgColor & 0xFF;

    final double radius = options.tolerance.clamp(0, 100) / 100.0 * 190.0;
    final double globalLimit2 = radius * radius;
    final double localRadius = radius * 0.35;
    final double localLimit2 = localRadius * localRadius;

    final Uint8List mask = Uint8List(w * h);
    final Uint8List visited = Uint8List(w * h);
    final Int32List stack = Int32List(w * h);
    int sp = 0;

    bool nearGlobal(int idx) {
      final int i = idx << 2;
      final int dr = rgba[i] - bgR;
      final int dg = rgba[i + 1] - bgG;
      final int db = rgba[i + 2] - bgB;
      return (dr * dr + dg * dg + db * db).toDouble() <= globalLimit2;
    }

    bool nearNeighbour(int idx, int refIdx) {
      final int i = idx << 2;
      final int j = refIdx << 2;
      final int dr = rgba[i] - rgba[j];
      final int dg = rgba[i + 1] - rgba[j + 1];
      final int db = rgba[i + 2] - rgba[j + 2];
      return (dr * dr + dg * dg + db * db).toDouble() <= localLimit2;
    }

    // ---- 1. 采集边界种子 ----
    for (int x = 0; x < w; x++) {
      final int top = x;
      final int bottom = (h - 1) * w + x;
      if (visited[top] == 0 && nearGlobal(top)) {
        visited[top] = 1;
        stack[sp++] = top;
      }
      if (h > 1 && visited[bottom] == 0 && nearGlobal(bottom)) {
        visited[bottom] = 1;
        stack[sp++] = bottom;
      }
    }
    for (int y = 0; y < h; y++) {
      final int left = y * w;
      final int right = y * w + w - 1;
      if (visited[left] == 0 && nearGlobal(left)) {
        visited[left] = 1;
        stack[sp++] = left;
      }
      if (w > 1 && visited[right] == 0 && nearGlobal(right)) {
        visited[right] = 1;
        stack[sp++] = right;
      }
    }

    if (sp == 0) {
      // 边界上找不到任何背景像素，说明主体填满了画面，整体判为前景。
      return MaskResult(
        mask: mask,
        width: w,
        height: h,
        backgroundArgb: bgColor,
        fallbackUsed: true,
      );
    }

    // ---- 2. 洪水填充 ----
    void push(int idx, int fromIdx) {
      if (visited[idx] != 0) return;
      if (nearGlobal(idx) || (options.localGrowth && nearNeighbour(idx, fromIdx))) {
        visited[idx] = 1;
        stack[sp++] = idx;
      }
    }

    while (sp > 0) {
      final int idx = stack[--sp];
      mask[idx] = 255;

      final int x = idx % w;
      final int y = idx ~/ w;

      if (x > 0) push(idx - 1, idx);
      if (x < w - 1) push(idx + 1, idx);
      if (y > 0) push(idx - w, idx);
      if (y < h - 1) push(idx + w, idx);
    }

    // ---- 3. 去边缘杂色 + 羽化 ----
    Uint8List result = mask;
    if (options.edgeClean > 0) {
      result = _dilate(result, w, h, options.edgeClean.clamp(0, 5));
    }
    if (options.feather > 0) {
      result = _boxBlur(result, w, h, options.feather.clamp(0, 8));
    }

    return MaskResult(
      mask: result,
      width: w,
      height: h,
      backgroundArgb: bgColor,
      fallbackUsed: false,
    );
  }

  /// 从四角采样，用颜色直方图众数估计背景主色。
  ///
  /// 证件照人物居中，四个角基本都是背景，因此这个估计相当稳。
  static int estimateBackgroundColor(PixelBuffer source) {
    final int w = source.width;
    final int h = source.height;
    final int minSide = w < h ? w : h;
    final int size = (minSide * 0.05).round().clamp(3, 32);

    final List<List<int>> corners = <List<int>>[
      <int>[0, 0],
      <int>[w - size, 0],
      <int>[0, h - size],
      <int>[w - size, h - size],
    ];

    final Map<int, List<int>> buckets = <int, List<int>>{};
    for (final List<int> corner in corners) {
      final int x0 = corner[0].clamp(0, math.max(0, w - 1));
      final int y0 = corner[1].clamp(0, math.max(0, h - 1));
      final int xEnd = math.min(x0 + size, w);
      final int yEnd = math.min(y0 + size, h);
      for (int y = y0; y < yEnd; y++) {
        for (int x = x0; x < xEnd; x++) {
          final int i = (y * w + x) << 2;
          final int r = source.rgba[i];
          final int g = source.rgba[i + 1];
          final int b = source.rgba[i + 2];
          // 每通道量化到 32 级（5 bit）
          final int key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
          final List<int>? acc = buckets[key];
          if (acc == null) {
            buckets[key] = <int>[r, g, b, 1];
          } else {
            acc[0] += r;
            acc[1] += g;
            acc[2] += b;
            acc[3] += 1;
          }
        }
      }
    }

    if (buckets.isEmpty) return 0xFFFFFF;

    List<int> best = const <int>[255, 255, 255, 1];
    int bestCount = -1;
    for (final List<int> acc in buckets.values) {
      if (acc[3] > bestCount) {
        bestCount = acc[3];
        best = acc;
      }
    }
    final int n = best[3];
    return ((best[0] ~/ n) << 16) | ((best[1] ~/ n) << 8) | (best[2] ~/ n);
  }

  /// 8 邻域最大值膨胀（让背景掩膜向外扩张）。
  static Uint8List _dilate(Uint8List mask, int w, int h, int radius) {
    if (radius <= 0) return mask;
    Uint8List cur = mask;
    for (int r = 0; r < radius; r++) {
      final Uint8List next = Uint8List.fromList(cur);
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final int idx = y * w + x;
          if (cur[idx] == 255) continue;
          bool hit = false;
          for (int dy = -1; dy <= 1 && !hit; dy++) {
            final int ny = y + dy;
            if (ny < 0 || ny >= h) continue;
            for (int dx = -1; dx <= 1; dx++) {
              final int nx = x + dx;
              if (nx < 0 || nx >= w) continue;
              if (cur[ny * w + nx] == 255) {
                hit = true;
                break;
              }
            }
          }
          if (hit) next[idx] = 255;
        }
      }
      cur = next;
    }
    return cur;
  }

  /// 可分离盒式模糊，O(w*h)。
  static Uint8List _boxBlur(Uint8List src, int w, int h, int radius) {
    if (radius <= 0 || w == 0 || h == 0) return src;
    final int window = radius * 2 + 1;
    final Uint8List tmp = Uint8List(w * h);
    final Uint8List out = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      final int base = y * w;
      int sum = 0;
      for (int i = -radius; i <= radius; i++) {
        sum += src[base + i.clamp(0, w - 1)];
      }
      for (int x = 0; x < w; x++) {
        tmp[base + x] = sum ~/ window;
        sum += src[base + (x + radius + 1).clamp(0, w - 1)];
        sum -= src[base + (x - radius).clamp(0, w - 1)];
      }
    }

    for (int x = 0; x < w; x++) {
      int sum = 0;
      for (int i = -radius; i <= radius; i++) {
        sum += tmp[i.clamp(0, h - 1) * w + x];
      }
      for (int y = 0; y < h; y++) {
        out[y * w + x] = sum ~/ window;
        sum += tmp[(y + radius + 1).clamp(0, h - 1) * w + x];
        sum -= tmp[(y - radius).clamp(0, h - 1) * w + x];
      }
    }
    return out;
  }

  /// 手动修补：在掩膜上点一个圆。`asBackground = true` 表示"这块是背景"。
  static void stampCircle(
    Uint8List mask,
    int width,
    int height,
    int cx,
    int cy,
    int radius, {
    required bool asBackground,
  }) {
    final int value = asBackground ? 255 : 0;
    if (radius <= 0) return;
    final int r2 = radius * radius;
    final int yStart = (cy - radius).clamp(0, math.max(0, height - 1));
    final int yEnd = (cy + radius).clamp(0, math.max(0, height - 1));
    final int xStart = (cx - radius).clamp(0, math.max(0, width - 1));
    final int xEnd = (cx + radius).clamp(0, math.max(0, width - 1));
    for (int y = yStart; y <= yEnd; y++) {
      for (int x = xStart; x <= xEnd; x++) {
        final int dx = x - cx;
        final int dy = y - cy;
        if (dx * dx + dy * dy <= r2) {
          mask[y * width + x] = value;
        }
      }
    }
  }

  /// 在两点之间连续盖章，手势快速滑动时不会出现断点。
  static void stampLine(
    Uint8List mask,
    int width,
    int height,
    double x0,
    double y0,
    double x1,
    double y1,
    int radius, {
    required bool asBackground,
  }) {
    final double dx = x1 - x0;
    final double dy = y1 - y0;
    final double distance = math.sqrt(dx * dx + dy * dy);
    final int steps = distance.ceil().clamp(1, 512);
    for (int i = 0; i <= steps; i++) {
      final double t = i / steps;
      stampCircle(
        mask,
        width,
        height,
        (x0 + dx * t).round(),
        (y0 + dy * t).round(),
        radius,
        asBackground: asBackground,
      );
    }
  }
}
