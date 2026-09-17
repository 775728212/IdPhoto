import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 「保存到相册 / 分享给他人」这一组动作条。
///
/// 四个工具的收尾动作完全一样，收成一个组件，免得每页再抄一遍
/// 按钮样式与禁用逻辑（编码还没算完时必须禁掉）。
class SaveBar extends StatelessWidget {
  const SaveBar({
    super.key,
    required this.enabled,
    required this.onSave,
    required this.onShare,
    this.saveLabel = '保存到相册',
    this.shareLabel = '分享给他人',
    this.footer,
  });

  final bool enabled;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final String saveLabel;
  final String shareLabel;

  /// 追加在按钮下面的内容（例如「再做一个」）。
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? save = enabled ? onSave : null;
    final VoidCallback? share = enabled ? onShare : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: save,
          icon: const Icon(Icons.download_rounded, size: 20),
          label: Text(saveLabel),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: share,
          icon: const Icon(Icons.ios_share_rounded, size: 19),
          label: Text(shareLabel),
        ),
        if (footer != null) ...<Widget>[
          const SizedBox(height: 10),
          footer!,
        ],
      ],
    );
  }
}

/// 一行「标签 + 数值」的小格子，用于成片信息卡片。
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
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
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textTertiary,
            ),
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

/// 方形选项卡（格式 / 压缩方式 / 相纸 等二选一场景）。
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
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
                        color: selected
                            ? AppColors.brandDark
                            : AppColors.textPrimary,
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
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一排可以单选的胶囊选项。
class ChipRow<T> extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.items,
    required this.labelOf,
    required this.selected,
    required this.onSelected,
    this.equals,
  });

  final List<T> items;
  final String Function(T item) labelOf;
  final T selected;
  final ValueChanged<T> onSelected;
  final bool Function(T a, T b)? equals;

  @override
  Widget build(BuildContext context) {
    final bool Function(T, T) same = equals ?? (T a, T b) => a == b;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((T item) {
        final bool active = same(item, selected);
        return GestureDetector(
          onTap: () => onSelected(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: active ? AppColors.brand : AppColors.pageBg,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: active ? AppColors.brand : Colors.transparent,
              ),
            ),
            child: Text(
              labelOf(item),
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
