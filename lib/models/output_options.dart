import '../core/utils/pixel_buffer.dart';
import '../services/encode_service.dart';

/// 输出格式与压缩策略。
///
/// 抽成独立状态的理由：裁剪 / 压缩 / 换底 / 拼图四条链路最后都要过同一道
/// 「编码 + 压体积」工序，逻辑只该有一份。
class OutputOptions {
  OutputOptions({
    this.forcePng = false,
    this.quality = 92,
    this.targetKb,
    this.maxSide,
  });

  /// 用户显式选了 PNG。
  bool forcePng = false;

  /// JPEG 质量 1..100。
  int quality = 92;

  /// 目标体积上限（KB）。非空时优先按体积压缩。
  int? targetKb;

  /// 非空时先把最长边限制到该值再编码（「压缩大小」工具用）。
  int? maxSide;

  bool get sizeLocked => targetKb != null && targetKb! > 0;

  bool get resizeLocked => maxSide != null && maxSide! > 0;

  /// 实际是否输出 PNG。透明底只能 PNG，这是格式上的硬约束。
  bool resolvePng({required bool transparent}) => forcePng || transparent;

  /// 编码前的预处理：按需限制最长边。
  PixelBuffer prepare(PixelBuffer image) {
    final int? side = maxSide;
    if (side == null || side <= 0) return image;
    return EncodeService.limitMaxSide(image, side);
  }

  /// 一次编码。透明底走 PNG；锁定体积走二分搜索；否则按画质。
  Future<EncodedImage> encode(
    PixelBuffer image, {
    required bool transparent,
  }) =>
      encodePrepared(prepare(image), transparent: transparent);

  /// 对**已经预处理过**的图编码。
  ///
  /// 单独留一个入口是为了让页面只算一次缩放：预览要显示缩放后的图，
  /// 编码也要用同一张，走 [encode] 会把 `limitMaxSide` 重采样算两遍。
  Future<EncodedImage> encodePrepared(
    PixelBuffer prepared, {
    required bool transparent,
  }) async {
    if (resolvePng(transparent: transparent)) {
      return EncodeService.encodePng(prepared);
    }
    if (sizeLocked) {
      return EncodeService.compressToTargetSize(prepared, targetKb! * 1024);
    }
    return EncodeService.encodeJpegAsync(prepared, quality);
  }
}

/// 由原文件名派生输出文件名前缀。
///
/// `IMG_1234.jpg` + `白底` → `IMG_1234_白底`。没有扩展名时原样返回。
String outputBaseName(String sourceName, [String suffix = '']) {
  final int dot = sourceName.lastIndexOf('.');
  final String stem = dot > 0 ? sourceName.substring(0, dot) : sourceName;
  return suffix.isEmpty ? stem : '${stem}_$suffix';
}
