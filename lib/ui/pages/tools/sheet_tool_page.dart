import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/photo_specs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pixel_buffer.dart';
import '../../../models/crop_session.dart';
import '../../../services/encode_service.dart';
import '../../../services/export_service.dart';
import '../../../services/image_loader.dart';
import '../../../services/layout_service.dart';
import '../../../services/photo_picker.dart';
import '../../widgets/photo_source_sheet.dart';
import '../../widgets/pixel_buffer_view.dart';
import '../../widgets/save_bar.dart';
import '../../widgets/spec_picker_sheet.dart';
import 'crop_editor_page.dart';
import 'output_page.dart';

/// 拼图的两种玩法。
enum SheetMode {
  /// 同一张照片在相纸上重复排多份。
  repeatSingle,

  /// 多张**互不相同**的照片拼到一张相纸上。
  mixed,
}

/// 拼图 / 排版工具。
///
/// 两种模式共用同一套「相纸 + 间距 + 裁切线 → 逐格等比贴图」逻辑，
/// 区别只在照片列表怎么来：单张重复是把同一张图排多份，多张混排是
/// 每张图各自裁剪后按格子铺开（[LayoutService.buildMixedSheet]）。
class SheetToolPage extends StatefulWidget {
  const SheetToolPage({
    super.key,
    required this.photos,
    required this.mode,
    this.initialSpecId = 'one_inch',
  });

  final List<LoadedPhoto> photos;
  final SheetMode mode;

  /// 每张照片默认裁剪到的规格。
  final String initialSpecId;

  @override
  State<SheetToolPage> createState() => _SheetToolPageState();
}

class _SheetToolPageState extends State<SheetToolPage> {
  /// 预览用的相纸分辨率。真正的成片在保存时按 300 DPI 重算 ——
  /// 排版几何与 DPI 无关，所以预览所见与最终成品一致，但重算量小一个数量级。
  static const int _previewDpi = 130;

  late final List<CropSession> _sessions = widget.photos
      .map(
        (LoadedPhoto p) => CropSession(
          source: p.buffer,
          sourceName: p.name,
          spec: PhotoSpecs.byId(widget.initialSpecId),
          cropEnabled: true,
        ),
      )
      .toList();

  int _copies = 8;
  PaperSize _paper = PaperSize.sixInch;
  bool _cutLines = true;
  int _gap = 8;

  SheetLayout? _preview;
  bool _busy = false;
  Timer? _debounce;

  bool get _single => widget.mode == SheetMode.repeatSingle;

  @override
  void initState() {
    super.initState();
    _copies = _single ? 8 : _sessions.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPreview());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ------------------------------------------------ 排版计算

  SheetLayout _build(int dpi) {
    if (_single) {
      final CropSession s = _sessions.first;
      return LayoutService.buildSheet(
        s.renderCrop(),
        copies: _copies,
        paper: _paper,
        dpi: dpi,
        gap: _gap,
        cutLines: _cutLines,
      );
    }
    return LayoutService.buildMixedSheet(
      _sessions.map((CropSession s) => s.renderCrop()).toList(),
      paper: _paper,
      dpi: dpi,
      gap: _gap,
      cutLines: _cutLines,
    );
  }

  Future<void> _refreshPreview() async {
    if (!mounted || _sessions.isEmpty) return;
    setState(() => _busy = true);
    final SheetLayout layout = _build(_previewDpi);
    if (!mounted) return;
    setState(() {
      _preview = layout;
      _busy = false;
    });
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _refreshPreview);
  }

  void _touch() {
    setState(() {});
    _schedule();
  }

  // ------------------------------------------------ 照片管理

  Future<void> _cropOne(int index) async {
    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CropEditorPage(
          session: _sessions[index],
          title: _single ? '裁剪照片' : '裁剪第 ${index + 1} 张',
        ),
      ),
    );
    if (done != true || !mounted) return;
    await _refreshPreview();
  }

  Future<void> _changeSpec() async {
    final PhotoSpec? picked =
        await showSpecPicker(context, _sessions.first.spec);
    if (picked == null || !mounted) return;
    setState(() {
      for (final CropSession s in _sessions) {
        s.setSpec(picked);
        s.ensureCropInitialized();
      }
    });
    await _refreshPreview();
  }

  Future<void> _reselectSingle() async {
    final ImageSource? source =
        await showPhotoSourceSheet(context, title: '换一张照片');
    if (source == null || !mounted) return;
    try {
      setState(() => _busy = true);
      final LoadedPhoto? photo = await PhotoPicker.pickOne(source: source);
      if (!mounted) return;
      if (photo == null) {
        setState(() => _busy = false);
        return;
      }
      _sessions[0] = CropSession(
        source: photo.buffer,
        sourceName: photo.name,
        spec: PhotoSpecs.byId(widget.initialSpecId),
        cropEnabled: true,
      );
      setState(() => _busy = false);
      await _refreshPreview();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('$error');
    }
  }

  Future<void> _addMore() async {
    const int maxPhotos = 12;
    if (_sessions.length >= maxPhotos) {
      _toast('最多 $maxPhotos 张，再多一张相纸也排不下');
      return;
    }
    try {
      final PhotoBatch batch =
          await PhotoPicker.pickMany(limit: maxPhotos - _sessions.length);
      if (!mounted || batch.isEmpty) return;
      setState(() {
        for (final LoadedPhoto p in batch.photos) {
          _sessions.add(
            CropSession(
              source: p.buffer,
              sourceName: p.name,
              spec: PhotoSpecs.byId(widget.initialSpecId),
              cropEnabled: true,
            ),
          );
        }
      });
      if (batch.skipped > 0) _toast('有 ${batch.skipped} 张图片无法解析，已跳过');
      await _refreshPreview();
    } catch (error) {
      if (mounted) _toast('$error');
    }
  }

  void _removeAt(int index) {
    if (_sessions.length <= 1) return;
    setState(() => _sessions.removeAt(index));
    _schedule();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------ 导出

  Future<void> _runBusy(
    String label,
    Future<void> Function(SheetLayout full) action,
    String successMessage,
  ) async {
    setState(() => _busy = true);
    try {
      final SheetLayout full = _build(300);
      await action(full);
      if (mounted) _toast(successMessage);
    } catch (error) {
      if (mounted) _toast('$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    await _runBusy(
      '正在生成排版图纸',
      (SheetLayout full) async {
        final EncodedImage encoded = EncodeService.encodeJpeg(full.sheet, 94);
        await ExportService.saveToGallery(
          encoded,
          album: '证件照',
          baseName: '排版_${full.cols}x${full.rows}',
        );
      },
      '排版图纸已保存到相册「证件照」',
    );
  }

  Future<void> _share() async {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    await _runBusy(
      '正在准备分享',
      (SheetLayout full) async {
        final EncodedImage encoded = EncodeService.encodeJpeg(full.sheet, 94);
        await ExportService.share(
          encoded,
          baseName: '排版_${full.cols}x${full.rows}',
          text: '证件照排版图纸（${full.gridLabel}）',
          sharePositionOrigin:
              box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        );
      },
      '已调起分享',
    );
  }

  /// 把排版好的图纸再送去「导出设置」压体积 —— 冲印店常要求单文件不超过多少 KB。
  void _openOutput() {
    if (_preview == null) return;
    final SheetLayout full = _build(300);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => OutputPage(
          image: full.sheet,
          baseName: '排版_${full.cols}x${full.rows}',
          title: '排版图纸压缩',
          dpi: 300,
          allowResize: true,
          metaLabel: '${_paper.name} · ${full.gridLabel}',
          shareText: '证件照排版图纸（${full.gridLabel}）',
        ),
      ),
    );
  }

  // ------------------------------------------------ 视图

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_single ? '一张照片印多份' : '多张照片拼一张'),
        actions: <Widget>[
          TextButton(
            onPressed: _changeSpec,
            child: const Text('更换规格', style: TextStyle(fontSize: 13.5)),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              Expanded(child: _buildStage()),
              _buildPanel(),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: const Color(0x33000000),
                  child: const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    final SheetLayout? layout = _preview;

    return ColoredBox(
      color: AppColors.stage,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            Expanded(
              child: layout == null
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Center(
                      child: AspectRatio(
                        aspectRatio:
                            layout.sheet.width / layout.sheet.height,
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: const <BoxShadow>[
                              BoxShadow(
                                color: Color(0x66000000),
                                blurRadius: 16,
                                offset: Offset(0, 6),
                              ),
                            ],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: PixelBufferView(
                              buffer: layout.sheet,
                              filterQuality: FilterQuality.medium,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              layout == null
                  ? '正在排版…'
                  : '${_paper.name} · ${layout.gridLabel}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanel() {
    final double maxPanelHeight = MediaQuery.of(context).size.height * 0.5;

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
              if (!_single) _buildPhotoStrip(),
              if (_single) _buildSinglePhotoRow(),
              const SizedBox(height: 16),
              if (_single) ...<Widget>[
                const _Label('打印张数'),
                const SizedBox(height: 10),
                ChipRow<int>(
                  items: const <int>[1, 2, 4, 6, 8, 10, 12, 16],
                  labelOf: (int n) => '$n 张',
                  selected: _copies,
                  onSelected: (int n) {
                    _copies = n;
                    _touch();
                  },
                ),
                const SizedBox(height: 16),
              ],
              const _Label('相纸'),
              const SizedBox(height: 10),
              Row(
                children: PaperSize.presets.map((PaperSize p) {
                  final bool active = p.name == _paper.name;
                  final bool first = p == PaperSize.presets.first;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: first ? 0 : 8),
                      child: GestureDetector(
                        onTap: () {
                          _paper = p;
                          _touch();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color:
                                active ? AppColors.brand : AppColors.pageBg,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            p.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w500,
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
              const SizedBox(height: 16),
              const _Label('间距与裁切线'),
              const SizedBox(height: 10),
              ChipRow<int>(
                items: const <int>[0, 4, 8, 16, 24],
                labelOf: (int g) => g == 0 ? '无间距' : '$g px',
                selected: _gap,
                onSelected: (int g) {
                  _gap = g;
                  _touch();
                },
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _cutLines,
                onChanged: (bool v) {
                  _cutLines = v;
                  _touch();
                },
                title: const Text(
                  '显示裁切线',
                  style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                ),
                subtitle: const Text(
                  '每张照片外框一条浅灰线，方便裁剪',
                  style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _preview == null || _busy ? null : _save,
                icon: const Icon(Icons.download_rounded, size: 20),
                label: const Text('保存排版图纸'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _preview == null || _busy ? null : _share,
                icon: const Icon(Icons.ios_share_rounded, size: 19),
                label: const Text('分享给他人'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _preview == null || _busy ? null : _openOutput,
                icon: const Icon(Icons.compress_rounded, size: 19),
                label: const Text('压缩这张图纸'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .popUntil((Route<dynamic> route) => route.isFirst),
                child: const Text(
                  '回到工具箱',
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSinglePhotoRow() {
    final CropSession s = _sessions.first;
    final PixelBuffer cropped = s.renderCrop();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 54,
            height: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: PixelBufferView(buffer: cropped),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  s.spec.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${s.spec.mmLabel} · ${s.spec.pxLabel(s.dpi)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    _MiniAction(
                      icon: Icons.crop_rounded,
                      label: '裁剪',
                      onTap: () => _cropOne(0),
                    ),
                    const SizedBox(width: 8),
                    _MiniAction(
                      icon: Icons.swap_horiz_rounded,
                      label: '换照片',
                      onTap: _reselectSingle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '照片（${_sessions.length} 张）',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: _addMore,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('＋ 添加', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _sessions.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int index) {
              final CropSession s = _sessions[index];
              return _PhotoThumb(
                session: s,
                index: index,
                onCrop: () => _cropOne(index),
                onRemove: _sessions.length > 1
                    ? () => _removeAt(index)
                    : null,
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '点缩略图可逐张裁剪。每张会按 ${_sessions.first.spec.name}'
          '（${_sessions.first.spec.mmLabel}）输出后拼到同一张相纸上。',
          style: const TextStyle(
            fontSize: 11.5,
            height: 1.55,
            color: AppColors.textTertiary,
          ),
        ),
      ],
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

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: AppColors.brand),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.session,
    required this.index,
    required this.onCrop,
    this.onRemove,
  });

  final CropSession session;
  final int index;
  final VoidCallback onCrop;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: Column(
        children: <Widget>[
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onCrop,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.stage,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: PixelBufferView(buffer: session.renderCrop()),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 3,
                  top: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (onRemove != null)
                  Positioned(
                    right: 1,
                    top: 1,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            session.cropEnabled ? session.spec.name : '原图',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
