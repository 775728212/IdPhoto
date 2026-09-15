import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 裁剪框（图像坐标系，单位像素）。
class CropFrame {
  const CropFrame({required this.x, required this.y, required this.width});

  final double x;
  final double y;
  final double width;

  double height(double aspect) => width / aspect;

  CropFrame copyWith({double? x, double? y, double? width}) => CropFrame(
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
      );

  @override
  String toString() => 'CropFrame(x=$x, y=$y, w=$width)';
}

/// 裁剪画布。
///
/// 设计要点：**取景框本身就是最终成片**——视口(viewfinder)按目标规格的宽高比
/// 呈现，框内所见即导出所得，不需要再额外画一个遮罩去表示"被裁掉的部分"。
/// 单指拖动 = 平移图片，双指捏合 = 缩放。
class CropCanvas extends StatefulWidget {
  const CropCanvas({
    super.key,
    required this.image,
    required this.viewport,
    required this.aspect,
    required this.imageWidth,
    required this.imageHeight,
    required this.frame,
    required this.minCropWidth,
    required this.maxCropWidth,
    required this.onFrameChanged,
    this.showGrid = true,
    this.showGuides = true,
  });

  final ui.Image image;
  final Size viewport;
  final double aspect;
  final int imageWidth;
  final int imageHeight;
  final CropFrame frame;
  final double minCropWidth;
  final double maxCropWidth;
  final ValueChanged<CropFrame> onFrameChanged;
  final bool showGrid;
  final bool showGuides;

  @override
  State<CropCanvas> createState() => _CropCanvasState();
}

class _CropCanvasState extends State<CropCanvas> {
  late double _startWidth;
  late Offset _startFocal;
  late double _anchorX;
  late double _anchorY;

  void _onScaleStart(ScaleStartDetails details) {
    _startWidth = widget.frame.width;
    _startFocal = details.localFocalPoint;
    final double s = widget.viewport.width / _startWidth;
    // 记录起始焦点对应的图像坐标，缩放时保持该点不动
    _anchorX = widget.frame.x + _startFocal.dx / s;
    _anchorY = widget.frame.y + _startFocal.dy / s;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final double rawWidth = _startWidth / details.scale;
    final double newWidth =
        rawWidth.clamp(widget.minCropWidth, widget.maxCropWidth);
    final double s = widget.viewport.width / newWidth;
    final Offset focal = details.localFocalPoint;

    double nx = _anchorX - focal.dx / s;
    double ny = _anchorY - focal.dy / s;

    final double newHeight = newWidth / widget.aspect;
    nx = nx.clamp(0.0, (widget.imageWidth - newWidth).clamp(0.0, double.infinity));
    ny = ny.clamp(0.0, (widget.imageHeight - newHeight).clamp(0.0, double.infinity));

    widget.onFrameChanged(CropFrame(x: nx, y: ny, width: newWidth));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: SizedBox(
        width: widget.viewport.width,
        height: widget.viewport.height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            painter: _CropPainter(
              image: widget.image,
              frame: widget.frame,
              aspect: widget.aspect,
              viewport: widget.viewport,
              showGrid: widget.showGrid,
              showGuides: widget.showGuides,
            ),
            size: widget.viewport,
          ),
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.frame,
    required this.aspect,
    required this.viewport,
    required this.showGrid,
    required this.showGuides,
  });

  final ui.Image image;
  final CropFrame frame;
  final double aspect;
  final Size viewport;
  final bool showGrid;
  final bool showGuides;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / frame.width;

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    // 图片按裁剪框的映射关系铺满取景框
    final Rect src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final Rect dst = Rect.fromLTWH(
      -frame.x * s,
      -frame.y * s,
      image.width * s,
      image.height * s,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );

    if (showGrid) _paintGrid(canvas, size);
    if (showGuides) _paintGuides(canvas, size);

    canvas.restore();

    _paintCorners(canvas, size);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.8;
    for (int i = 1; i <= 2; i++) {
      final double dx = size.width * i / 3;
      final double dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  /// 证件照构图参考线：头顶留白 ~10%，下巴位置 ~62%。
  void _paintGuides(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = const Color(0xFF34D399).withValues(alpha: 0.9)
      ..strokeWidth = 1.2;
    final double top = size.height * 0.10;
    final double chin = size.height * 0.62;
    _dashLine(canvas, Offset(0, top), Offset(size.width, top), paint);
    _dashLine(canvas, Offset(0, chin), Offset(size.width, chin), paint);
  }

  void _dashLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const double dash = 6;
    const double gap = 5;
    final double total = (b - a).distance;
    if (total <= 0) return;
    final Offset dir = (b - a) / total;
    double travelled = 0;
    while (travelled < total) {
      final double end = (travelled + dash).clamp(0, total);
      canvas.drawLine(a + dir * travelled, a + dir * end, paint);
      travelled = end + gap;
    }
  }

  /// 四角白色直角标记。
  void _paintCorners(Canvas canvas, Size size) {
    const double len = 22;
    const double inset = 1.5;
    final Paint paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final double r = size.width;
    final double b = size.height;

    // 左上
    canvas.drawLine(Offset(inset, len), Offset(inset, inset), paint);
    canvas.drawLine(Offset(inset, inset), Offset(len, inset), paint);
    // 右上
    canvas.drawLine(Offset(r - len, inset), Offset(r - inset, inset), paint);
    canvas.drawLine(Offset(r - inset, inset), Offset(r - inset, len), paint);
    // 左下
    canvas.drawLine(Offset(inset, b - len), Offset(inset, b - inset), paint);
    canvas.drawLine(Offset(inset, b - inset), Offset(len, b - inset), paint);
    // 右下
    canvas.drawLine(Offset(r - len, b - inset), Offset(r - inset, b - inset), paint);
    canvas.drawLine(Offset(r - inset, b - inset), Offset(r - inset, b - len), paint);
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) =>
      oldDelegate.frame.x != frame.x ||
      oldDelegate.frame.y != frame.y ||
      oldDelegate.frame.width != frame.width ||
      oldDelegate.aspect != aspect ||
      oldDelegate.image != image ||
      oldDelegate.showGrid != showGrid ||
      oldDelegate.showGuides != showGuides;
}
