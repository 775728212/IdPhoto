import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/utils/pixel_buffer.dart';

/// 水印排版方式。
enum WatermarkLayout {
  /// 斜向平铺，铺满整张图，防盗用效果最强。
  diagonalTile('平铺斜排'),

  /// 单条居中。
  center('居中'),

  /// 底部半透明横条 + 文字。
  bottomBar('底部横条'),

  /// 右下角。
  corner('右下角');

  const WatermarkLayout(this.label);

  final String label;
}

/// 水印参数。[fontSizeRatio] 与各间距都按**图宽比例**表达，
/// 这样同一套参数在 295px 的小图和 2400px 的原图上观感一致。
class WatermarkOptions {
  WatermarkOptions({
    this.text = '仅供办理证件使用',
    this.fontSizeRatio = 0.055,
    this.opacity = 0.45,
    this.colorArgb = 0xFFFFFF,
    this.bold = true,
    this.layout = WatermarkLayout.diagonalTile,
    this.tileSpacing = 0.35,
    this.barColorArgb = 0x000000,
  });

  String text;
  double fontSizeRatio;
  double opacity;
  int colorArgb;
  bool bold;
  WatermarkLayout layout;
  double tileSpacing;
  int barColorArgb;

  bool get canRender => text.trim().isNotEmpty;
}

/// 往照片上叠加水印。
///
/// 实现上刻意**不用** `package:image` 自带的位图字体 —— 那套字体只有 ASCII，
/// 中文会直接画成方块，而中文恰恰是证件照水印最常用的（「仅供办理 XX 使用」）。
/// 这里改成用 Flutter 的 [TextPainter] 把文字画进一层全透明画布，回读像素后
/// 再用 [ImageOps.blit] 与原图做 alpha 合成，中英文都正常。
class WatermarkService {
  WatermarkService._();

  static Future<PixelBuffer> apply(
    PixelBuffer source,
    WatermarkOptions options,
  ) async {
    if (!options.canRender) return source.clone();

    final int w = source.width;
    final int h = source.height;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );

    final TextPainter painter = _layoutPainter(w, options);
    switch (options.layout) {
      case WatermarkLayout.diagonalTile:
        _paintTile(canvas, painter, w, h, options);
      case WatermarkLayout.center:
        painter.paint(
          canvas,
          Offset((w - painter.width) / 2, (h - painter.height) / 2),
        );
      case WatermarkLayout.bottomBar:
        _paintBottomBar(canvas, painter, w, h, options);
      case WatermarkLayout.corner:
        final double margin = w * 0.035;
        painter.paint(
          canvas,
          Offset(w - painter.width - margin, h - painter.height - margin),
        );
    }

    final ui.Image image = await recorder.endRecording().toImage(w, h);
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return source.clone();

    final Uint8List raw =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final PixelBuffer overlay =
        PixelBuffer(w, h, _unpremultiply(raw, w * h));

    final PixelBuffer out = source.clone();
    ImageOps.blit(out, overlay, 0, 0);
    return out;
  }

  // ------------------------------------------------ 文字

  static TextPainter _layoutPainter(int imageWidth, WatermarkOptions options) {
    final double fontSize = (imageWidth * options.fontSizeRatio).clamp(8.0, 400.0);
    return TextPainter(
      text: TextSpan(
        text: options.text.trim(),
        style: TextStyle(
          color: Color(0xFF000000 | (options.colorArgb & 0xFFFFFF))
              .withValues(alpha: options.opacity.clamp(0.02, 1.0)),
          fontSize: fontSize,
          fontWeight: options.bold ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: fontSize * 0.10,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  // ------------------------------------------------ 各排版

  static void _paintTile(
    Canvas canvas,
    TextPainter painter,
    int w,
    int h,
    WatermarkOptions options,
  ) {
    const double rot = math.pi / 6; // 逆时针 30°
    final double diag = math.sqrt(w * w + h * h.toDouble());
    final double extra = diag * (0.03 + 0.20 * options.tileSpacing.clamp(0.0, 1.0));

    // 旋转 30° 之后，一条横排文字实际占用的纵向高度是这样的。
    final double lineExtentY =
        painter.height * math.cos(rot) + painter.width * math.sin(rot);
    final double stepX = painter.width + extra;
    final double stepY = lineExtentY + extra * 0.9;

    final int cols = (diag / stepX).ceil() + 2;
    final int rows = (diag / stepY).ceil() + 2;
    final double halfW = painter.width / 2;
    final double halfH = painter.height / 2;

    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(-rot);
    for (int row = -rows; row <= rows; row++) {
      // 奇数行错开半格，免得斜排之后出现一条条明显的竖向空档
      final double stagger = row.isOdd ? stepX / 2 : 0;
      final double dy = row * stepY;
      for (int col = -cols; col <= cols; col++) {
        final double dx = col * stepX + stagger;
        painter.paint(canvas, Offset(dx - halfW, dy - halfH));
      }
    }
    canvas.restore();
  }

  static void _paintBottomBar(
    Canvas canvas,
    TextPainter painter,
    int w,
    int h,
    WatermarkOptions options,
  ) {
    final double barHeight = painter.height + w * 0.045;
    final Rect bar = Rect.fromLTWH(0, h - barHeight, w.toDouble(), barHeight);
    canvas.drawRect(
      bar,
      Paint()
        ..color = Color(0xFF000000 | (options.barColorArgb & 0xFFFFFF))
            .withValues(alpha: (options.opacity * 0.85).clamp(0.02, 1.0)),
    );
    painter.paint(
      canvas,
      Offset(
        (w - painter.width) / 2,
        h - barHeight + (barHeight - painter.height) / 2,
      ),
    );
  }

  // ------------------------------------------------ 像素回读

  /// `ImageByteFormat.rawRgba` 给的是**预乘 alpha** 的数据，
  /// 直接当普通 RGBA 去混会偏暗（半透明浅色文字尤其明显），先还原。
  static Uint8List _unpremultiply(Uint8List raw, int pixelCount) {
    final Uint8List out = Uint8List(pixelCount * 4);
    final int limit = math.min(raw.length, out.length);
    for (int i = 0; i + 3 < limit; i += 4) {
      final int a = raw[i + 3];
      if (a == 0) continue; // 全透明像素留 0 即可
      if (a == 255) {
        out[i] = raw[i];
        out[i + 1] = raw[i + 1];
        out[i + 2] = raw[i + 2];
      } else {
        out[i] = math.min(255, raw[i] * 255 ~/ a);
        out[i + 1] = math.min(255, raw[i + 1] * 255 ~/ a);
        out[i + 2] = math.min(255, raw[i + 2] * 255 ~/ a);
      }
      out[i + 3] = a;
    }
    return out;
  }
}
