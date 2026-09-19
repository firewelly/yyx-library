import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/backup_service.dart';
import 'database_provider.dart';

/// 备份状态
class BackupState {
  final bool isBackingUp;
  final bool isRestoring;
  final String? lastBackupPath;
  final String? error;
  final List<BackupInfo> backups;

  const BackupState({
    this.isBackingUp = false,
    this.isRestoring = false,
    this.lastBackupPath,
    this.error,
    this.backups = const [],
  });

  BackupState copyWith({
    bool? isBackingUp,
    bool? isRestoring,
    String? lastBackupPath,
    String? error,
    List<BackupInfo>? backups,
  }) {
    return BackupState(
      isBackingUp: isBackingUp ?? this.isBackingUp,
      isRestoring: isRestoring ?? this.isRestoring,
      lastBackupPath: lastBackupPath ?? this.lastBackupPath,
      error: error ?? this.error,
      backups: backups ?? this.backups,
    );
  }
}

/// 备份 Provider
class BackupNotifier extends StateNotifier<BackupState> {
  final BackupService _backupService;

  BackupNotifier(this._backupService) : super(const BackupState());

  /// 执行备份
  Future<String> backup({String? targetDir}) async {
    state = state.copyWith(isBackingUp: true, error: null);
    try {
      final path = await _backupService.backup(targetDir: targetDir);
      state = state.copyWith(isBackingUp: false, lastBackupPath: path);
      // 刷新备份列表
      await loadBackups(backupDir: targetDir);
      return path;
    } catch (e) {
      state = state.copyWith(isBackingUp: false, error: '备份失败: $e');
      rethrow;
    }
  }

  /// 从备份恢复
  Future<void> restore(String backupFilePath) async {
    state = state.copyWith(isRestoring: true, error: null);
    try {
      await _backupService.restore(backupFilePath);
      state = state.copyWith(isRestoring: false);
    } catch (e) {
      state = state.copyWith(isRestoring: false, error: '恢复失败: $e');
    }
  }

  /// 加载备份列表
  Future<void> loadBackups({String? backupDir}) async {
    try {
      final backups = await _backupService.listBackups(backupDir: backupDir);
      state = state.copyWith(backups: backups);
    } catch (e) {
      state = state.copyWith(error: '加载备份列表失败: $e');
    }
  }

  /// 删除备份
  Future<void> deleteBackup(String backupFilePath, {String? backupDir}) async {
    try {
      await _backupService.deleteBackup(backupFilePath);
      await loadBackups(backupDir: backupDir);
    } catch (e) {
      state = state.copyWith(error: '删除备份失败: $e');
    }
  }

  // ============================================================
  // SQL dump 备份/恢复（全平台通用，Web 端的主要备份方式）
  // ============================================================

  /// 导出 SQL dump（Web 端由调用方触发浏览器下载）
  Future<String> backupSql() async {
    state = state.copyWith(isBackingUp: true, error: null);
    try {
      final sql = await _backupService.backupSqlDump();
      state = state.copyWith(isBackingUp: false);
      return sql;
    } catch (e) {
      state = state.copyWith(isBackingUp: false, error: '备份失败: $e');
      rethrow;
    }
  }

  /// 从 SQL dump 恢复（完成后建议重启应用）
  Future<void> restoreSql(String sql) async {
    state = state.copyWith(isRestoring: true, error: null);
    try {
      await _backupService.restoreSqlDump(sql);
      state = state.copyWith(isRestoring: false);
    } catch (e) {
      state = state.copyWith(isRestoring: false, error: '恢复失败: $e');
      rethrow;
    }
  }
}

final backupProvider = StateNotifierProvider<BackupNotifier, BackupState>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return BackupNotifier(BackupService(db));
});