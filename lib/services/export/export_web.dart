import 'dart:js_interop';
import 'dart:ui' show Rect;

import '../encode_service.dart';
import 'export_exception.dart';

/// Web（H5）平台的导出实现。
///
/// 浏览器里没有「系统相册」这个概念，所以：
///  - 保存 → 触发浏览器下载（`<a download>` + Blob URL）
///  - 分享 → 优先用 Web Share API（移动端浏览器支持），不支持时回退到下载
///
/// 两个 JS 辅助函数定义在 `web/index.html` 里，页面加载时就注册成全局函数，
/// 因此这里不需要额外依赖 `package:web` 或 `dart:html`。

@JS('idPhotoDownload')
external JSAny? _idPhotoDownload(
  JSUint8Array bytes,
  JSString fileName,
  JSString mimeType,
);

@JS('idPhotoShare')
external JSAny? _idPhotoShare(
  JSUint8Array bytes,
  JSString fileName,
  JSString mimeType,
  JSString text,
);

String _safeName(String baseName) =>
    baseName.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');

String _stampedName(String baseName, String extension) =>
    '${_safeName(baseName)}_${DateTime.now().millisecondsSinceEpoch}.$extension';

/// 浏览器里「保存」= 下载文件。
Future<void> saveToGallery(
  EncodedImage encoded, {
  String album = '证件照',
  String? baseName,
}) async {
  final String name = _stampedName(baseName ?? album, encoded.extension);
  try {
    _idPhotoDownload(encoded.bytes.toJS, name.toJS, encoded.mimeType.toJS);
  } catch (error) {
    throw ExportException('浏览器下载失败：$error');
  }
}

/// 优先调用 Web Share API 分享文件；浏览器不支持时由 JS 侧回退为下载。
Future<void> share(
  EncodedImage encoded, {
  required String baseName,
  String text = '证件照已制作完成',
  Rect? sharePositionOrigin,
}) async {
  final String name = _stampedName(baseName, encoded.extension);
  try {
    _idPhotoShare(
      encoded.bytes.toJS,
      name.toJS,
      encoded.mimeType.toJS,
      text.toJS,
    );
  } catch (error) {
    throw ExportException('分享失败：$error');
  }
}
