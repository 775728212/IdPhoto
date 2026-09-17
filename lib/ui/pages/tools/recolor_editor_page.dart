import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/bg_swatches.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pixel_buffer.dart';
import '../../../models/crop_session.dart';
import '../../../models/output_options.dart';
import '../../../models/recolor_state.dart';
import '../../../services/recolor_service.dart';
import '../../../services/segmentation_service.dart';
import '../../widgets/common.dart';
import '../../widgets/pixel_buffer_view.dart';
import 'crop_editor_page.dart';
import 'output_page.dart';

enum _Brush { none, pipette, background, foreground }

/// 换底色编辑器。
///
/// 「裁剪」在这里是**可选**的：默认直接拿原图换底，用户想去掉多余部分时
/// 再点上面的「裁剪」进 [CropEditorPage]。这样只想去蓝底的人不会被强塞
/// 一次裁剪流程。
class RecolorEditorPage extends StatefulWidget {
  const RecolorEditorPage({super.key, required this.session});

  final CropSession session;

  @override
  State<RecolorEditorPage> createState() => _RecolorEditorPageState();
}

class _RecolorEditorPageState extends State<RecolorEditorPage> {
  late final CropSession s = widget.session;
  late final RecolorState r = RecolorState(swatchId: s.spec.defaultSwatchId);

  bool _busy = false;
  bool _showOriginal = false;
  _Brush _brush = _Brush.none;
  double _brushRadius = 12;
  Offset? _lastBrushPoint;

  Timer? _debounce;
  DateTime _lastComposite = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ------------------------------------------------ 计算

  PixelBuffer _base() => s.baseImage;

  Future<void> _recompute() async {
    if (!mounted) return;
    setState(() => _busy = true);
    final PixelBuffer base = _base();
    final MaskResult result =
        await SegmentationService.buildMask(base, r.options);
    if (!mounted) return;
    r.mask = result;
    _composite();
    setState(() => _busy = false);
  }

  /// 只换底色，不重算掩膜。
  void _composite() {
    final MaskResult? mask = r.mask;
    if (mask == null) return;
    r.composited = RecolorService.apply(
      source: _base(),
      mask: mask.mask,
      swatch: r.swatch,
      originalBackgroundArgb: mask.backgroundArgb,
    );
  }

  void _onToleranceChanged(double value) {
    r.tolerance = value.round();
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), _recompute);
  }

  void _onSwatchChanged(BgSwatch swatch) {
    setState(() {
      r.swatch = swatch;
      _composite();
    });
  }

  void _onEdgeChanged({int? clean, int? feather}) {
    setState(() {
      if (clean != null) r.edgeClean = clean;
      if (feather != null) r.feather = feather;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), _recompute);
  }

  void _resetMask() {
    r.reset();
    _recompute();
  }

  // ------------------------------------------------ 裁剪

  /// 裁剪状态变了（启用 / 调整 / 恢复原图），掩膜必须重算。
  Future<void> _onCropChanged() async {
    r.invalidateMask();
    await _recompute();
  }

  // ------------------------------------------------ 交互

  Offset? _toImagePoint(Size box, Offset local) {
    final PixelBuffer img = _base();
    final Rect rect = containRect(
      box,
      Size(img.width.toDouble(), img.height.toDouble()),
    );
    if (rect.width <= 0) return null;
    final double scale = rect.width / img.width;
    final double x = (local.dx - rect.left) / scale;
    final double y = (local.dy - rect.top) / scale;
    if (x < 0 || y < 0 || x >= img.width || y >= img.height) return null;
    return Offset(x, y);
  }

  void _pickBackgroundColor(Size box, Offset local) {
    final Offset? p = _toImagePoint(box, local);
    if (p == null) return;
    final int argb = _base().argbAt(p.dx.round(), p.dy.round());
    r.seedColor = argb & 0xFFFFFF;
    _toast(
      '已取色 #${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}，'
      '正在重新识别',
    );
    _recompute();
  }

  void _applyBrush(Size box, Offset local, bool isStart) {
    final MaskResult? mask = r.mask;
    if (mask == null) return;
    final Offset? p = _toImagePoint(box, local);
    if (p == null) return;

    final bool asBackground = _brush == _Brush.background;
    final int radius = _brushRadius.round().clamp(2, 120);
    final Offset? prev = _lastBrushPoint;

    if (isStart || prev == null) {
      SegmentationService.stampCircle(
        mask.mask,
        mask.width,
        mask.height,
        p.dx.round(),
        p.dy.round(),
        radius,
        asBackground: asBackground,
      );
    } else {
      SegmentationService.stampLine(
        mask.mask,
        mask.width,
        mask.height,
        prev.dx,
        prev.dy,
        p.dx,
        p.dy,
        radius,
        asBackground: asBackground,
      );
    }
    _lastBrushPoint = p;

    // 逐帧重算合成会掉帧，限制在 ~25fps
    final DateTime now = DateTime.now();
    if (now.difference(_lastComposite).inMilliseconds >= 40) {
      _lastComposite = now;
      _composite();
    }
    setState(() {});
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _finish() {
    if (r.mask != null) _composite();
    final PixelBuffer output = r.outputOn(_base());
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OutputPage(
          image: output,
          baseName: outputBaseName(s.sourceName, r.swatch.name),
          title: '导出换底结果',
          transparent: r.transparentOutput,
          dpi: s.dpi,
          metaLabel: s.summaryLabel,
          shareText: '证件照（${r.swatch.name}底）已制作完成',
        ),
      ),
    );
  }

  // ------------------------------------------------ 视图

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更换底色'),
        actions: <Widget>[
          TextButton(
            onPressed: _resetMask,
            child: const Text('重新识别', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(child: _buildStage()),
          _buildPanel(),
        ],
      ),
    );
  }

  Widget _buildStage() {
    final PixelBuffer base = _base();
    final PixelBuffer preview = _showOriginal ? base : r.previewOn(base);

    return ColoredBox(
      color: AppColors.stage,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final Size box = Size(c.maxWidth, c.maxHeight);
          final bool brushing =
              _brush == _Brush.background || _brush == _Brush.foreground;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _brush == _Brush.pipette
                ? (TapUpDetails d) => _pickBackgroundColor(box, d.localPosition)
                : null,
            onLongPressStart: (LongPressStartDetails _) =>
                setState(() => _showOriginal = true),
            onLongPressEnd: (LongPressEndDetails _) =>
                setState(() => _showOriginal = false),
            onPanStart: brushing
                ? (DragStartDetails d) {
                    _lastBrushPoint = null;
                    _applyBrush(box, d.localPosition, true);
                  }
                : null,
            onPanUpdate: brushing
                ? (DragUpdateDetails d) =>
                    _applyBrush(box, d.localPosition, false)
                : null,
            onPanEnd: brushing
                ? (DragEndDetails _) {
                    _lastBrushPoint = null;
                    _composite();
                    setState(() {});
                  }
                : null,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: (r.enabled && r.swatch.transparent)
                        ? Checkerboard(
                            cell: 12,
                            child: PixelBufferView(buffer: preview),
                          )
                        : PixelBufferView(buffer: preview),
                  ),
                ),
                if (brushing && r.mask != null)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: CustomPaint(
                        painter: _MaskOverlayPainter(
                          mask: r.mask!.mask,
                          imageWidth: r.mask!.width,
                          imageHeight: r.mask!.height,
                          asBackground: _brush == _Brush.background,
                        ),
                      ),
                    ),
                  ),
                if (_busy)
                  const Positioned(
                    right: 16,
                    bottom: 16,
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                _buildHint(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHint() {
    return Positioned(
      left: 0,
      right: 0,
      top: 10,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            switch (_brush) {
              _Brush.pipette => '点击照片上的背景区域取色',
              _Brush.background => '涂抹要变成背景的区域（红色覆盖处）',
              _Brush.foreground => '涂抹要保留的人物区域（绿色覆盖处）',
              _Brush.none => '长按照片可对比原图',
            },
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final double maxPanelHeight = MediaQuery.of(context).size.height * 0.54;

    return Container(
      constraints: BoxConstraints(maxHeight: maxPanelHeight),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              CropHintCard(session: s, onChanged: _onCropChanged),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '智能换底色',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    r.enabled ? '已开启' : '已关闭',
                    style: TextStyle(
                      fontSize: 12.5,
                      color:
                          r.enabled ? AppColors.brand : AppColors.textTertiary,
                    ),
                  ),
                  Switch(
                    value: r.enabled,
                    onChanged: (bool v) => setState(() => r.enabled = v),
                  ),
                ],
              ),
              _StatusBar(mask: r.mask, swatch: r.swatch, enabled: r.enabled),
              const SizedBox(height: 12),
              const _SectionLabel('选择底色'),
              const SizedBox(height: 10),
              SwatchPicker(selected: r.swatch, onSelected: _onSwatchChanged),
              const SizedBox(height: 4),
              LabelSlider(
                label: '抠图容差',
                value: r.tolerance.toDouble(),
                min: 0,
                max: 80,
                onChanged: _onToleranceChanged,
                valueLabel: '${r.tolerance}',
                hint: '背景没抠干净就调大；人物被误当背景吃掉就调小',
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StepperBox(
                      label: '去边缘杂色',
                      value: r.edgeClean,
                      min: 0,
                      max: 4,
                      unit: 'px',
                      onChanged: (int v) => _onEdgeChanged(clean: v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StepperBox(
                      label: '边缘羽化',
                      value: r.feather,
                      min: 0,
                      max: 6,
                      unit: 'px',
                      onChanged: (int v) => _onEdgeChanged(feather: v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _SectionLabel('手动修补'),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  ToolButton(
                    icon: Icons.colorize_rounded,
                    label: '取色',
                    active: _brush == _Brush.pipette,
                    onTap: () => setState(() => _brush =
                        _brush == _Brush.pipette ? _Brush.none : _Brush.pipette),
                  ),
                  ToolButton(
                    icon: Icons.brush_rounded,
                    label: '涂背景',
                    active: _brush == _Brush.background,
                    onTap: () => setState(() => _brush = _brush == _Brush.background
                        ? _Brush.none
                        : _Brush.background),
                  ),
                  ToolButton(
                    icon: Icons.auto_fix_normal_rounded,
                    label: '抹前景',
                    active: _brush == _Brush.foreground,
                    onTap: () => setState(() => _brush = _brush == _Brush.foreground
                        ? _Brush.none
                        : _Brush.foreground),
                  ),
                  ToolButton(
                    icon: Icons.visibility_rounded,
                    label: '看原图',
                    active: _showOriginal,
                    onTap: () =>
                        setState(() => _showOriginal = !_showOriginal),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LabelSlider(
                label: '画笔大小',
                value: _brushRadius,
                min: 3,
                max: 40,
                onChanged: (double v) => setState(() => _brushRadius = v),
                valueLabel: '${_brushRadius.round()}px',
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _finish,
                child: const Text('下一步 · 导出'),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

// ------------------------------------------------ 子组件

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.mask,
    required this.swatch,
    this.enabled = true,
  });

  final MaskResult? mask;
  final BgSwatch swatch;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return const Row(
        children: <Widget>[
          Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: AppColors.textTertiary,
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              '已关闭换底色，将保留照片原有背景',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ],
      );
    }

    final MaskResult? m = mask;
    if (m == null) {
      return const Row(
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            '正在识别背景…',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      );
    }

    final double coverage = m.coverage;
    final bool suspicious = m.fallbackUsed || coverage < 0.08;
    final Color color = suspicious ? AppColors.warning : AppColors.success;
    final String text = suspicious
        ? '没找到明显背景，请用「涂背景」手动补一下'
        : '背景识别完成 · 背景占比 ${(coverage * 100).toStringAsFixed(0)}%'
            ' · 原底色 #${m.backgroundArgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

    return Row(
      children: <Widget>[
        Icon(
          suspicious ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12.5, color: color)),
        ),
        if (swatch.transparent)
          const InfoChip(
            icon: Icons.layers_rounded,
            text: '将导出 PNG',
            color: AppColors.brand,
          ),
      ],
    );
  }
}

/// 画笔模式下把掩膜以半透明色叠加显示。
class _MaskOverlayPainter extends CustomPainter {
  _MaskOverlayPainter({
    required this.mask,
    required this.imageWidth,
    required this.imageHeight,
    required this.asBackground,
  });

  final Uint8List mask;
  final int imageWidth;
  final int imageHeight;
  final bool asBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect target = containRect(
      size,
      Size(imageWidth.toDouble(), imageHeight.toDouble()),
    );
    if (target.width <= 0) return;

    // 逐格采样：既保留掩膜形状，也避免绘制上万个矩形。
    const double cell = 3;
    final int cols = (target.width / cell).ceil();
    final int rows = (target.height / cell).ceil();
    final double sampleScaleX = imageWidth / target.width;
    final double sampleScaleY = imageHeight / target.height;

    final Paint paint = Paint()
      ..color = (asBackground
              ? const Color(0xFFFF4D4F)
              : const Color(0xFF34D399))
          .withValues(alpha: 0.42);

    final Path path = Path();
    for (int y = 0; y < rows; y++) {
      final int sy =
          (y * cell * sampleScaleY).round().clamp(0, math.max(0, imageHeight - 1));
      for (int x = 0; x < cols; x++) {
        final int sx =
            (x * cell * sampleScaleX).round().clamp(0, math.max(0, imageWidth - 1));
        final int v = mask[sy * imageWidth + sx];
        // 「涂背景」时高亮背景；「抹前景」时高亮前景
        final bool highlight = asBackground ? v > 127 : v <= 127;
        if (!highlight) continue;
        path.addRect(
          Rect.fromLTWH(
            target.left + x * cell,
            target.top + y * cell,
            cell,
            cell,
          ),
        );
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MaskOverlayPainter oldDelegate) => true;
}
