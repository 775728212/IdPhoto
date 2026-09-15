import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/utils/pixel_buffer.dart';
import 'recolor_service.dart';

/// 一次编码的结果。
class EncodedImage {
  const EncodedImage({
    required this.bytes,
    required this.extension,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List bytes;

  /// `jpg` 或 `png`。
  final String extension;
  final int width;
  final int height;

  /// JPEG 质量 1..100；PNG 固定为 100（无损）。
  final int quality;

  int get byteSize => bytes.length;

  String get mimeType => extension == 'png' ? 'image/png' : 'image/jpeg';

  String get sizeLabel => formatBytes(byteSize);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}

/// 图片编码 / 压缩。
///
/// 压缩走的是「JPEG 质量二分查找」：给定目标体积（KB），
/// 在质量 10..96 之间二分，找到体积不超过目标值的最高质量。
class EncodeService {
  EncodeService._();

  static img.Image toImage(PixelBuffer buffer) => img.Image.fromBytes(
        width: buffer.width,
        height: buffer.height,
        bytes: buffer.rgba.buffer,
        bytesOffset: buffer.rgba.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

  static PixelBuffer fromImage(img.Image image) {
    // 非 8bit（如 16bit PNG）先降到 8bit，否则 getBytes 返回的是原始字节视图。
    final img.Image byteImage = image.format == img.Format.uint8
        ? image
        : image.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);

    // getBytes(order: rgba) 在通道数不为 4 时会自动补/转通道，
    // 返回的正好是 width * height * 4 的 RGBA 字节流。
    final Uint8List bytes =
        byteImage.getBytes(order: img.ChannelOrder.rgba, alpha: 255);
    final int expected = byteImage.width * byteImage.height * 4;
    if (bytes.length != expected) {
      throw StateError('无法把图像转换为 RGBA：${bytes.length} != $expected');
    }
    return PixelBuffer(byteImage.width, byteImage.height, bytes);
  }

  /// JPEG 有损编码。`quality` 1..100。
  static EncodedImage encodeJpeg(PixelBuffer buffer, int quality) {
    final int q = quality.clamp(1, 100);
    final Uint8List bytes = img.encodeJpg(toImage(buffer), quality: q);
    return EncodedImage(
      bytes: bytes,
      extension: 'jpg',
      width: buffer.width,
      height: buffer.height,
      quality: q,
    );
  }

  /// PNG 无损编码，保留 alpha 通道。
  static EncodedImage encodePng(PixelBuffer buffer) {
    final Uint8List bytes = img.encodePng(toImage(buffer));
    return EncodedImage(
      bytes: bytes,
      extension: 'png',
      width: buffer.width,
      height: buffer.height,
      quality: 100,
    );
  }

  static EncodedImage encode(
    PixelBuffer buffer, {
    required bool asPng,
    int quality = 92,
  }) {
    if (asPng) return encodePng(buffer);
    // JPEG 不支持透明通道，透明区域先用白色铺底，否则会变成黑块。
    final PixelBuffer flat = buffer.hasTransparency
        ? RecolorService.flattenOn(buffer, 0xFFFFFF)
        : buffer;
    return encodeJpeg(flat, quality);
  }

  /// 异步 JPEG 编码（isolate 内执行）。
  static Future<EncodedImage> encodeJpegAsync(
    PixelBuffer buffer,
    int quality,
  ) =>
      Isolate.run(() => encodeJpeg(buffer, quality));

  /// 按目标体积压缩。返回体积不超过 [targetBytes] 的最高质量结果。
  ///
  /// 若最低质量仍然超出目标，则返回最低质量的结果（由调用方提示用户）。
  static Future<EncodedImage> compressToTargetSize(
    PixelBuffer buffer,
    int targetBytes, {
    int minQuality = 10,
    int maxQuality = 96,
  }) async {
    if (buffer.hasTransparency) {
      // 透明图只能出 PNG，体积不可控，直接返回无损结果。
      return encodePng(buffer);
    }
    try {
      return await Isolate.run(
        () => _searchQuality(buffer, targetBytes, minQuality, maxQuality),
      );
    } catch (_) {
      return _searchQuality(buffer, targetBytes, minQuality, maxQuality);
    }
  }

  static EncodedImage _searchQuality(
    PixelBuffer buffer,
    int targetBytes, [
    int minQuality = 10,
    int maxQuality = 96,
  ]) {
    EncodedImage best = encodeJpeg(buffer, minQuality);
    if (best.byteSize > targetBytes) return best;

    int lo = minQuality;
    int hi = maxQuality;
    while (lo <= hi) {
      final int mid = (lo + hi) ~/ 2;
      final EncodedImage candidate = encodeJpeg(buffer, mid);
      if (candidate.byteSize <= targetBytes) {
        best = candidate;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return best;
  }

  /// 限制最长边（用于预览渲染，避免超大图卡顿）。
  static PixelBuffer limitMaxSide(PixelBuffer source, int maxSide) {
    final int longest =
        source.width > source.height ? source.width : source.height;
    if (longest <= maxSide) return source;

    final double scale = maxSide / longest;
    final int w = (source.width * scale).round().clamp(1, 100000);
    final int h = (source.height * scale).round().clamp(1, 100000);
    return ImageOps.resampleRegion(source, 0, 0, source.width.toDouble(),
        source.height.toDouble(), w, h);
  }
}
