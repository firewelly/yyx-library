import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;

import 'database_service.dart';
import 'import_service.dart';
import 'platform_fs.dart';
import '../models/models.dart';

/// 扫描结果统计
class ScanResult {
  int totalFiles = 0;
  /// 未物化（OneDrive 占位）文件数，全部跳过、不触发云端下载
  int placeholderSkipped = 0;
  /// 新导入的书
  int imported = 0;
  /// 已存在但文件有更新（章节有变化）
  int updated = 0;
  /// 已存在且文件无变化
  int noChange = 0;
  int failed = 0;
  final List<String> errors = [];

  bool get isEmpty =>
      totalFiles == 0 && placeholderSkipped == 0 && imported == 0 &&
      updated == 0 && noChange == 0 && failed == 0 && errors.isEmpty;
}

/// 书库扫描服务
///
/// 遍历配置的书库文件夹（可多个）：
/// - 自动检测并跳过 OneDrive 占位文件（未物化，`du -ak` 占用为 0，不触发下载）
/// - 书名（文件名去扩展名）不在库中 → 导入
/// - 书名已在库中但文件 mtime 新于书的更新时间 → 重新导入（内部检测章节变化）
/// - 其余已存在且无变化的文件直接跳过
///
/// 仅桌面端可用；Web 端无本地文件系统，扫描直接返回错误说明。
class LibraryScanService {
  final DatabaseService _db;
  final ImportService _import;

  LibraryScanService(this._db, this._import);

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// 扫描所有书库文件夹并导入新书/更新章节
  ///
  /// [folders] 书库文件夹绝对路径列表；[onProgress] 进度回调（已处理数/总数/当前消息）。
  Future<ScanResult> scanFolders(
    List<String> folders, {
    void Function(int processed, int total, String message)? onProgress,
  }) async {
    _cancelled = false;
    final result = ScanResult();

    if (kIsWeb) {
      result.errors.add('Web 端无本地文件系统，不支持书库扫描。请使用文件导入功能。');
      return result;
    }

    final validFolders = <String>[];
    for (final folder in folders) {
      // 支持相对路径（以程序目录为基准），如「novels」「H」
      final resolved = PlatformFs.resolvePath(folder);
      if (await PlatformFs.dirExists(resolved)) {
        validFolders.add(resolved);
      } else {
        result.errors.add('文件夹不存在: $folder（解析为 $resolved）');
      }
    }
    if (validFolders.isEmpty) {
      if (result.errors.isEmpty) {
        result.errors.add('未配置书库文件夹，请先在设置中添加');
      }
      return result;
    }

    // 1. 收集所有支持格式的文件，同时检测占位文件
    final files = <String>[];
    final conflictCopyRe = RegExp(r'\(\d{4}-\d{2}-\d{2}');
    for (final folder in validFolders) {
      final placeholders = await PlatformFs.findPlaceholderFiles(folder);
      result.placeholderSkipped += placeholders.length;

      final listed = await PlatformFs.listFiles(
        folder,
        recursive: true,
        extensions: kSupportedImportExtensions.toSet(),
        skipZeroByte: true, // 0 字节兜底
      );
      for (final path in listed) {
        if (_cancelled) break;
        final lower = path.toLowerCase();
        if (lower.endsWith('.bak') || lower.endsWith('.crdownload')) continue;
        if (conflictCopyRe.hasMatch(path)) continue; // Finder 冲突副本
        if (placeholders.contains(p.normalize(path))) continue; // 占位跳过
        files.add(path);
      }
      if (_cancelled) break;
    }

    // 2. 预加载库内书名 → Book 映射（避免逐本查询）
    final bookByTitle = <String, Book>{};
    for (final row in await _db.db.query('books')) {
      final book = Book.fromJson(row);
      bookByTitle[book.title] = book;
    }

    // 3. 逐本处理
    result.totalFiles = files.length;
    final total = files.length;
    for (int i = 0; i < files.length; i++) {
      if (_cancelled) break;
      final path = files[i];
      final title = p.basenameWithoutExtension(path).trim();
      onProgress?.call(i + 1, total, '正在处理: $title');

      try {
        final existing = bookByTitle[title];
        // 已存在且文件不比库中记录新 → 跳过
        if (existing != null) {
          final fileMtime = await PlatformFs.lastModified(path);
          final bookTime = DateTime.tryParse(existing.updatedAt) ?? DateTime(1970);
          if (fileMtime != null && !fileMtime.isAfter(bookTime)) {
            result.noChange++;
            continue;
          }
        }

        final r = await _import.importByExtension(path);
        if (r.success) {
          if (existing != null) {
            result.updated++;
          } else {
            result.imported++;
            // 同步内存映射，后续同名文件不会重复处理
            bookByTitle[title] = Book(
              title: title,
              createdAt: DateTime.now().toIso8601String(),
              updatedAt: DateTime.now().toIso8601String(),
            );
          }
        } else if (r.message.contains('无变化')) {
          result.noChange++;
        } else {
          result.failed++;
          result.errors.add('$title: ${r.message}');
        }
      } catch (e) {
        result.failed++;
        result.errors.add('$title: $e');
      }
    }

    return result;
  }
}
