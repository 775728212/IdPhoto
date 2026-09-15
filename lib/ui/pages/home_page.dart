import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/photo_specs.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/pixel_buffer.dart';
import '../../models/edit_session.dart';
import '../../services/image_loader.dart';
import '../widgets/common.dart';
import '../widgets/spec_picker_sheet.dart';
import 'crop_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  PhotoSpec _spec = PhotoSpecs.byId('one_inch');
  bool _busy = false;
  String _busyLabel = '正在读取照片';

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        // 相机直出一般 4000px+，这里先让系统侧做一次粗缩，减轻解码压力
        maxWidth: 4000,
        maxHeight: 4000,
        imageQuality: 95,
        requestFullMetadata: false,
      );
      if (file == null) return;

      setState(() {
        _busy = true;
        _busyLabel = '正在读取照片';
      });

      final Uint8List bytes = await file.readAsBytes();
      setState(() => _busyLabel = '正在解析图像');
      final PixelBuffer? buffer = await ImageLoader.decodeBytes(bytes);
      if (!mounted) return;

      if (buffer == null) {
        setState(() => _busy = false);
        _toast('无法解析这张图片，请换一张试试');
        return;
      }

      final EditSession session = EditSession(
        source: buffer,
        sourceName: file.name,
        spec: _spec,
      );
      setState(() => _busy = false);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => CropPage(session: session)),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('读取照片失败：$error');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSpecSheet() async {
    final PhotoSpec? picked = await showSpecPicker(context, _spec);
    if (picked != null) setState(() => _spec = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: CustomScrollView(
              slivers: <Widget>[
                const SliverToBoxAdapter(child: _Header()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildStartCard()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(child: _buildSpecCard()),
                ),
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  sliver: SliverToBoxAdapter(child: _FeatureList()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 28)),
              ],
            ),
          ),
          if (_busy) Positioned.fill(child: BusyOverlay(label: _busyLabel)),
        ],
      ),
    );
  }

  Widget _buildStartCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _BigAction(
                  icon: Icons.photo_library_rounded,
                  title: '从相册选择',
                  subtitle: '已有的正面照',
                  onTap: () => _pick(ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigAction(
                  icon: Icons.photo_camera_rounded,
                  title: '立即拍照',
                  subtitle: '找面白墙更好',
                  onTap: () => _pick(ImageSource.camera),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.tips_and_updates_rounded,
                    size: 16, color: AppColors.brand),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正面免冠、光线均匀、背景干净的照片，换底色效果最好。',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: AppColors.brandDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecCard() {
    final List<PhotoSpec> quick = PhotoSpecs.common;
    return SectionCard(
      title: '选择规格',
      trailing: TextButton(
        onPressed: _openSpecSheet,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text('全部规格  >', style: TextStyle(fontSize: 12.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quick.map((PhotoSpec s) {
              final bool active = s.id == _spec.id;
              return GestureDetector(
                onTap: () => setState(() => _spec = s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.brand : AppColors.pageBg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: active ? AppColors.brand : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    s.name,
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
          const SizedBox(height: 14),
          Container(
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
                        '${_spec.name} · ${_spec.mmLabel}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _spec.note.isEmpty
                            ? '输出 ${_spec.pxLabel(300)} @300DPI'
                            : '${_spec.note} · 输出 ${_spec.pxLabel(_spec.dpi)}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                InfoChip(
                  icon: Icons.straighten_rounded,
                  text: '${_spec.pixelWidth(_spec.dpi)}×${_spec.pixelHeight(_spec.dpi)}',
                  color: AppColors.brand,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 22, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '证件照制作',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '标准规格裁剪 · 智能换底色 · 按体积压缩',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _BigAction extends StatelessWidget {
  const _BigAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[AppColors.brand, AppColors.brandDark],
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, size: 30, color: Colors.white),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.82),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      title: '能做什么',
      child: Column(
        children: <Widget>[
          _FeatureRow(
            icon: Icons.crop_rounded,
            title: '标准尺寸裁剪',
            desc: '一寸 / 二寸 / 护照 / 签证 / 各类考试报名，共 30+ 规格，按毫米换算精确像素',
          ),
          _FeatureRow(
            icon: Icons.auto_fix_high_rounded,
            title: '一键换底色',
            desc: '自动识别背景并替换成白底、蓝底、红底或渐变色，边缘自动去色溢',
          ),
          _FeatureRow(
            icon: Icons.compress_rounded,
            title: '按体积压缩',
            desc: '指定"不超过 50KB"，自动二分搜索出画质最好的压缩参数',
          ),
          _FeatureRow(
            icon: Icons.grid_view_rounded,
            title: '排版打印',
            desc: '一张 6 寸相纸自动排下 8 张一寸照，带裁切线，拿去冲印即可',
            last: true,
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.desc,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String desc;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: AppColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  desc,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
