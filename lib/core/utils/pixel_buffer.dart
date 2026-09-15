import 'dart:typed_data';

/// 整个图像处理流水线统一使用的 RGBA8888 像素缓冲区。
///
/// 之所以不直接依赖 `package:image` 的 Image 对象，是因为：
///  1. 抠图 / 换底 / 压缩都需要大量逐像素读写，直接操作 `Uint8List` 最快；
///  2. 与 `package:image` 解耦后，核心算法可以在纯 Dart 环境下做单元测试。
class PixelBuffer {
  PixelBuffer(this.width, this.height, this.rgba)
      : assert(width > 0 && height > 0, '尺寸必须为正数'),
        assert(
          rgba.length == width * height * 4,
          'RGBA 缓冲区长度(${rgba.length}) 与 ${width}x$height 不匹配',
        );

  factory PixelBuffer.empty(int width, int height) =>
      PixelBuffer(width, height, Uint8List(width * height * 4));

  final int width;
  final int height;

  /// 长度为 `width * height * 4` 的 RGBA 字节流，顺序固定为 R,G,B,A。
  final Uint8List rgba;

  int get pixelCount => width * height;

  double get aspectRatio => width / height;

  int indexOf(int x, int y) => (y * width + x) * 4;

  /// 读取 (x, y) 处的颜色，返回 0xAARRGGBB。
  int argbAt(int x, int y) {
    final i = indexOf(x, y);
    return (rgba[i + 3] << 24) | (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
  }

  void setRgba(int x, int y, int r, int g, int b, int a) {
    final i = indexOf(x, y);
    rgba[i] = r;
    rgba[i + 1] = g;
    rgba[i + 2] = b;
    rgba[i + 3] = a;
  }

  PixelBuffer clone() => PixelBuffer(width, height, Uint8List.fromList(rgba));

  /// 是否包含任何非全不透明像素（用于判断能否输出 JPEG）。
  bool get hasTransparency {
    for (int i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) return true;
    }
    return false;
  }

  @override
  String toString() => 'PixelBuffer(${width}x$height)';
}

/// 图像几何变换：旋转、镜像、区域重采样。
class ImageOps {
  ImageOps._();

  /// 顺时针旋转 [quarters] 个 90°。`quarters` 会先归一化到 0..3。
  static PixelBuffer rotateQuarters(PixelBuffer src, int quarters) {
    final q = ((quarters % 4) + 4) % 4;
    if (q == 0) return src.clone();

    final w = src.width;
    final h = src.height;
    final swap = q.isOdd;
    final outW = swap ? h : w;
    final outH = swap ? w : h;

    final dst = PixelBuffer.empty(outW, outH);
    final s = src.rgba;
    final d = dst.rgba;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int dx;
        final int dy;
        switch (q) {
          case 1: // 顺时针 90°：(x, y) -> (h-1-y, x)
            dx = h - 1 - y;
            dy = x;
            break;
          case 2: // 180°：(x, y) -> (w-1-x, h-1-y)
            dx = w - 1 - x;
            dy = h - 1 - y;
            break;
          default: // 270°：(x, y) -> (y, w-1-x)
            dx = y;
            dy = w - 1 - x;
            break;
        }
        final si = (y * w + x) * 4;
        final di = (dy * outW + dx) * 4;
        d[di] = s[si];
        d[di + 1] = s[si + 1];
        d[di + 2] = s[si + 2];
        d[di + 3] = s[si + 3];
      }
    }
    return dst;
  }

  /// 水平镜像。
  static PixelBuffer flipHorizontal(PixelBuffer src) {
    final w = src.width;
    final h = src.height;
    final dst = PixelBuffer.empty(w, h);
    final s = src.rgba;
    final d = dst.rgba;

    for (int y = 0; y < h; y++) {
      final rowBase = y * w;
      for (int x = 0; x < w; x++) {
        final si = (rowBase + x) * 4;
        final di = (rowBase + (w - 1 - x)) * 4;
        d[di] = s[si];
        d[di + 1] = s[si + 1];
        d[di + 2] = s[si + 2];
        d[di + 3] = s[si + 3];
      }
    }
    return dst;
  }

  /// 垂直镜像。
  static PixelBuffer flipVertical(PixelBuffer src) {
    final w = src.width;
    final h = src.height;
    final dst = PixelBuffer.empty(w, h);
    final s = src.rgba;
    final d = dst.rgba;

    for (int y = 0; y < h; y++) {
      final si = y * w * 4;
      final di = (h - 1 - y) * w * 4;
      for (int i = 0; i < w * 4; i++) {
        d[di + i] = s[si + i];
      }
    }
    return dst;
  }

  /// 从 [src] 中取出浮点矩形区域并重采样到 [outW] x [outH]。
  ///
  /// - 缩小（区域大于输出）时使用**面积平均**，避免证件照缩小时出现摩尔纹/锯齿；
  /// - 放大时使用**双线性插值**。
  ///
  /// 区域允许超出图像边界，超出的部分按边缘像素钳制。
  static PixelBuffer resampleRegion(
    PixelBuffer src,
    double sx,
    double sy,
    double sw,
    double sh,
    int outW,
    int outH,
  ) {
    assert(sw > 0 && sh > 0);
    assert(outW > 0 && outH > 0);

    final dst = PixelBuffer.empty(outW, outH);
    final s = src.rgba;
    final d = dst.rgba;
    final srcW = src.width;
    final srcH = src.height;

    final xRatio = sw / outW;
    final yRatio = sh / outH;

    if (xRatio >= 1.0 && yRatio >= 1.0) {
      // ---- 降采样：面积平均 ----
      for (int oy = 0; oy < outH; oy++) {
        final yTop = sy + oy * yRatio;
        final yBottom = yTop + yRatio;
        var iy0 = yTop.floor();
        var iy1 = yBottom.ceil() - 1;
        if (iy1 < iy0) iy1 = iy0;
        if (iy0 < 0) iy0 = 0;
        if (iy1 > srcH - 1) iy1 = srcH - 1;
        if (iy1 < iy0) {
          // 完全越界，退化为最近行
          iy0 = yTop.round().clamp(0, srcH - 1);
          iy1 = iy0;
        }

        for (int ox = 0; ox < outW; ox++) {
          final xLeft = sx + ox * xRatio;
          final xRight = xLeft + xRatio;
          var ix0 = xLeft.floor();
          var ix1 = xRight.ceil() - 1;
          if (ix1 < ix0) ix1 = ix0;
          if (ix0 < 0) ix0 = 0;
          if (ix1 > srcW - 1) ix1 = srcW - 1;
          if (ix1 < ix0) {
            ix0 = xLeft.round().clamp(0, srcW - 1);
            ix1 = ix0;
          }

          int r = 0, g = 0, b = 0, a = 0, n = 0;
          for (int y = iy0; y <= iy1; y++) {
            int base = (y * srcW + ix0) * 4;
            for (int x = ix0; x <= ix1; x++) {
              r += s[base];
              g += s[base + 1];
              b += s[base + 2];
              a += s[base + 3];
              base += 4;
              n++;
            }
          }

          final di = (oy * outW + ox) * 4;
          d[di] = r ~/ n;
          d[di + 1] = g ~/ n;
          d[di + 2] = b ~/ n;
          d[di + 3] = a ~/ n;
        }
      }
      return dst;
    }

    // ---- 放大：双线性插值 ----
    for (int oy = 0; oy < outH; oy++) {
      final fy = (sy + (oy + 0.5) * yRatio - 0.5).clamp(0.0, (srcH - 1).toDouble());
      final y0 = fy.floor();
      final y1 = (y0 + 1).clamp(0, srcH - 1);
      final wy = fy - y0;

      for (int ox = 0; ox < outW; ox++) {
        final fx = (sx + (ox + 0.5) * xRatio - 0.5).clamp(0.0, (srcW - 1).toDouble());
        final x0 = fx.floor();
        final x1 = (x0 + 1).clamp(0, srcW - 1);
        final wx = fx - x0;

        final di = (oy * outW + ox) * 4;
        final i00 = (y0 * srcW + x0) * 4;
        final i10 = (y0 * srcW + x1) * 4;
        final i01 = (y1 * srcW + x0) * 4;
        final i11 = (y1 * srcW + x1) * 4;

        for (int c = 0; c < 4; c++) {
          final top = s[i00 + c] * (1 - wx) + s[i10 + c] * wx;
          final bottom = s[i01 + c] * (1 - wx) + s[i11 + c] * wx;
          d[di + c] = (top * (1 - wy) + bottom * wy).round().clamp(0, 255);
        }
      }
    }
    return dst;
  }

  /// 在 [dst] 的 (dx, dy) 位置贴一张图（越界部分自动裁剪）。
  static void blit(
    PixelBuffer dst,
    PixelBuffer src,
    int dx,
    int dy, {
    bool skipTransparent = true,
  }) {
    final x0 = dx < 0 ? -dx : 0;
    final y0 = dy < 0 ? -dy : 0;
    final x1 = (dx + src.width > dst.width) ? dst.width - dx : src.width;
    final y1 = (dy + src.height > dst.height) ? dst.height - dy : src.height;
    if (x1 <= x0 || y1 <= y0) return;

    for (int y = y0; y < y1; y++) {
      var si = (y * src.width + x0) * 4;
      var di = ((y + dy) * dst.width + (x0 + dx)) * 4;
      for (int x = x0; x < x1; x++) {
        final a = src.rgba[si + 3];
        if (a == 255 || (a != 0 && !skipTransparent)) {
          dst.rgba[di] = src.rgba[si];
          dst.rgba[di + 1] = src.rgba[si + 1];
          dst.rgba[di + 2] = src.rgba[si + 2];
          dst.rgba[di + 3] = a;
        } else if (a != 0) {
          // 半透明：与底色做 alpha 混合
          final inv = 255 - a;
          dst.rgba[di] = (src.rgba[si] * a + dst.rgba[di] * inv) ~/ 255;
          dst.rgba[di + 1] = (src.rgba[si + 1] * a + dst.rgba[di + 1] * inv) ~/ 255;
          dst.rgba[di + 2] = (src.rgba[si + 2] * a + dst.rgba[di + 2] * inv) ~/ 255;
          dst.rgba[di + 3] = 255;
        }
        si += 4;
        di += 4;
      }
    }
  }

  /// 用纯色填充整张图。
  static void fillColor(PixelBuffer dst, int r, int g, int b, [int a = 255]) {
    final d = dst.rgba;
    for (int i = 0; i < d.length; i += 4) {
      d[i] = r;
      d[i + 1] = g;
      d[i + 2] = b;
      d[i + 3] = a;
    }
  }
}
