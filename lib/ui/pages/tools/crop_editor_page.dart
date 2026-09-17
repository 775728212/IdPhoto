import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/constants/photo_specs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pixel_buffer.dart';
import '../../../models/crop_session.dart';
import '../../widgets/common.dart';
import '../../widgets/crop_canvas.dart';
import '../../widgets/pixel_buffer_view.dart';
import '../../widgets/spec_picker_sheet.dart';

/// 裁剪编辑器。
///
/// 三个工具共用它：「裁剪大小」把它当主界面；「换底色」「加水印」把它当
/// 子页面推出来，用户点「完成」后才把裁剪结果算出来。
///
/// 关闭时返回 `true` 表示用户确认了裁剪；返回 `null` 表示放弃（调用方
/// 应自行决定是保持原状还是中止流程）。
class CropEditorPage extends StatefulWidget {
  const CropEditorPage({
    super.key,
    required this.session,
    this.title = '裁剪尺寸',
    this.doneLabel = '完成裁剪',
  });

  final CropSession session;
  final String title;
  final String doneLabel;

  @override
  State<CropEditorPage> createState() => _CropEditorPageState();
}

class _CropEditorPageState extends State<CropEditorPage> {
  late final CropSession s = widget.session;

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
      s.setSpec(picked);
      s.ensureCropInitialized();
    });
  }

  void _done() {
    s.cropEnabled = true;
    s.renderCrop(force: true);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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

          return Stack(
            children: <Widget>[
              Center(
                child: CropCanvas(
                  image: image,
                  viewport: Size(vw, vh),
                  aspect: aspect,
                  imageWidth: s.working.width,
                  imageHeight: s.working.height,
                  frame: CropFrame(x: s.cropX, y: s.cropY, width: s.cropW),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
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
    final double maxPanelHeight = MediaQuery.of(context).size.height * 0.44;

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
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '证件规格',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
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
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.brand,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildSpecSummary(),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  ToolButton(
                    icon: Icons.rotate_90_degrees_ccw_rounded,
                    label: '左转',
                    onTap: () => _applyTransform(rotateDelta: -1),
                  ),
                  ToolButton(
                    icon: Icons.rotate_90_degrees_cw_rounded,
                    label: '右转',
                    onTap: () => _applyTransform(rotateDelta: 1),
                  ),
                  ToolButton(
                    icon: Icons.flip_rounded,
                    label: '镜像',
                    onTap: () => _applyTransform(flip: !s.flipH),
                    active: s.flipH,
                  ),
                  ToolButton(
                    icon: Icons.center_focus_strong_rounded,
                    label: '构图线',
                    onTap: () => setState(() => _showGuides = !_showGuides),
                    active: _showGuides,
                  ),
                  ToolButton(
                    icon: Icons.grid_on_rounded,
                    label: '网格',
                    onTap: () => setState(() => _showGrid = !_showGrid),
                    active: _showGrid,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton(onPressed: _done, child: Text(widget.doneLabel)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
    );
  }
}

/// 「裁剪（可选）」条。
///
/// 换底色 / 加水印这类不做裁剪也能用的工具，都在面板顶部放它：
/// 平时显示当前用的是原图还是裁剪结果，点一下才进 [CropEditorPage]。
class CropHintCard extends StatelessWidget {
  const CropHintCard({
    super.key,
    required this.session,
    required this.onChanged,
  });

  final CropSession session;

  /// 裁剪状态发生变化（启用 / 调整 / 恢复原图）后回调。
  final VoidCallback onChanged;

  Future<void> _openCrop(BuildContext context) async {
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CropEditorPage(session: session, title: '裁剪底图'),
      ),
    );
    if (done == true) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final PixelBuffer base = session.baseImage;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.crop_rounded,
            size: 17,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '裁剪（可选）',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  session.cropEnabled
                      ? '已裁剪 · ${session.spec.name} '
                          '${base.width}×${base.height}px'
                      : '使用原图 ${base.width}×${base.height}px',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _openCrop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              session.cropEnabled ? '调整' : '去裁剪',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (session.cropEnabled)
            TextButton(
              onPressed: () {
                session.cropEnabled = false;
                onChanged();
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '用原图',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
