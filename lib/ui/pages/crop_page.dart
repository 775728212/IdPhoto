import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/constants/photo_specs.dart';
import '../../core/theme/app_theme.dart';
import '../../models/edit_session.dart';
import '../widgets/common.dart';
import '../widgets/crop_canvas.dart';
import '../widgets/pixel_buffer_view.dart';
import '../widgets/spec_picker_sheet.dart';
import 'background_page.dart';

class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.session});

  final EditSession session;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  late final EditSession s = widget.session;

  ui.Image? _image;
  bool _showGuides = true;
  bool _showGrid = true;

  @override
  void initState() {
    super.initState();
    s.ensureCropInitialized();
    _decode();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final ui.Image decoded = await pixelBufferToUiImage(s.working);
    if (!mounted) {
      decoded.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = decoded;
    });
  }

  Future<void> _applyTransform({int? rotateDelta, bool? flip}) async {
    s.mutateTransform(rotateDelta: rotateDelta, flip: flip);
    s.ensureCropInitialized();
    setState(() {});
    await _decode();
  }

  Future<void> _changeSpec() async {
    final PhotoSpec? picked = await showSpecPicker(context, s.spec);
    if (picked == null || !mounted) return;
    setState(() {
      s.spec = picked;
      s.ensureCropInitialized();
      s.invalidateMask();
    });
  }

  void _next() {
    s.renderCrop(force: true);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => BackgroundPage(session: s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('调整裁剪'),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              s.resetTransform();
              await _applyTransform();
            },
            child: const Text('重置', style: TextStyle(fontSize: 13.5)),
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
    return ColoredBox(
      color: AppColors.stage,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final ui.Image? image = _image;
          if (image == null) {
            return const Center(
              child: SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              ),
            );
          }

          const double pad = 30;
          final double maxW = math.max(140.0, c.maxWidth - pad * 2);
          final double maxH = math.max(180.0, c.maxHeight - pad * 2);
          final double aspect = s.spec.aspectRatio;

          final double vw;
          final double vh;
          if (maxW / maxH > aspect) {
            vh = maxH;
            vw = vh * aspect;
          } else {
            vw = maxW;
            vh = vw / aspect;
          }

          final CropFrame frame = CropFrame(
            x: s.cropX,
            y: s.cropY,
            width: s.cropW,
          );

          return Stack(
            children: <Widget>[
              Center(
                child: CropCanvas(
                  image: image,
                  viewport: Size(vw, vh),
                  aspect: aspect,
                  imageWidth: s.working.width,
                  imageHeight: s.working.height,
                  frame: frame,
                  minCropWidth: s.minCropW,
                  maxCropWidth: s.maxCropW,
                  showGrid: _showGrid,
                  showGuides: _showGuides,
                  onFrameChanged: (CropFrame f) {
                    setState(() {
                      s.setCrop(x: f.x, y: f.y, w: f.width);
                    });
                  },
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '双指缩放 · 拖动调整  ${s.zoom.toStringAsFixed(1)}×',
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
          );
        },
      ),
    );
  }

  Widget _buildPanel() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Color(0x14000000), blurRadius: 18, offset: Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    const Text(
                      '证件规格',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _changeSpec,
                      child: const Row(
                        children: <Widget>[
                          Text(
                            '更换',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.brand,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: AppColors.brand),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
                              '${s.spec.name} · ${s.spec.mmLabel}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '裁剪 ${s.cropW.round()}×${s.cropH.round()}px'
                              '  →  输出 ${s.spec.pxLabel(s.dpi)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InfoChip(
                        icon: Icons.hd_rounded,
                        text: '${s.dpi} DPI',
                        color: AppColors.brand,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: <Widget>[
                    _ToolButton(
                      icon: Icons.rotate_90_degrees_ccw_rounded,
                      label: '左转',
                      onTap: () => _applyTransform(rotateDelta: -1),
                    ),
                    _ToolButton(
                      icon: Icons.rotate_90_degrees_cw_rounded,
                      label: '右转',
                      onTap: () => _applyTransform(rotateDelta: 1),
                    ),
                    _ToolButton(
                      icon: Icons.flip_rounded,
                      label: '镜像',
                      onTap: () => _applyTransform(flip: !s.flipH),
                      active: s.flipH,
                    ),
                    _ToolButton(
                      icon: Icons.center_focus_strong_rounded,
                      label: '构图线',
                      onTap: () => setState(() => _showGuides = !_showGuides),
                      active: _showGuides,
                    ),
                    _ToolButton(
                      icon: Icons.grid_on_rounded,
                      label: '网格',
                      onTap: () => setState(() => _showGrid = !_showGrid),
                      active: _showGrid,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton(
                  onPressed: _next,
                  child: const Text('下一步 · 换底色'),
                ),
              ),
            ],
          ),
        ),
      ),
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active ? AppColors.brandSoft : AppColors.pageBg,
                borderRadius: BorderRadius.circular(12),
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
