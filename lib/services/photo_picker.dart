import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../core/utils/pixel_buffer.dart';
import 'image_loader.dart';

/// 选图过程中的失败。带上中文提示，界面直接丢进 SnackBar 即可。
class PhotoPickException implements Exception {
  const PhotoPickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 一次多选的结果。
///
/// 刻意不用「抛异常」表达「有 1 张解析失败」——那样会把已经成功的照片一起丢掉。
/// 解析失败的张数单独记在 [skipped] 里，由界面决定是否提示。
class PhotoBatch {
  const PhotoBatch({required this.photos, this.skipped = 0});

  final List<LoadedPhoto> photos;

  /// 选中但解析失败的张数。
  final int skipped;

  bool get isEmpty => photos.isEmpty;

  int get length => photos.length;
}

/// 选图（相册 / 拍照）+ 解码的统一入口。
///
/// 原本这段逻辑散在首页里，四个独立工具都要用同一套，于是收拢到这里。
/// 刻意不碰任何 UI —— 忙碌遮罩与提示由调用页面自己控制，方便各工具
/// 按自己的节奏显示「正在读取照片」「正在解析图像」。
class PhotoPicker {
  PhotoPicker._();

  static final ImagePicker _picker = ImagePicker();

  /// 先让系统侧做一次粗缩，4MP 左右足够撑住 600px 级成片，还能省下解码内存。
  static const double _preMaxSide = 4000;

  /// 读取单张。用户取消返回 `null`。
  static Future<LoadedPhoto?> pickOne({required ImageSource source}) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      maxWidth: _preMaxSide,
      maxHeight: _preMaxSide,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    if (file == null) return null;
    final LoadedPhoto? photo = await _decode(file);
    if (photo == null) {
      throw const PhotoPickException('无法解析这张图片，请换一张试试');
    }
    return photo;
  }

  /// 相册多选。用户取消返回空批次。
  ///
  /// 拼图工具会一次要好几张不同照片，[limit] 用来挡住「一口气选 200 张」
  /// 把内存打爆的情况。
  static Future<PhotoBatch> pickMany({int limit = 12}) async {
    final List<XFile> files = await _picker.pickMultiImage(
      maxWidth: _preMaxSide,
      maxHeight: _preMaxSide,
      imageQuality: 95,
      requestFullMetadata: false,
      limit: limit,
    );
    if (files.isEmpty) return const PhotoBatch(photos: <LoadedPhoto>[]);

    final List<LoadedPhoto> photos = <LoadedPhoto>[];
    var skipped = 0;
    for (final XFile file in files) {
      final LoadedPhoto? photo = await _decode(file);
      if (photo == null) {
        skipped++;
      } else {
        photos.add(photo);
      }
    }
    if (photos.isEmpty) {
      throw const PhotoPickException('选中的图片都无法解析，请换几张试试');
    }
    return PhotoBatch(photos: photos, skipped: skipped);
  }

  static Future<LoadedPhoto?> _decode(XFile file) async {
    final Uint8List bytes = await file.readAsBytes();
    final PixelBuffer? buffer = await ImageLoader.decodeBytes(bytes);
    if (buffer == null) return null;
    return LoadedPhoto(buffer: buffer, name: file.name);
  }
}
