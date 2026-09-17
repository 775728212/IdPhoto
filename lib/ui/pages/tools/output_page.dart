import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pixel_buffer.dart';
import '../../../models/output_options.dart';
import '../../../services/encode_service.dart';
import '../../../services/export_service.dart';
import '../../widgets/common.dart';
import '../../widgets/output_settings_card.dart';
import '../../widgets/pixel_buffer_view.dart';
import '../../widgets/save_bar.dart';

/// 所有工具的最后一个环节：预览 → 输出设置 → 保存 / 分享。
///
/// 裁剪、压缩、换底、水印四条链路都汇到这里，差别只在传进来的图和
/// 初始选项（[preferTargetSize] 让「压缩大小」一进来就按体积压）。
class OutputPage extends StatefulWidget {
  const OutputPage({
    super.key,
    required this.image,
    required this.baseName,
    required this.title,
    this.transparent = false,
    this.dpi = 300,
    this.allowResize = false,
    this.preferTargetSize = false,
    this.metaLabel = '',
    this.shareText = '证件照已制作完成',
    this.album = '证件照',
  });

  /// 待输出的像素图（已应用过裁剪 / 换底 / 水印）。
  final PixelBuffer image;

  /// 输出文件名前缀，不含扩展名。
  final String baseName;

  final String title;

  /// 待输出图是否含透明像素。
  final bool transparent;

  final int dpi;

  /// 是否显示「限制尺寸」。
  final bool allowResize;

  /// 初始压缩方式是否为「按体积」。
  final bool preferTargetSize;

  /// 成片信息里「规格」一栏的展示文本。
  final String metaLabel;

  final String shareText;
  final String album;

  @override
  State<OutputPage> createState() => _OutputPageState();
}

class _OutputPageState extends State<OutputPage> {
  late final OutputOptions options = OutputOptions(
    targetKb: widget.preferTargetSize ? 50 : null,
  );

  late PixelBuffer _prepared = widget.image;
  EncodedImage? _encoded;

  bool _busy = false;
  String _busyLabel = '正在处理';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reencode());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleReencode() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _reencode);
  }

  void _onOptionsChanged() {
    setState(() {});
    _scheduleReencode();
  }

  Future<void> _reencode() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _busyLabel = '正在压缩';
    });

    final PixelBuffer prepared = options.prepare(widget.image);
    final EncodedImage result = await options.encodePrepared(
      prepared,
      transparent: widget.transparent,
    );
    if (!mounted) return;

    setState(() {
      _prepared = prepared;
      _encoded = result;
      _busy = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runBusy(
    String label,
    Future<void> Function() action,
    String successMessage,
  ) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await action();
      if (mounted) _toast(successMessage);
    } catch (error) {
      if (mounted) _toast('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final EncodedImage? e = _encoded;
    if (e == null) return;
    await _runBusy(
      '正在保存到相册',
      () => ExportService.saveToGallery(e, album: widget.album),
      '已保存到相册「${widget.album}」',
    );
  }

  Future<void> _share() async {
    final EncodedImage? e = _encoded;
    if (e == null) return;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    await _runBusy(
      '正在准备分享',
      () => ExportService.share(
        e,
        baseName: widget.baseName,
        text: widget.shareText,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
      '已调起分享',
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool png = options.resolvePng(transparent: widget.transparent);
    final bool showChecker = png && widget.transparent;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: <Widget>[
              _buildPreview(showChecker),
              const SizedBox(height: 14),
              _buildInfoCard(),
              const SizedBox(height: 14),
              OutputSettingsCard(
                options: options,
                transparent: widget.transparent,
                encoded: _encoded,
                onChanged: _onOptionsChanged,
                allowResize: widget.allowResize,
              ),
              const SizedBox(height: 18),
              SaveBar(
                enabled: _encoded != null && !_busy,
                onSave: _save,
                onShare: _share,
                footer: TextButton(
                  onPressed: () => Navigator.of(context)
                      .popUntil((Route<dynamic> route) => route.isFirst),
                  child: const Text(
                    '回到工具箱',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
          if (_busy) Positioned.fill(child: BusyOverlay(label: _busyLabel)),
        ],
      ),
    );
  }

  Widget _buildPreview(bool showChecker) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: AppColors.stage,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      padding: const EdgeInsets.all(20),
      child: showChecker
          ? Checkerboard(cell: 12, child: PixelBufferView(buffer: _prepared))
          : PixelBufferView(buffer: _prepared),
    );
  }

  Widget _buildInfoCard() {
    final EncodedImage? e = _encoded;
    return SectionCard(
      title: '成片信息',
      trailing: InfoChip(
        icon: Icons.aspect_ratio_rounded,
        text: '${_prepared.width}×${_prepared.height}',
        color: AppColors.brand,
      ),
      child: Row(
        children: <Widget>[
          StatTile(
            label: '规格',
            value: widget.metaLabel.isEmpty ? widget.title : widget.metaLabel,
          ),
          StatTile(label: '分辨率', value: '${widget.dpi} DPI'),
          StatTile(
            label: '格式',
            value: options.resolvePng(transparent: widget.transparent)
                ? 'PNG'
                : 'JPG ${options.quality}',
          ),
          StatTile(
            label: '文件体积',
            value: e == null ? '计算中' : e.sizeLabel,
            highlight: true,
          ),
        ],
      ),
    );
  }
}
