/// 平台文件系统门面的共享类型（io/web 实现与调用方共用）。
library;

/// 文件元信息（避免把 dart:io 的 FileStat 泄漏到共享代码）
class FileStatInfo {
  final int size;
  final DateTime modified;

  const FileStatInfo({required this.size, required this.modified});
}
