import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/utils/pixel_buffer.dart';
import 'encode_service.dart';

/// 解码后的照片。
class LoadedPhoto {
  const LoadedPhoto({required this.buffer, required this.name});

  final PixelBuffer buffer;
  final String name;
}

/// 把用户选择的文件解码成统一的 [PixelBuffer]。
class ImageLoader {
  ImageLoader._();

  /// 工作分辨率上限（最长边）。
  ///
  /// 证件照最终输出最大也就 600px 级别，2400px 的原图余量非常充足，
  /// 同时把内存占用从 12MP 的 ~48MB 压到 ~10MB，保证编辑流畅。
  static const int maxWorkingSide = 2400;

  static Future<PixelBuffer?> decodeBytes(
    Uint8List bytes, {
    int maxSide = maxWorkingSide,
  }) async {
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // 手机拍摄的照片方向信息写在 EXIF 里，必须烘焙进像素，否则会躺倒。
    final img.Image oriented = img.bakeOrientation(decoded);
    final PixelBuffer buffer = EncodeService.fromImage(oriented);
    return EncodeService.limitMaxSide(buffer, maxSide);
  }
}
