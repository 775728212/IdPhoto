import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/pixel_buffer.dart';
import '../../models/edit_session.dart';
import '../../services/encode_service.dart';
import '../../services/export_service.dart';
import '../../services/layout_service.dart';
import '../widgets/common.dart';
import '../widgets/pixel_buffer_view.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key, required this.session});

  final EditSession session;

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  late final EditSession s = widget.session;

  bool _busy = false;
  String _busyLabel = '正在处理';
  EncodedImage? _encoded;
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

  Future<void> _reencode() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _busyLabel = '正在压缩';
    });

    final PixelBuffer source = s.outputImage;
    EncodedImage result;
    if (s.asPng) {
      result = EncodeService.encodePng(source);
    } else if (s.sizeLocked) {
      result = await EncodeService.compressToTargetSize(
        source,
        s.targetKb! * 1024,
      );
    } else {
      result = await EncodeService.encodeJpegAsync(source, s.quality);
    }

    if (!mounted) return;
    s.encoded = result;
    setState(() {
      _encoded = result;
      _busy = false;
    });
  }

  void _scheduleReencode() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), _reencode);
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
      () => ExportService.saveToGallery(e),
      '已保存到相册「证件照」',
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
        baseName: s.fileBaseName,
        text: '${s.spec.name}证件照（${s.spec.mmLabel}）',
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
      '已调起分享',
    );
  }

  Future<void> _openSheetMaker() async {
    final _SheetChoice? choice = await showModalBottomSheet<_SheetChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SheetMakerSheet(session: s),
    );
    if (choice == null || !mounted) return;

    await _runBusy(
      '正在生成排版图纸',
      () async {
        final SheetLayout layout = LayoutService.buildSheet(
          s.outputImage,
          copies: choice.copies,
          paper: choice.paper,
          dpi: s.dpi,
          cutLines: choice.cutLines,
        );
        final EncodedImage encoded = EncodeService.encodeJpeg(layout.sheet, 94);
        await ExportService.saveToGallery(encoded, album: '证件照');
      },
      '排版图纸已保存到相册「证件照」',
    );
  }

  @override
  Widget build(BuildContext context) {
    final EncodedImage? e = _encoded;

    return Scaffold(
      appBar: AppBar(title: const Text('压缩导出')),
      body: Stack(
        children: <Widget>[
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: <Widget>[
              _buildPreview(),
              const SizedBox(height: 14),
              _buildInfoCard(e),
              const SizedBox(height: 14),
              _buildFormatCard(),
              const SizedBox(height: 14),
              _buildCompressCard(e),
              const SizedBox(height: 14),
              _buildSheetCard(),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: e == null || _busy ? null : _save,
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text('保存到相册'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: e == null || _busy ? null : _share,
                icon: const Icon(Icons.ios_share_rounded, size: 19),
                label: const Text('分享给他人'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .popUntil((Route<dynamic> route) => route.isFirst),
                child: const Text('重新制作一张', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          if (_busy) Positioned.fill(child: BusyOverlay(label: _busyLabel)),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final bool transparent = s.asPng && s.bgEnabled && s.swatch.transparent;
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: AppColors.stage,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      padding: const EdgeInsets.all(20),
      child: transparent
          ? Checkerboard(cell: 12, child: PixelBufferView(buffer: s.outputImage))
          : PixelBufferView(buffer: s.outputImage),
    );
  }

  Widget _buildInfoCard(EncodedImage? e) {
    return SectionCard(
      title: '成片信息',
      trailing: InfoChip(
        icon: Icons.aspect_ratio_rounded,
        text: '${s.spec.pixelWidth(s.dpi)}×${s.spec.pixelHeight(s.dpi)}',
        color: AppColors.brand,
      ),
      child: Row(
        children: <Widget>[
          _StatTile(label: '规格', value: s.spec.name),
          _StatTile(label: '物理尺寸', value: s.spec.mmLabel),
          _StatTile(label: '分辨率', value: '${s.dpi} DPI'),
          _StatTile(
            label: '文件体积',
            value: e == null ? '计算中' : e.sizeLabel,
            highlight: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFormatCard() {
    final bool forced = s.bgEnabled && s.swatch.transparent;
    return SectionCard(
      title: '输出格式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _FormatTile(
                  title: 'JPG',
                  desc: '体积小，通用',
                  selected: !s.asPng,
                  onTap: forced
                      ? null
                      : () {
                          setState(() => s.forcePng = false);
                          _scheduleReencode();
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FormatTile(
                  title: 'PNG',
                  desc: '无损，可透明',
                  selected: s.asPng,
                  onTap: () {
                    setState(() => s.forcePng = true);
                    _scheduleReencode();
                  },
                ),
              ),
            ],
          ),
          if (forced) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              '当前底色为「透明」，只能导出 PNG。',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompressCard(EncodedImage? e) {
    if (s.asPng) {
      return const SectionCard(
        title: '压缩',
        child: Text(
          'PNG 为无损格式，体积由像素尺寸决定。若要压缩体积，请切换到 JPG。',
          style: TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSecondary),
        ),
      );
    }

    final bool locked = s.sizeLocked;
    return SectionCard(
      title: '压缩方式',
      trailing: Text(
        locked ? '按目标体积' : '按画质',
        style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _FormatTile(
                  title: '按画质',
                  desc: '手动调质量',
                  selected: !locked,
                  onTap: () {
                    setState(() => s.targetKb = null);
                    _scheduleReencode();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FormatTile(
                  title: '按体积',
                  desc: '自动卡上限',
                  selected: locked,
                  onTap: () {
                    setState(() => s.targetKb = s.targetKb ?? 50);
                    _scheduleReencode();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!locked)
            LabelSlider(
              label: 'JPEG 画质',
              value: s.quality.toDouble(),
              min: 30,
              max: 98,
              onChanged: (double v) {
                setState(() => s.quality = v.round());
                _scheduleReencode();
              },
              valueLabel: '${s.quality}',
              hint: '数值越低体积越小，证件照一般 85~95 肉眼无差别',
            )
          else ...<Widget>[
            const Text(
              '目标体积上限',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <int>[20, 30, 50, 100, 200, 500].map((int kb) {
                final bool active = s.targetKb == kb;
                return GestureDetector(
                  onTap: () {
                    setState(() => s.targetKb = kb);
                    _scheduleReencode();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: active ? AppColors.brand : AppColors.pageBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '≤ $kb KB',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        color: active ? Colors.white : AppColors.textSecondary,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _TargetResult(targetKb: s.targetKb!, encoded: e),
          ],
        ],
      ),
    );
  }

  Widget _buildSheetCard() {
    return SectionCard(
      title: '排版打印',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '把同一张证件照在一张相纸上排多份，附裁切线，直接拿去冲印店打印。',
            style: TextStyle(fontSize: 12.5, height: 1.6, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openSheetMaker,
            icon: const Icon(Icons.grid_view_rounded, size: 19),
            label: const Text('生成排版图纸'),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------ 子组件

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: highlight ? AppColors.brand : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String desc;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandSoft : AppColors.pageBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brand : Colors.transparent,
              width: 1.4,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.brandDark : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetResult extends StatelessWidget {
  const _TargetResult({required this.targetKb, required this.encoded});

  final int targetKb;
  final EncodedImage? encoded;

  @override
  Widget build(BuildContext context) {
    if (encoded == null) {
      return const Text(
        '正在计算…',
        style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      );
    }

    final int actual = encoded!.byteSize;
    final int target = targetKb * 1024;
    final bool ok = actual <= target;
    final Color color = ok ? AppColors.success : AppColors.warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok
                  ? '已压到 ${encoded!.sizeLabel}（上限 $targetKb KB，画质 ${encoded!.quality}）'
                  : '该尺寸下最低画质仍有 ${encoded!.sizeLabel}，无法压到 $targetKb KB 以内',
              style: TextStyle(fontSize: 12.5, color: color, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------ 排版设置面板

class _SheetChoice {
  const _SheetChoice({
    required this.copies,
    required this.paper,
    required this.cutLines,
  });

  final int copies;
  final PaperSize paper;
  final bool cutLines;
}

class _SheetMakerSheet extends StatefulWidget {
  const _SheetMakerSheet({required this.session});

  final EditSession session;

  @override
  State<_SheetMakerSheet> createState() => _SheetMakerSheetState();
}

class _SheetMakerSheetState extends State<_SheetMakerSheet> {
  int _copies = 8;
  PaperSize _paper = PaperSize.sixInch;
  bool _cutLines = true;

  @override
  void initState() {
    super.initState();
    _copies = widget.session.sheetCopies;
    _cutLines = widget.session.sheetCutLines;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '排版打印设置',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '张数',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <int>[1, 2, 4, 6, 8, 10, 12, 16].map((int n) {
                  final bool active = _copies == n;
                  return GestureDetector(
                    onTap: () => setState(() => _copies = n),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(
                        color: active ? AppColors.brand : AppColors.surface,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$n 张',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                          color: active ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const Text(
                '相纸',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <PaperSize>[PaperSize.fiveInch, PaperSize.sixInch]
                    .map((PaperSize p) {
                  final bool active = p.name == _paper.name;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: p.name == PaperSize.fiveInch.name ? 8 : 0,
                        left: p.name == PaperSize.sixInch.name ? 8 : 0,
                      ),
                      child: GestureDetector(
                        onTap: () => setState(() => _paper = p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? AppColors.brand : AppColors.surface,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w500,
                              color: active
                                  ? Colors.white
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _cutLines,
                onChanged: (bool v) => setState(() => _cutLines = v),
                title: const Text(
                  '显示裁切线',
                  style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                ),
                subtitle: const Text(
                  '每张照片外框一条浅灰线，方便裁剪',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  widget.session.sheetCopies = _copies;
                  widget.session.sheetCutLines = _cutLines;
                  Navigator.of(context).pop(
                    _SheetChoice(
                      copies: _copies,
                      paper: _paper,
                      cutLines: _cutLines,
                    ),
                  );
                },
                child: const Text('生成并保存'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
