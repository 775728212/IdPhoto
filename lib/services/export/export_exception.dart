/// 导出失败时抛出的异常。
///
/// 单独放在这个文件里，是为了让「平台无关的门面」和「各平台实现」
/// 都能引用同一个类型，而不产生循环 import。
class ExportException implements Exception {
  ExportException(this.message);

  final String message;

  @override
  String toString() => message;
}
