import 'dart:io';
import 'dart:ui' show Rect;

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../encode_service.dart';
import 'export_exception.dart';

/// 原生平台（Android / iOS / Windows / macOS / Linux）的导出实现。
///
/// 这个文件是唯一允许 `import 'dart:io'` 的导出实现；web 走 export_web.dart。
/// 两者必须保持完全一致的两个顶层函数签名。

String _safeName(String baseName) =>
    baseName.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');

String _stampedName(String baseName, String extension) =>
    '${_safeName(baseName)}_${DateTime.now().millisecondsSinceEpoch}.$extension';

/// 把编码结果写到临时目录，返回文件。
Future<File> writeToTemp(EncodedImage encoded, String baseName) async {
  final Directory dir = await getTemporaryDirectory();
  final File file = File(
    '${dir.path}${Platform.pathSeparator}'
    '${_stampedName(baseName, encoded.extension)}',
  );
  await file.writeAsBytes(encoded.bytes, flush: true);
  return file;
}

/// 保存到系统相册。
///
/// [baseName] 在原生平台只用于 `share` 的临时文件名，相册归类由 [album] 决定；
/// 参数保留是为了和 web 实现保持同一套签名。
Future<void> saveToGallery(
  EncodedImage encoded, {
  String album = '证件照',
  String? baseName,
}) async {
  try {
    if (!await Gal.hasAccess()) {
      final bool granted = await Gal.requestAccess();
      if (!granted) {
        throw ExportException('相册权限被拒绝，请在系统设置中开启后重试');
      }
    }
    await Gal.putImageBytes(encoded.bytes, album: album);
  } on GalException catch (e) {
    throw ExportException(e.type.message);
  }
}

/// 调起系统分享面板。
Future<void> share(
  EncodedImage encoded, {
  required String baseName,
  String text = '证件照已制作完成',
  Rect? sharePositionOrigin,
}) async {
  final File file = await writeToTemp(encoded, baseName);
  await SharePlus.instance.share(
    ShareParams(
      text: text,
      files: <XFile>[XFile(file.path, mimeType: encoded.mimeType)],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}
