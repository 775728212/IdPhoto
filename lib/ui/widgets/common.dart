import 'package:flutter/material.dart';

import '../../core/constants/bg_swatches.dart';
import '../../core/theme/app_theme.dart';
import 'pixel_buffer_view.dart';

/// 带标题的白色圆角卡片。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
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
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
                if (title != null) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          title!,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
          child,
        ],
      ),
    );
  }
}

/// 带标签与当前值的滑块。
class LabelSlider extends StatelessWidget {
  const LabelSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.valueLabel,
    this.hint,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final String? valueLabel;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Text(
              valueLabel ?? value.toStringAsFixed(0),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.brand,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions ?? (max - min).round(),
          onChanged: onChanged,
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              hint!,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }
}

/// 横向排列的胶囊选项卡。
class PillSelector<T> extends StatelessWidget {
  const PillSelector({
    super.key,
    required this.items,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final List<T> items;
  final String Function(T item) labelOf;
  final T selected;
  final ValueChanged<T> onSelected;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: items.map((T item) {
          final bool active = item == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(item),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: active ? AppColors.brand : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active ? AppColors.brand : AppColors.divider,
                  ),
                ),
                child: Text(
                  labelOf(item),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 底色选择器。
class SwatchPicker extends StatelessWidget {
  const SwatchPicker({
    super.key,
    required this.selected,
    required this.onSelected,
    this.swatches = BgSwatches.all,
  });

  final BgSwatch selected;
  final ValueChanged<BgSwatch> onSelected;
  final List<BgSwatch> swatches;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: swatches.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (BuildContext context, int index) {
          final BgSwatch swatch = swatches[index];
          final bool active = swatch.id == selected.id;
          return GestureDetector(
            onTap: () => onSelected(swatch),
            child: SizedBox(
              width: 56,
              child: Column(
                children: <Widget>[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: active ? AppColors.brand : AppColors.divider,
                        width: active ? 2.5 : 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _SwatchSwatchTile(swatch: swatch),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    swatch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      color: active ? AppColors.brand : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SwatchSwatchTile extends StatelessWidget {
  const _SwatchSwatchTile({required this.swatch});

  final BgSwatch swatch;

  @override
  Widget build(BuildContext context) {
    if (swatch.transparent) {
      return const Checkerboard(
        cell: 6,
        child: SizedBox.expand(),
      );
    }
    if (swatch.isGradient) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              toFlutterColor(swatch.color),
              toFlutterColor(swatch.color2!),
            ],
          ),
        ),
      );
    }
    return ColoredBox(color: toFlutterColor(swatch.color));
  }
}

/// 把 `0xRRGGBB` 转成 Flutter 的 [Color]。
Color toFlutterColor(int rgb, [double opacity = 1]) => Color.fromARGB(
      (opacity * 255).round().clamp(0, 255),
      (rgb >> 16) & 0xFF,
      (rgb >> 8) & 0xFF,
      rgb & 0xFF,
    );

/// 全屏遮罩加载中。
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x66101828),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              if (label != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  label!,
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行小徽标。
class InfoChip extends StatelessWidget {
  const InfoChip({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final Color c = color ?? AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// 面板底部那一排「图标 + 文字」的方形工具按钮。
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.size = 46,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final double size;

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
              width: size,
              height: size,
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

/// 带加减按钮的整数步进器。
class StepperBox extends StatelessWidget {
  const StepperBox({
    super.key,
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
            onTap: () => onChanged(value > min ? value - 1 : min),
          ),
          _MiniButton(
            icon: Icons.add_rounded,
            enabled: value < max,
            onTap: () => onChanged(value < max ? value + 1 : max),
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
