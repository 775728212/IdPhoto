import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/utils/pixel_buffer.dart';

/// 把 [PixelBuffer] 转成 Flutter 可绘制的 [ui.Image]。
Future<ui.Image> pixelBufferToUiImage(PixelBuffer buffer) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    buffer.rgba,
    buffer.width,
    buffer.height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// 一个会缓存 [ui.Image] 的像素预览组件。
///
/// `PixelBuffer` 用对象标识（identity）作为缓存键：只要上游没有产生新对象，
/// 就不会重新解码，因此拖动滑块时不会反复做无谓的 GPU 上传。
class PixelBufferView extends StatefulWidget {
  const PixelBufferView({
    super.key,
    required this.buffer,
    this.fit = BoxFit.contain,
    this.filterQuality = FilterQuality.medium,
    this.alignment = Alignment.center,
  });

  final PixelBuffer? buffer;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Alignment alignment;

  @override
  State<PixelBufferView> createState() => _PixelBufferViewState();
}

class _PixelBufferViewState extends State<PixelBufferView> {
  ui.Image? _image;
  PixelBuffer? _decodedFrom;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(PixelBufferView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.buffer, widget.buffer)) {
      _decode();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final PixelBuffer? buffer = widget.buffer;
    final int token = ++_token;
    if (buffer == null) {
      setState(() {
        _image?.dispose();
        _image = null;
        _decodedFrom = null;
      });
      return;
    }

    final ui.Image image = await pixelBufferToUiImage(buffer);
    if (!mounted || token != _token) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _decodedFrom = buffer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;
    if (image == null || _decodedFrom != widget.buffer) {
      return const SizedBox.expand(
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return RawImage(
      image: image,
      fit: widget.fit,
      filterQuality: widget.filterQuality,
      alignment: widget.alignment,
    );
  }
}

/// 透明底预览用的棋盘格背景。
class Checkerboard extends StatelessWidget {
  const Checkerboard({super.key, this.cell = 10, required this.child});

  final double cell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerboardPainter(cell),
      child: child,
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  _CheckerboardPainter(this.cell);

  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint light = Paint()..color = const Color(0xFFFFFFFF);
    final Paint dark = Paint()..color = const Color(0xFFE9ECF2);
    canvas.drawRect(Offset.zero & size, light);

    final int cols = (size.width / cell).ceil();
    final int rows = (size.height / cell).ceil();
    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < cols; x++) {
        if ((x + y).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) =>
      oldDelegate.cell != cell;
}

/// 在 [box] 内按 [BoxFit.contain] 摆放 [imageSize]，返回实际绘制矩形。
Rect containRect(Size box, Size imageSize) {
  if (box.isEmpty || imageSize.isEmpty) return Rect.zero;
  final double scale = (box.width / imageSize.width) < (box.height / imageSize.height)
      ? box.width / imageSize.width
      : box.height / imageSize.height;
  final double w = imageSize.width * scale;
  final double h = imageSize.height * scale;
  return Rect.fromLTWH((box.width - w) / 2, (box.height - h) / 2, w, h);
}

/// 把 [Uint8List] 的 RGBA 数据编码为 PNG（用于导出排版图纸）。
Future<Uint8List> pixelBufferToPngBytes(PixelBuffer buffer) async {
  final ui.Image image = await pixelBufferToUiImage(buffer);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}
