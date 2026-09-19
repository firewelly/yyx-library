import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'database_service.dart';
import 'platform_fs.dart';

/// 备份与恢复服务
///
/// 仅桌面端可用：通过复制 SQLite 数据库文件实现备份。
/// Web 端数据库存于浏览器 IndexedDB（WASM 虚拟文件系统），
/// 无法以文件形式复制，备份/恢复在 Web 端抛 [UnsupportedError]，
/// 由设置页在 Web 端隐藏相关入口。
class BackupService {
  final DatabaseService _db;

  BackupService(this._db);

  /// 备份数据库到指定目录
  /// 返回备份文件路径
  Future<String> backup({String? targetDir}) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 端暂不支持数据库备份，请在桌面端操作');
    }

    final dir = targetDir ?? await PlatformFs.defaultBackupDir();
    await PlatformFs.ensureDir(dir);

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
    final fileName = 'novelmgt_backup_$timestamp.db';
    final backupPath = p.join(dir, fileName);

    // 获取源数据库路径
    final sourcePath = _db.dbFilePath;
    if (sourcePath == null) {
      throw StateError('数据库未初始化');
    }

    // 复制数据库文件
    if (!await PlatformFs.fileExists(sourcePath)) {
      throw Exception('数据库文件不存在: $sourcePath');
    }
    await PlatformFs.copyFile(sourcePath, backupPath);

    // 写入备份元数据
    await PlatformFs.writeTextFile(
      dir,
      'novelmgt_backup_$timestamp.meta',
      'version=1\ntimestamp=$timestamp\napp=novelmgt_flutter\ndb_version=1\n',
    );

    // 清理旧备份（保留最近 N 份）
    await _cleanupOldBackups(dir, keepCount: 7);

    return backupPath;
  }

  /// 从备份文件恢复数据库
  Future<void> restore(String backupFilePath) async {
    if (kIsWeb) {
      throw UnsupportedError('Web 端暂不支持数据库恢复，请在桌面端操作');
    }

    if (!await PlatformFs.fileExists(backupFilePath)) {
      throw Exception('备份文件不存在: $backupFilePath');
    }

    // 获取当前数据库路径
    final dbFile = _db.dbFilePath;
    if (dbFile == null) {
      throw StateError('数据库未初始化');
    }

    // 关闭当前数据库
    await _db.close();

    // 覆盖数据库文件
    await PlatformFs.copyFile(backupFilePath, dbFile);

    // 重新初始化数据库
    await _db.initialize();
  }

  /// 列出所有备份文件
  Future<List<BackupInfo>> listBackups({String? backupDir}) async {
    if (kIsWeb) return [];

    final dir = backupDir ?? await PlatformFs.defaultBackupDir();
    final paths = await PlatformFs.listFiles(dir, extensions: const {'.db'});

    final backups = <BackupInfo>[];
    for (final path in paths) {
      final stat = await PlatformFs.statFile(path);
      if (stat == null) continue;
      final fileName = p.basename(path);
      // 从文件名提取时间戳: novelmgt_backup_2026-04-10T09-30-00.db
      final timestampMatch = RegExp(r'novelmgt_backup_(.+)\.db').firstMatch(fileName);
      final timestamp = timestampMatch?.group(1) ?? '';
      backups.add(BackupInfo(
        path: path,
        fileName: fileName,
        timestamp: timestamp,
        fileSize: stat.size,
        modifiedTime: stat.modified,
      ));
    }

    // 按时间降序排列
    backups.sort((a, b) => b.modifiedTime.compareTo(a.modifiedTime));
    return backups;
  }

  /// 删除指定备份
  Future<bool> deleteBackup(String backupFilePath) async {
    if (kIsWeb) return false;
    if (!await PlatformFs.fileExists(backupFilePath)) return false;

    // 删除对应的 .db 文件
    await PlatformFs.deleteFile(backupFilePath);

    // 删除对应的 .meta 文件（如果存在）
    final metaPath = backupFilePath.replaceAll('.db', '.meta');
    await PlatformFs.deleteFile(metaPath);

    return true;
  }

  /// 清理旧备份，保留最近 keepCount 份
  Future<void> _cleanupOldBackups(String dir, {int keepCount = 7}) async {
    final backups = await listBackups(backupDir: dir);
    if (backups.length <= keepCount) return;

    // 删除最旧的备份
    for (int i = keepCount; i < backups.length; i++) {
      await deleteBackup(backups[i].path);
    }
  }

  // ============================================================
  // SQL dump 备份/恢复（全平台通用，Web 端的主要备份方式）
  // ============================================================

  /// 导出数据库为 SQL dump 文本。
  ///
  /// Web 端由设置页调用后经浏览器下载 .sql 文件；
  /// 桌面端也可用作跨设备迁移格式（可导入任意端的库）。
  Future<String> backupSqlDump() async {
    return _db.exportSqlDump();
  }

  /// 从 SQL dump 文本恢复（清空当前库后导入，单事务失败自动回滚）。
  ///
  /// 全平台可用（不依赖数据库文件路径）；完成后建议重启应用。
  Future<void> restoreSqlDump(String sql) async {
    await _db.restoreFromSqlDump(sql);
  }
}

/// 备份文件信息
class BackupInfo {
  final String path;
  final String fileName;
  final String timestamp;
  final int fileSize;
  final DateTime modifiedTime;

  const BackupInfo({
    required this.path,
    required this.fileName,
    required this.timestamp,
    required this.fileSize,
    required this.modifiedTime,
  });

  /// 格式化文件大小
  String get formattedSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
