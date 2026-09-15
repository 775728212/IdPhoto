import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/constants/bg_swatches.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pixel_buffer.dart';
import '../../models/edit_session.dart';
import '../../services/recolor_service.dart';
import '../../services/segmentation_service.dart';
import '../widgets/common.dart';
import '../widgets/pixel_buffer_view.dart';
import 'export_page.dart';

enum _Tool { none, pipette, brushBackground, brushForeground }

class BackgroundPage extends StatefulWidget {
  const BackgroundPage({super.key, required this.session});

  final EditSession session;

  @override
  State<BackgroundPage> createState() => _BackgroundPageState();
}

class _BackgroundPageState extends State<BackgroundPage> {
  late final EditSession s = widget.session;

  bool _busy = false;
  bool _showOriginal = false;
  _Tool _tool = _Tool.none;
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

  /// 重新计算掩膜（抠图）。
  Future<void> _recompute() async {
    if (!mounted) return;
    setState(() => _busy = true);
    final PixelBuffer base = s.renderCrop();
    final MaskResult result =
        await SegmentationService.buildMask(base, s.segmentOptions);
    if (!mounted) return;
    s.mask = result;
    _composite();
    setState(() => _busy = false);
  }

  /// 只换底色，不重算掩膜。
  void _composite() {
    final MaskResult? mask = s.mask;
    if (mask == null) return;
    s.composited = RecolorService.apply(
      source: s.renderCrop(),
      mask: mask.mask,
      swatch: s.swatch,
      originalBackgroundArgb: mask.backgroundArgb,
    );
    s.invalidateEncoded();
  }

  void _onToleranceChanged(double value) {
    s.tolerance = value.round();
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), _recompute);
  }

  void _onSwatchChanged(BgSwatch swatch) {
    setState(() {
      s.swatch = swatch;
      _composite();
    });
  }

  void _onEdgeChanged({int? clean, int? feather}) {
    setState(() {
      if (clean != null) s.edgeClean = clean;
      if (feather != null) s.feather = feather;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 140), _recompute);
  }

  void _resetMask() {
    s.seedColor = null;
    s.tolerance = 34;
    s.edgeClean = 1;
    s.feather = 1;
    s.invalidateMask();
    _recompute();
  }

  // ------------------------------------------------ 交互

  Offset? _toImagePoint(Size box, Offset local) {
    final PixelBuffer img = s.baseImage;
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
    final PixelBuffer img = s.baseImage;
    final int argb = img.argbAt(p.dx.round(), p.dy.round());
    s.seedColor = argb & 0xFFFFFF;
    _toast(
      '已取色 #${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}，正在重新识别',
    );
    _recompute();
  }

  void _applyBrush(Size box, Offset local, bool isStart) {
    final MaskResult? mask = s.mask;
    if (mask == null) return;
    final Offset? p = _toImagePoint(box, local);
    if (p == null) return;

    final bool asBackground = _tool == _Tool.brushBackground;
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

    // 逐帧重算合成会掉帧，这里限制在 ~25fps
    final DateTime now = DateTime.now();
    if (now.difference(_lastComposite).inMilliseconds >= 40) {
      _lastComposite = now;
      _composite();
      setState(() {});
    } else {
      setState(() {});
    }
  }

  void _next() {
    if (s.mask != null) _composite();
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => ExportPage(session: s)),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
    final PixelBuffer preview =
        _showOriginal ? s.baseImage : s.previewImage;

    return ColoredBox(
      color: AppColors.stage,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final Size box = Size(c.maxWidth, c.maxHeight);
          final bool brushing =
              _tool == _Tool.brushBackground || _tool == _Tool.brushForeground;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: _tool == _Tool.pipette
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
                ? (DragUpdateDetails d) => _applyBrush(box, d.localPosition, false)
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
                    child: (s.bgEnabled && s.swatch.transparent)
                        ? Checkerboard(
                            cell: 12,
                            child: PixelBufferView(buffer: preview),
                          )
                        : PixelBufferView(buffer: preview),
                  ),
                ),
                if (brushing && s.mask != null)
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: CustomPaint(
                        painter: _MaskOverlayPainter(
                          mask: s.mask!.mask,
                          imageWidth: s.mask!.width,
                          imageHeight: s.mask!.height,
                          asBackground: _tool == _Tool.brushBackground,
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
                Positioned(
                  left: 0,
                  right: 0,
                  top: 10,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _hintText(),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _hintText() => switch (_tool) {
        _Tool.pipette => '点击照片上的背景区域取色',
        _Tool.brushBackground => '涂抹要变成背景的区域（红色覆盖处）',
        _Tool.brushForeground => '涂抹要保留的人物区域（绿色覆盖处）',
        _Tool.none => '长按照片可对比原图',
      };

  Widget _buildPanel() {
    final MaskResult? mask = s.mask;
    final double maxPanelHeight = MediaQuery.of(context).size.height * 0.52;

    return Container(
      constraints: BoxConstraints(maxHeight: maxPanelHeight),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Color(0x14000000), blurRadius: 18, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
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
                    s.bgEnabled ? '已开启' : '已关闭',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: s.bgEnabled
                          ? AppColors.brand
                          : AppColors.textTertiary,
                    ),
                  ),
                  Switch(
                    value: s.bgEnabled,
                    onChanged: (bool v) {
                      setState(() {
                        s.bgEnabled = v;
                        s.invalidateEncoded();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 2),
              _StatusBar(
                mask: mask,
                swatch: s.swatch,
                enabled: s.bgEnabled,
              ),
              const SizedBox(height: 12),
              const Text(
                '选择底色',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              SwatchPicker(selected: s.swatch, onSelected: _onSwatchChanged),
              const SizedBox(height: 4),
              LabelSlider(
                label: '抠图容差',
                value: s.tolerance.toDouble(),
                min: 0,
                max: 80,
                onChanged: _onToleranceChanged,
                valueLabel: '${s.tolerance}',
                hint: '背景没抠干净就调大；人物被误当背景吃掉就调小',
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _Stepper(
                      label: '去边缘杂色',
                      value: s.edgeClean,
                      min: 0,
                      max: 4,
                      unit: 'px',
                      onChanged: (int v) => _onEdgeChanged(clean: v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Stepper(
                      label: '边缘羽化',
                      value: s.feather,
                      min: 0,
                      max: 6,
                      unit: 'px',
                      onChanged: (int v) => _onEdgeChanged(feather: v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                '手动修补',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  _ToolButton(
                    icon: Icons.colorize_rounded,
                    label: '取色',
                    active: _tool == _Tool.pipette,
                    onTap: () => setState(() => _tool =
                        _tool == _Tool.pipette ? _Tool.none : _Tool.pipette),
                  ),
                  _ToolButton(
                    icon: Icons.brush_rounded,
                    label: '涂背景',
                    active: _tool == _Tool.brushBackground,
                    onTap: () => setState(() => _tool = _tool == _Tool.brushBackground
                        ? _Tool.none
                        : _Tool.brushBackground),
                  ),
                  _ToolButton(
                    icon: Icons.auto_fix_normal_rounded,
                    label: '抹前景',
                    active: _tool == _Tool.brushForeground,
                    onTap: () => setState(() => _tool =
                        _tool == _Tool.brushForeground ? _Tool.none : _Tool.brushForeground),
                  ),
                  _ToolButton(
                    icon: Icons.visibility_rounded,
                    label: '看原图',
                    active: _showOriginal,
                    onTap: () => setState(() => _showOriginal = !_showOriginal),
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
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _next,
                child: const Text('下一步 · 压缩导出'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------ 子组件

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
          Icon(Icons.info_outline_rounded, size: 15, color: AppColors.textTertiary),
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

    if (mask == null) {
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

    final double coverage = mask!.coverage;
    final bool suspicious = mask!.fallbackUsed || coverage < 0.08;
    final Color color = suspicious ? AppColors.warning : AppColors.success;
    final String text = suspicious
        ? '没找到明显背景，请用「涂背景」手动补一下'
        : '背景识别完成 · 背景占比 ${(coverage * 100).toStringAsFixed(0)}%'
            ' · 原底色 #${mask!.backgroundArgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

    return Row(
      children: <Widget>[
        Icon(
          suspicious ? Icons.error_outline_rounded : Icons.check_circle_rounded,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12.5, color: color),
          ),
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

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final Color color = active ? AppColors.brand : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: active ? AppColors.brandSoft : AppColors.pageBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? AppColors.brand : Colors.transparent,
                ),
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.unit = '',
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$value$unit',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          _MiniButton(
            icon: Icons.remove_rounded,
            enabled: value > min,
            onTap: () => onChanged(math.max(min, value - 1)),
          ),
          _MiniButton(
            icon: Icons.add_rounded,
            enabled: value < max,
            onTap: () => onChanged(math.min(max, value + 1)),
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 26,
        height: 26,
        margin: const EdgeInsets.only(left: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }
}

/// 画笔模式下把掩膜以半透明红色叠加显示。
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
    final Rect target = containRect(size, Size(imageWidth.toDouble(), imageHeight.toDouble()));
    if (target.width <= 0) return;

    // 逐格采样：既保留了掩膜的形状信息，也避免绘制上万个矩形。
    const double cell = 3;
    final int cols = (target.width / cell).ceil();
    final int rows = (target.height / cell).ceil();
    final double sampleScaleX = imageWidth / target.width;
    final double sampleScaleY = imageHeight / target.height;

    final Paint paint = Paint()
      ..color = (asBackground ? const Color(0xFFFF4D4F) : const Color(0xFF34D399))
          .withValues(alpha: 0.42);

    final Path path = Path();
    for (int y = 0; y < rows; y++) {
      final int sy = (y * cell * sampleScaleY).round().clamp(0, imageHeight - 1);
      for (int x = 0; x < cols; x++) {
        final int sx = (x * cell * sampleScaleX).round().clamp(0, imageWidth - 1);
        final int v = mask[sy * imageWidth + sx];
        // 「涂背景」时高亮背景；「抹前景」时高亮前景
        final bool highlight = asBackground ? v > 127 : v <= 127;
        if (!highlight) continue;
        path.addRect(Rect.fromLTWH(
          target.left + x * cell,
          target.top + y * cell,
          cell,
          cell,
        ));
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MaskOverlayPainter oldDelegate) => true;
}
