import 'package:flutter/foundation.dart' show kIsWeb;
import 'platform_fs.dart';

/// 缓存清理结果
class CacheCleanResult {
  final int freedBytes;
  final int removedFiles;
  final List<String> errors;

  const CacheCleanResult({
    this.freedBytes = 0,
    this.removedFiles = 0,
    this.errors = const [],
  });

  bool get success => errors.isEmpty;

  /// 格式化释放空间
  String get formattedFreed {
    if (freedBytes < 1024) return '$freedBytes B';
    if (freedBytes < 1024 * 1024) return '${(freedBytes / 1024).toStringAsFixed(1)} KB';
    return '${(freedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 缓存清理服务
/// 负责统计与清理应用产生的临时文件与缓存：
/// - 系统临时目录（getTemporaryDirectory）
/// - 应用支持目录下的临时产物（保留数据库与配置）
/// 明确不清理：数据库文件、Hive 设置、用户手动选择的导出文件
///
/// Web 端无本地文件缓存（数据在 IndexedDB），统计为 0、清理为无操作。
class CacheService {
  /// 需要保留的后缀（数据库与配置）
  static const List<String> _keepExtensions = ['.db', '.hive', '.hive.lock'];

  /// 统计缓存占用大小（字节）
  Future<int> computeCacheSize() async {
    if (kIsWeb) return 0;
    int total = 0;
    for (final dir in await PlatformFs.cacheDirPaths()) {
      total += await PlatformFs.dirSizeExcluding(dir, _keepExtensions);
    }
    return total;
  }

  /// 清理缓存，返回释放的字节数与删除文件数
  Future<CacheCleanResult> clearCache() async {
    if (kIsWeb) {
      return const CacheCleanResult(
        errors: ['Web 端无本地文件缓存，数据存储于浏览器 IndexedDB'],
      );
    }

    int freedBytes = 0;
    int removedFiles = 0;
    final errors = <String>[];

    for (final dir in await PlatformFs.cacheDirPaths()) {
      final r = await PlatformFs.clearDirExcluding(dir, _keepExtensions);
      freedBytes += r.freedBytes;
      removedFiles += r.removedFiles;
      errors.addAll(r.errors);
    }

    return CacheCleanResult(
      freedBytes: freedBytes,
      removedFiles: removedFiles,
      errors: errors,
    );
  }
}
