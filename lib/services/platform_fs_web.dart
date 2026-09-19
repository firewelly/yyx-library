/// Web 端文件系统门面实现：无本地文件系统，全部不支持。
///
/// Web 端的导入/导出走内存字节流（ImportService.importByBytes /
/// WebLauncher.downloadBytes），不会调用这里的方法；
/// 若被误调用，抛出明确的 [UnsupportedError] 而非编译失败或静默崩溃。
library;
import 'dart:typed_data';

import 'platform_fs_types.dart';

export 'platform_fs_types.dart';

UnsupportedError _unsupported(String what) =>
    UnsupportedError('Web 端无本地文件系统，不支持$what。请使用导入（选择文件）或导出（浏览器下载）功能。');

/// 平台文件系统门面（Web 端实现）
class PlatformFs {
  PlatformFs._();

  static Future<bool> fileExists(String path) async => false;

  static Future<bool> dirExists(String path) async => false;

  static Future<void> ensureDir(String path) async {
    throw _unsupported('创建目录');
  }

  static Future<Uint8List?> readBytes(String path) async => null;

  static Future<String> writeTextFile(String dir, String fileName, String content) async {
    throw _unsupported('写文件');
  }

  static Future<String> writeBytesFile(String dir, String fileName, List<int> bytes) async {
    throw _unsupported('写文件');
  }

  static Future<void> copyFile(String from, String to) async {
    throw _unsupported('复制文件');
  }

  static Future<void> moveFile(String from, String to) async {
    throw _unsupported('移动文件');
  }

  static Future<void> deleteFile(String path) async {
    throw _unsupported('删除文件');
  }

  static Future<DateTime?> lastModified(String path) async => null;

  static Future<FileStatInfo?> statFile(String path) async => null;

  static Future<List<String>> listFiles(
    String dir, {
    bool recursive = false,
    Set<String>? extensions,
    bool skipZeroByte = false,
  }) async {
    return const [];
  }

  static Future<Set<String>> findPlaceholderFiles(String dir) async => {};

  static Future<List<String>> cacheDirPaths() async => [];

  static Future<int> dirSizeExcluding(String dirPath, List<String> keepExtensions) async => 0;

  static Future<({int freedBytes, int removedFiles, List<String> errors})>
      clearDirExcluding(String dirPath, List<String> keepExtensions) async {
    return (freedBytes: 0, removedFiles: 0, errors: <String>[]);
  }

  /// Web 端 Hive 走 IndexedDB（initFlutter 默认行为，无需处理）
  static Future<String> hiveInitDir() async => throw UnsupportedError('Web 端请使用 Hive.initFlutter');

  /// Web 端无本地路径概念
  static Future<String?> normalizeLegacyCustomDbPath(String customDbPath, {required String dbName}) async => null;

  /// Web 端数据库走 ffi_web 虚拟文件系统，无需迁移
  static Future<String?> stableDatabaseDir({required String dbName}) async => null;

  /// Web 端显示保持正斜杠
  static String nativeSeparators(String path) => path;

  /// Web 端无程序目录概念
  static String programDir() => '';

  /// Web 端原样返回（扫描/文件功能本就禁用）
  static String resolvePath(String path) => path;

  /// Web 端无程序目录，配置了才生效
  static String effectiveLibraryRoot(String configuredRoot) => configuredRoot;

  static Future<String> defaultBackupDir() async {
    throw _unsupported('默认备份目录');
  }
}
