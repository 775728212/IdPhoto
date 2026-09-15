import 'dart:ui' show Rect;

import '../encode_service.dart';
import 'export_exception.dart';

/// 既没有 `dart:io` 也没有 JS 互操作能力的平台（理论上不会走到）。
///
/// 保留这个 stub 是为了让条件导入链有兜底分支：如果两个 `if` 分支都不成立，
/// 编译期仍能通过，只在真正调用时抛出一个可读的错误。
Future<void> saveToGallery(
  EncodedImage encoded, {
  String album = '证件照',
  String? baseName,
}) async {
  throw ExportException('当前平台不支持保存到相册');
}

Future<void> share(
  EncodedImage encoded, {
  required String baseName,
  String text = '证件照已制作完成',
  Rect? sharePositionOrigin,
}) async {
  throw ExportException('当前平台不支持分享');
}
