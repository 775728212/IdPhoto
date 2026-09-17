import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/output_options.dart';
import '../../services/encode_service.dart';
import 'common.dart';
import 'save_bar.dart';

/// 输出格式 + 压缩方式 + （可选）尺寸上限。
///
/// 四个工具的最后一步都长这样，抽成一张卡片组；调用方只需要把
/// [OutputOptions] 递进来，改动后回调 [onChanged] 触发重新编码。
class OutputSettingsCard extends StatelessWidget {
  const OutputSettingsCard({
    super.key,
    required this.options,
    required this.transparent,
    required this.encoded,
    required this.onChanged,
    this.allowResize = false,
  });

  final OutputOptions options;

  /// 待输出图是否含透明像素（透明底只能出 PNG）。
  final bool transparent;

  /// 最近一次编码结果，用于展示实际体积。
  final EncodedImage? encoded;

  /// 参数被改动，调用方需要重新编码。
  final VoidCallback onChanged;

  /// 「压缩大小」工具会额外显示最长边限制。
  final bool allowResize;

  /// 最长边可选项；`null` 表示保持原始尺寸。
  static const List<int?> maxSidePresets = <int?>[
    null,
    1600,
    1200,
    800,
    600,
    400,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildFormatCard(),
        if (allowResize) ...<Widget>[
          const SizedBox(height: 14),
          _buildResizeCard(),
        ],
        const SizedBox(height: 14),
        _buildCompressCard(),
      ],
    );
  }

  Widget _buildFormatCard() {
    return SectionCard(
      title: '输出格式',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ChoiceTile(
                  title: 'JPG',
                  desc: '体积小，通用',
                  selected: !options.resolvePng(transparent: transparent),
                  onTap: transparent
                      ? null
                      : () {
                          options.forcePng = false;
                          onChanged();
                        },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceTile(
                  title: 'PNG',
                  desc: '无损，可透明',
                  selected: options.resolvePng(transparent: transparent),
                  onTap: () {
                    options.forcePng = true;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          if (transparent) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              '当前成片含透明区域，只能导出 PNG。',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResizeCard() {
    return SectionCard(
      title: '限制尺寸',
      trailing: Text(
        options.resizeLocked ? '已开启' : '保持原尺寸',
        style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text(
            '按最长边等比缩小。很多报名系统只收几百 KB 的小图，'
            '先降尺寸再压体积，画质比死压 JPEG 画质好得多。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ChipRow<int?>(
            items: maxSidePresets,
            labelOf: (int? v) => v == null ? '原尺寸' : '$v px',
            selected: options.maxSide,
            onSelected: (int? v) {
              options.maxSide = v;
              onChanged();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompressCard() {
    if (options.resolvePng(transparent: transparent)) {
      return const SectionCard(
        title: '压缩',
        child: Text(
          'PNG 为无损格式，体积由像素尺寸决定。若要压缩体积，请切换到 JPG。',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    final bool locked = options.sizeLocked;
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
                child: ChoiceTile(
                  title: '按画质',
                  desc: '手动调质量',
                  selected: !locked,
                  onTap: () {
                    options.targetKb = null;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ChoiceTile(
                  title: '按体积',
                  desc: '自动卡上限',
                  selected: locked,
                  onTap: () {
                    options.targetKb = options.targetKb ?? 50;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!locked)
            LabelSlider(
              label: 'JPEG 画质',
              value: options.quality.toDouble(),
              min: 30,
              max: 98,
              onChanged: (double v) {
                options.quality = v.round();
                onChanged();
              },
              valueLabel: '${options.quality}',
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
            ChipRow<int>(
              items: const <int>[20, 30, 50, 100, 200, 500],
              labelOf: (int kb) => '≤ $kb KB',
              selected: options.targetKb ?? 50,
              onSelected: (int kb) {
                options.targetKb = kb;
                onChanged();
              },
            ),
            const SizedBox(height: 12),
            _TargetResult(targetKb: options.targetKb ?? 50, encoded: encoded),
          ],
        ],
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
                  : '当前尺寸下最低画质仍有 ${encoded!.sizeLabel}，压不到 $targetKb KB 以内，试试「限制尺寸」',
              style: TextStyle(fontSize: 12.5, color: color, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
