import 'dart:ui' show Rect;

import 'encode_service.dart';
import 'export/export_stub.dart'
    if (dart.library.io) 'export/export_io.dart'
    if (dart.library.js_interop) 'export/export_web.dart' as backend;

export 'export/export_exception.dart' show ExportException;

/// 导出（保存到相册 / 分享）的门面。
///
/// 之所以要做这层拆分：`dart:io` 在 web 上**不可用**，
/// 旧版本这个文件里直接 `import 'dart:io'` 并用了 `File` / `Platform`，
/// 会让整个项目无法通过 web 编译（不是运行时报错，是编译期直接失败）。
///
/// 现在按平台分流：
///  - 原生 → `export/export_io.dart`（gal 存相册 + share_plus 分享）
///  - Web  → `export/export_web.dart`（Blob 下载 + Web Share API）
///
/// 两个实现暴露完全相同的顶层函数签名，所以调用方（export_page.dart）
/// 一行都不用改。
class ExportService {
  ExportService._();

  /// 保存。原生平台写系统相册；Web 平台触发浏览器下载。
  ///
  /// [baseName] 用于生成文件名（Web 下载时有意义，原生平台忽略）。
  static Future<void> saveToGallery(
    EncodedImage encoded, {
    String album = '证件照',
    String? baseName,
  }) =>
      backend.saveToGallery(encoded, album: album, baseName: baseName);

  /// 分享。原生平台调起系统分享面板；Web 平台优先用 Web Share API。
  static Future<void> share(
    EncodedImage encoded, {
    required String baseName,
    String text = '证件照已制作完成',
    Rect? sharePositionOrigin,
  }) =>
      backend.share(
        encoded,
        baseName: baseName,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      );
}
