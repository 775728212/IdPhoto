import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/photo_specs.dart';
import '../../core/theme/app_theme.dart';
import '../../models/crop_session.dart';
import '../../models/output_options.dart';
import '../../services/image_loader.dart';
import '../../services/photo_picker.dart';
import '../widgets/common.dart';
import '../widgets/photo_source_sheet.dart';
import 'tools/crop_editor_page.dart';
import 'tools/output_page.dart';
import 'tools/recolor_editor_page.dart';
import 'tools/sheet_tool_page.dart';
import 'tools/watermark_tool_page.dart';

/// 工具箱首页。
///
/// 这里**不是**流程的第一步，而是五个互不相干的工具的入口：
/// 裁剪大小 / 压缩大小 / 换底色 / 加水印 / 拼图。想只压体积就直接点压缩，
/// 不会被迫先走一遍裁剪和换底。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _busy = false;
  String _busyLabel = '正在读取照片';

  /// 默认规格。各工具里都可以再换。
  static const String _defaultSpecId = 'one_inch';

  // ------------------------------------------------ 公共动作

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<LoadedPhoto?> _pickSingle({required String title}) async {
    final ImageSource? source =
        await showPhotoSourceSheet(context, title: title);
    if (source == null || !mounted) return null;

    try {
      setState(() {
        _busy = true;
        _busyLabel = '正在读取照片';
      });
      final LoadedPhoto? photo = await PhotoPicker.pickOne(source: source);
      if (!mounted) return null;
      setState(() => _busy = false);
      return photo;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _busy = false);
      _toast('$error');
      return null;
    }
  }

  Future<PhotoBatch?> _pickMany({required String busyLabel}) async {
    try {
      setState(() {
        _busy = true;
        _busyLabel = busyLabel;
      });
      final PhotoBatch batch = await PhotoPicker.pickMany(limit: 12);
      if (!mounted) return null;
      setState(() => _busy = false);
      if (batch.isEmpty) return null;
      if (batch.skipped > 0) {
        _toast('有 ${batch.skipped} 张图片无法解析，已跳过');
      }
      return batch;
    } catch (error) {
      if (!mounted) return null;
      setState(() => _busy = false);
      _toast('$error');
      return null;
    }
  }

  Future<void> _push(Widget page) async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }

  // ------------------------------------------------ 五个工具

  /// 裁剪大小：选图 → 裁剪编辑器 → 导出。
  Future<void> _openCrop() async {
    final LoadedPhoto? photo = await _pickSingle(title: '选择要裁剪的照片');
    if (photo == null || !mounted) return;

    final CropSession session = CropSession(
      source: photo.buffer,
      sourceName: photo.name,
      spec: PhotoSpecs.byId(_defaultSpecId),
    );

    final bool? done = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CropEditorPage(session: session),
      ),
    );
    if (done != true || !mounted) return;

    await _push(
      OutputPage(
        image: session.baseImage,
        baseName: outputBaseName(photo.name, session.spec.name),
        title: '导出裁剪结果',
        dpi: session.dpi,
        metaLabel: session.summaryLabel,
        shareText: '${session.spec.name}证件照已制作完成',
      ),
    );
  }

  /// 压缩大小：不裁剪、不换底，直接进压体积 / 限尺寸。
  Future<void> _openCompress() async {
    final LoadedPhoto? photo = await _pickSingle(title: '选择要压缩的照片');
    if (photo == null || !mounted) return;

    final int w = photo.buffer.width;
    final int h = photo.buffer.height;
    await _push(
      OutputPage(
        image: photo.buffer,
        baseName: outputBaseName(photo.name, '压缩'),
        title: '压缩大小',
        dpi: 300,
        allowResize: true,
        preferTargetSize: true,
        metaLabel: '原图 $w×$h px',
        shareText: '已压缩的照片',
      ),
    );
  }

  /// 换底色：默认直接用原图换底，需要时再进裁剪。
  Future<void> _openRecolor() async {
    final LoadedPhoto? photo = await _pickSingle(title: '选择要换底色的照片');
    if (photo == null || !mounted) return;

    await _push(
      RecolorEditorPage(
        session: CropSession(
          source: photo.buffer,
          sourceName: photo.name,
          spec: PhotoSpecs.byId(_defaultSpecId),
          cropEnabled: false,
        ),
      ),
    );
  }

  /// 加水印：自定义文字 / 字号 / 排版。
  Future<void> _openWatermark() async {
    final LoadedPhoto? photo = await _pickSingle(title: '选择要加水印的照片');
    if (photo == null || !mounted) return;

    await _push(
      WatermarkToolPage(
        session: CropSession(
          source: photo.buffer,
          sourceName: photo.name,
          spec: PhotoSpecs.byId(_defaultSpecId),
          cropEnabled: false,
        ),
      ),
    );
  }

  /// 拼图：先选玩法，再按玩法收照片。
  Future<void> _openSheet() async {
    final SheetMode? mode = await showModalBottomSheet<SheetMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SheetModeSheet(),
    );
    if (mode == null || !mounted) return;

    if (mode == SheetMode.repeatSingle) {
      final LoadedPhoto? photo =
          await _pickSingle(title: '选择要重复排版的照片');
      if (photo == null || !mounted) return;
      await _push(
        SheetToolPage(photos: <LoadedPhoto>[photo], mode: mode),
      );
      return;
    }

    final PhotoBatch? batch =
        await _pickMany(busyLabel: '正在读取照片（可一次多选）');
    if (batch == null || !mounted) return;
    if (batch.length < 2) {
      _toast('多张拼版至少要选 2 张照片，也可以改用「一张照片印多份」');
      return;
    }
    await _push(SheetToolPage(photos: batch.photos, mode: mode));
  }

  // ------------------------------------------------ 视图

  @override
  Widget build(BuildContext context) {
    final List<_Tool> tools = <_Tool>[
      _Tool(
        icon: Icons.crop_rounded,
        title: '裁剪大小',
        desc: '按一寸 / 二寸 / 护照等标准规格裁到精确像素，也能直接输 px 自定义',
        color: AppColors.brand,
        onTap: _openCrop,
      ),
      _Tool(
        icon: Icons.compress_rounded,
        title: '压缩大小',
        desc: '指定「不超过 50KB」自动二分压到体积以内，也可先限制最长边',
        color: const Color(0xFF0EA5A5),
        onTap: _openCompress,
      ),
      _Tool(
        icon: Icons.auto_fix_high_rounded,
        title: '换底色',
        desc: '自动抠出人像换白底 / 蓝底 / 红底，边缘自动去色溢，裁剪可选',
        color: const Color(0xFFF59E0B),
        onTap: _openRecolor,
      ),
      _Tool(
        icon: Icons.water_drop_rounded,
        title: '加水印',
        desc: '自定义水印文字、字号与排版：平铺斜排 / 居中 / 底部横条 / 右下角',
        color: const Color(0xFF7C3AED),
        onTap: _openWatermark,
      ),
      _Tool(
        icon: Icons.grid_view_rounded,
        title: '拼图排版',
        desc: '一张照片印多份，或多张不同照片拼一张，带裁切线直接拿去冲印',
        color: const Color(0xFFE11D63),
        onTap: _openSheet,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              children: <Widget>[
                const _Header(),
                LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints c) {
                    final double cardWidth = (c.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: tools
                          .map(
                            (_Tool t) => SizedBox(
                              width: cardWidth,
                              child: _ToolCard(tool: t),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 18),
                const _FooterNote(),
              ],
            ),
          ),
          if (_busy) Positioned.fill(child: BusyOverlay(label: _busyLabel)),
        ],
      ),
    );
  }
}

// ------------------------------------------------ 子组件

class _Tool {
  const _Tool({
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final Color color;
  final Future<void> Function() onTap;
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(4, 22, 4, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '证件照工具箱',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '五个独立功能，想用哪个点哪个，不必从头走一遍流程',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool});

  final _Tool tool;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => tool.onTap(),
      child: Container(
        height: 142,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x0A111827),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tool.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(tool.icon, size: 21, color: tool.color),
            ),
            const SizedBox(height: 11),
            Text(
              tool.title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Expanded(
              child: Text(
                tool.desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.tips_and_updates_rounded, size: 16, color: AppColors.brand),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '所有处理都在本机完成，照片不会上传到任何服务器。'
              '正面免冠、光线均匀、背景干净的照片，抠图换底效果最好。',
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.brandDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 拼图玩法选择。
class _SheetModeSheet extends StatelessWidget {
  const _SheetModeSheet();

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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
                '拼图排版',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '选一种玩法',
                style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 16),
              _ModeTile(
                icon: Icons.filter_none_rounded,
                title: '一张照片印多份',
                desc: '同一张证件照在一张相纸上重复排开，比如 6 寸排 8 张一寸照',
                onTap: () =>
                    Navigator.of(context).pop(SheetMode.repeatSingle),
              ),
              const SizedBox(height: 10),
              _ModeTile(
                icon: Icons.grid_view_rounded,
                title: '多张照片拼一张',
                desc: '一次选多张不同照片，每张各自裁剪，混排到同一张相纸上',
                onTap: () => Navigator.of(context).pop(SheetMode.mixed),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: AppColors.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
