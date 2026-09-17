import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/photo_specs.dart';
import '../../core/theme/app_theme.dart';

/// 弹出「全部规格」选择面板。
///
/// 面板里有一项「自定义」：点进去不是立刻返回，而是就地展开像素输入区，
/// 让用户直接填宽高（px）。很多报名系统给的就是像素要求，换算成毫米反而绕。
Future<PhotoSpec?> showSpecPicker(BuildContext context, PhotoSpec current) {
  return showModalBottomSheet<PhotoSpec>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _SpecPickerSheet(current: current),
  );
}

/// 自定义尺寸的快捷预设，省得用户每次手算像素。
class _PxPreset {
  const _PxPreset(this.label, this.width, this.height);

  final String label;
  final int width;
  final int height;
}

const List<_PxPreset> _presets = <_PxPreset>[
  _PxPreset('一寸', 295, 413),
  _PxPreset('小一寸', 260, 378),
  _PxPreset('二寸', 413, 579),
  _PxPreset('大一寸', 390, 567),
  _PxPreset('身份证', 358, 441),
  _PxPreset('方形', 600, 600),
];

class _SpecPickerSheet extends StatefulWidget {
  const _SpecPickerSheet({required this.current});

  final PhotoSpec current;

  @override
  State<_SpecPickerSheet> createState() => _SpecPickerSheetState();
}

class _SpecPickerSheetState extends State<_SpecPickerSheet> {
  late String _category = widget.current.category;

  /// 是否处于自定义像素输入视图。
  late bool _customMode = widget.current.isCustom;

  late final TextEditingController _widthPx = TextEditingController(
    text: '${widget.current.pixelWidth(widget.current.dpi)}',
  );
  late final TextEditingController _heightPx = TextEditingController(
    text: '${widget.current.pixelHeight(widget.current.dpi)}',
  );

  late int _dpi = widget.current.dpi;

  @override
  void dispose() {
    _widthPx.dispose();
    _heightPx.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double maxHeight = MediaQuery.of(context).size.height * 0.78;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: AppColors.pageBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _buildHeader(),
            if (_customMode)
              Flexible(child: _buildCustomPanel())
            else ...<Widget>[
              _buildCategoryRow(),
              const SizedBox(height: 12),
              Flexible(child: _buildSpecList()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        children: <Widget>[
          Text(
            _customMode ? '自定义尺寸' : '选择规格',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (_customMode)
            TextButton(
              onPressed: () => setState(() => _customMode = false),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('返回规格列表', style: TextStyle(fontSize: 12.5)),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                '共 30+ 种标准规格',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryRow() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: PhotoSpecs.categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final String c = PhotoSpecs.categories[index];
          final bool active = c == _category;
          return GestureDetector(
            onTap: () => setState(() => _category = c),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? AppColors.brand : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                c,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpecList() {
    final List<PhotoSpec> items = PhotoSpecs.byCategory(_category);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final PhotoSpec s = items[index];
        final bool active = s.id == widget.current.id;
        final bool customRow = s.isCustom;

        return GestureDetector(
          onTap: () {
            if (customRow) {
              setState(() => _customMode = true);
            } else {
              Navigator.of(context).pop(s);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AppColors.brand : Colors.transparent,
                width: 1.6,
              ),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        s.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        customRow
                            ? '手动输入像素尺寸'
                            : '${s.mmLabel} · '
                                '${s.note.isEmpty ? s.pxLabel(s.dpi) : s.note}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (customRow)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.brand,
                  )
                else ...<Widget>[
                  Text(
                    s.pxLabel(s.dpi),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (active)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: AppColors.brand,
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------------------------------ 自定义像素输入

  Widget _buildCustomPanel() {
    final int w = int.tryParse(_widthPx.text.trim()) ?? 0;
    final int h = int.tryParse(_heightPx.text.trim()) ?? 0;
    final bool valid = w >= 16 && h >= 16 && w <= 20000 && h <= 20000;

    final double mmW = w <= 0 ? 0 : w / _dpi * 25.4;
    final double mmH = h <= 0 ? 0 : h / _dpi * 25.4;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '快捷预设',
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
            children: _presets.map((_PxPreset p) {
              final bool active = w == p.width && h == p.height;
              return GestureDetector(
                onTap: () => setState(() {
                  _widthPx.text = '${p.width}';
                  _heightPx.text = '${p.height}';
                }),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppColors.brand : AppColors.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: active ? AppColors.brand : AppColors.divider,
                    ),
                  ),
                  child: Text(
                    '${p.label} ${p.width}×${p.height}',
                    style: TextStyle(
                      fontSize: 12.5,
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
            '像素尺寸',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _PxField(
                  label: '宽度',
                  controller: _widthPx,
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PxField(
                  label: '高度',
                  controller: _heightPx,
                  onChanged: () => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '冲印分辨率',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '只影响打印出来的物理大小，不影响像素值',
            style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 10),
          Row(
            children: PhotoSpecs.supportedDpi.map((int d) {
              final bool active = d == _dpi;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: d == PhotoSpecs.supportedDpi.last ? 0 : 8,
                  ),
                  child: GestureDetector(
                    onTap: () => setState(() => _dpi = d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? AppColors.brand : AppColors.surface,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: active ? AppColors.brand : AppColors.divider,
                        ),
                      ),
                      child: Text(
                        '$d DPI',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w500,
                          color:
                              active ? Colors.white : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: valid
                  ? AppColors.brandSoft
                  : AppColors.warning.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  valid
                      ? Icons.straighten_rounded
                      : Icons.error_outline_rounded,
                  size: 15,
                  color: valid ? AppColors.brand : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    valid
                        ? '输出 $w×$h px · 约 ${_mm(mmW)}×${_mm(mmH)}mm'
                        : '宽高需在 16 ~ 20000 px 之间',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: valid ? AppColors.brandDark : AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: valid
                ? () => Navigator.of(context).pop(
                      PhotoSpec.custom(
                        widthPx: w,
                        heightPx: h,
                        dpi: _dpi,
                      ),
                    )
                : null,
            child: const Text('使用这个尺寸'),
          ),
        ],
      ),
    );
  }

  static String _mm(double v) {
    final double r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);
  }
}

/// 只接受数字的像素输入框。
class _PxField extends StatelessWidget {
  const _PxField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$label (px)',
          style: const TextStyle(
            fontSize: 11.5,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          onChanged: (_) => onChanged(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.brand, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}
