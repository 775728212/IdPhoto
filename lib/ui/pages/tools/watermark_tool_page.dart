import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pixel_buffer.dart';
import '../../../models/crop_session.dart';
import '../../../models/output_options.dart';
import '../../../services/watermark_service.dart';
import '../../widgets/common.dart';
import '../../widgets/pixel_buffer_view.dart';
import '../../widgets/save_bar.dart';
import 'crop_editor_page.dart';
import 'output_page.dart';

/// 水印可选颜色。
class _InkColor {
  const _InkColor(this.name, this.argb);

  final String name;
  final int argb;

  Color get color => Color(0xFF000000 | argb);
}

const List<_InkColor> _inkColors = <_InkColor>[
  _InkColor('白色', 0xFFFFFF),
  _InkColor('黑色', 0x000000),
  _InkColor('红色', 0xD9001B),
  _InkColor('蓝色', 0x2563EB),
  _InkColor('灰色', 0x9CA3AF),
];

/// 加水印工具。
///
/// 文字、字号、颜色、不透明度、排版（平铺斜排 / 居中 / 底部横条 / 右下角）
/// 全部可调，改动后防抖重绘预览。裁剪同样是可选的。
class WatermarkToolPage extends StatefulWidget {
  const WatermarkToolPage({super.key, required this.session});

  final CropSession session;

  @override
  State<WatermarkToolPage> createState() => _WatermarkToolPageState();
}

class _WatermarkToolPageState extends State<WatermarkToolPage> {
  late final CropSession s = widget.session;

  final WatermarkOptions _options = WatermarkOptions();
  final TextEditingController _textController =
      TextEditingController(text: WatermarkOptions().text);

  PixelBuffer? _preview;
  bool _busy = false;
  bool _showOriginal = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  PixelBuffer _base() => s.baseImage;

  Future<void> _recompute() async {
    if (!mounted) return;
    setState(() => _busy = true);
    final PixelBuffer base = _base();
    final PixelBuffer result = await WatermarkService.apply(base, _options);
    if (!mounted) return;
    setState(() {
      _preview = result;
      _busy = false;
    });
  }

  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 160), _recompute);
  }

  void _touch() {
    setState(() {});
    _scheduleRecompute();
  }

  Future<void> _onCropChanged() async {
    _preview = null;
    await _recompute();
  }

  void _finish() {
    final PixelBuffer base = _base();
    final PixelBuffer output = _preview ?? base;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OutputPage(
          image: output,
          baseName: outputBaseName(s.sourceName, '水印'),
          title: '导出带水印照片',
          dpi: s.dpi,
          metaLabel: s.summaryLabel,
          shareText: '已添加水印的照片',
        ),
      ),
    );
  }

  // ------------------------------------------------ 视图

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('加水印'),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              _options
                ..fontSizeRatio = 0.055
                ..opacity = 0.45
                ..colorArgb = 0xFFFFFF
                ..bold = true
                ..layout = WatermarkLayout.diagonalTile
                ..tileSpacing = 0.35;
              _touch();
            },
            child: const Text('重置样式', style: TextStyle(fontSize: 13.5)),
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
    final PixelBuffer preview = _preview ?? base;

    return ColoredBox(
      color: AppColors.stage,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (LongPressStartDetails _) =>
            setState(() => _showOriginal = true),
        onLongPressEnd: (LongPressEndDetails _) =>
            setState(() => _showOriginal = false),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: PixelBufferView(
                  buffer: _showOriginal ? base : preview,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _showOriginal ? '原图（松手回到预览）' : '长按可对比原图',
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
      ),
    );
  }

  Widget _buildPanel() {
    final double maxPanelHeight = MediaQuery.of(context).size.height * 0.56;

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
              const _Label('水印文字'),
              const SizedBox(height: 8),
              TextField(
                controller: _textController,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onChanged: (String v) {
                  _options.text = v;
                  _touch();
                },
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.pageBg,
                  hintText: '例如：仅供办理居住证使用',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    color: AppColors.textTertiary,
                    onPressed: () {
                      _textController.clear();
                      _options.text = '';
                      _touch();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const _Label('排版方式'),
              const SizedBox(height: 10),
              ChipRow<WatermarkLayout>(
                items: WatermarkLayout.values,
                labelOf: (WatermarkLayout l) => l.label,
                selected: _options.layout,
                onSelected: (WatermarkLayout l) {
                  _options.layout = l;
                  _touch();
                },
              ),
              if (_options.layout == WatermarkLayout.diagonalTile) ...<Widget>[
                const SizedBox(height: 4),
                LabelSlider(
                  label: '平铺间距',
                  value: _options.tileSpacing,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (double v) {
                    _options.tileSpacing = v;
                    _touch();
                  },
                  valueLabel: '${(_options.tileSpacing * 100).round()}%',
                  hint: '调小更密，防盗用更强；调大更疏，看着更干净',
                ),
              ],
              if (_options.layout == WatermarkLayout.bottomBar) ...<Widget>[
                const SizedBox(height: 4),
                const _Note('底部横条会在画面下方压一条半透明黑带，底色选「白色」最清楚。'),
              ],
              const SizedBox(height: 8),
              LabelSlider(
                label: '字号',
                value: _options.fontSizeRatio,
                min: 0.02,
                max: 0.16,
                divisions: 28,
                onChanged: (double v) {
                  _options.fontSizeRatio = v;
                  _touch();
                },
                valueLabel: '${(_base().width * _options.fontSizeRatio).round()}px',
                hint: '按图片宽度比例计算，换一张图大小观感一致',
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: LabelSlider(
                      label: '不透明度',
                      value: _options.opacity,
                      min: 0.05,
                      max: 1,
                      divisions: 19,
                      onChanged: (double v) {
                        _options.opacity = v;
                        _touch();
                      },
                      valueLabel: '${(_options.opacity * 100).round()}%',
                    ),
                  ),
                  const SizedBox(width: 4),
                  _BoldToggle(
                    value: _options.bold,
                    onChanged: (bool v) {
                      _options.bold = v;
                      _touch();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _Label('水印颜色'),
              const SizedBox(height: 10),
              _buildColorRow(),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _options.canRender ? _finish : null,
                child: const Text('下一步 · 导出'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorRow() {
    return Row(
      children: _inkColors.map((_InkColor ink) {
        final bool active = ink.argb == _options.colorArgb;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: ink == _inkColors.last ? 0 : 8,
            ),
            child: GestureDetector(
              onTap: () {
                _options.colorArgb = ink.argb;
                _touch();
              },
              child: Column(
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 42,
                    decoration: BoxDecoration(
                      color: ink.color,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active
                            ? AppColors.brand
                            : AppColors.divider,
                        width: active ? 2.5 : 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    ink.name,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w400,
                      color: active
                          ? AppColors.brand
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ------------------------------------------------ 子组件

class _Label extends StatelessWidget {
  const _Label(this.text);

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

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          height: 1.55,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _BoldToggle extends StatelessWidget {
  const _BoldToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Text(
          '加粗',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
