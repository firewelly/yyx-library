import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/import_service.dart';
import 'database_provider.dart';
import 'settings_provider.dart';

/// 导入状态
class ImportState {
  final bool isImporting;
  final double progress;
  final String statusMessage;
  final ImportResult? lastResult;
  final BatchImportResult? batchResult;
  final String? error;

  const ImportState({
    this.isImporting = false,
    this.progress = 0,
    this.statusMessage = '',
    this.lastResult,
    this.batchResult,
    this.error,
  });

  ImportState copyWith({
    bool? isImporting,
    double? progress,
    String? statusMessage,
    ImportResult? lastResult,
    BatchImportResult? batchResult,
    String? error,
  }) {
    return ImportState(
      isImporting: isImporting ?? this.isImporting,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      lastResult: lastResult ?? this.lastResult,
      batchResult: batchResult ?? this.batchResult,
      error: error,
    );
  }
}

/// 导入 Provider
class ImportNotifier extends StateNotifier<ImportState> {
  final ImportService _importService;

  /// 读取「导入设置-默认编码」（随设置变化）
  final String Function() _defaultEncoding;

  ImportNotifier(this._importService, this._defaultEncoding)
      : super(const ImportState());

  /// 导入单个文件(自动按扩展名分派:TXT/EPUB/PDF/MOBI/AZW/AZW3)
  Future<void> importFile(String filePath, {String? author, List<String>? tags}) async {
    final extLabel = _formatLabel(filePath);
    state = state.copyWith(isImporting: true, progress: 0, error: null, statusMessage: '正在导入 $extLabel...');
    try {
      final result = await _importService.importByExtension(
        filePath,
        author: author,
        tags: tags,
        encoding: _defaultEncoding(),
      );
      state = state.copyWith(
        isImporting: false,
        progress: 1.0,
        lastResult: result,
        statusMessage: result.success ? '导入成功' : '导入失败',
        error: result.success ? null : result.message,
      );
    } catch (e) {
      state = state.copyWith(isImporting: false, error: e.toString());
    }
  }

  /// 按字节导入文件（Web 端主入口：file_picker 在 Web 上只有 bytes 无路径）
  Future<void> importBytes(String fileName, Uint8List bytes, {String? author, List<String>? tags}) async {
    final extLabel = _formatLabel(fileName);
    state = state.copyWith(isImporting: true, progress: 0, error: null, statusMessage: '正在导入 $extLabel...');
    try {
      final result = await _importService.importByBytes(
        fileName,
        bytes,
        author: author,
        tags: tags,
        encoding: _defaultEncoding(),
      );
      state = state.copyWith(
        isImporting: false,
        progress: 1.0,
        lastResult: result,
        statusMessage: result.success ? '导入成功' : '导入失败',
        error: result.success ? null : result.message,
      );
    } catch (e) {
      state = state.copyWith(isImporting: false, error: e.toString());
    }
  }

  /// 兼容旧调用:导入 TXT
  Future<void> importTxt(String filePath, {String? author, List<String>? tags}) =>
      importFile(filePath, author: author, tags: tags);

  /// 兼容旧调用:导入 EPUB
  Future<void> importEpub(String filePath, {String? author, List<String>? tags}) =>
      importFile(filePath, author: author, tags: tags);

  /// 导入 PDF
  Future<void> importPdf(String filePath, {String? author, List<String>? tags}) =>
      importFile(filePath, author: author, tags: tags);

  /// 导入 MOBI/Kindle
  Future<void> importMobi(String filePath, {String? author, List<String>? tags}) =>
      importFile(filePath, author: author, tags: tags);

  /// 根据扩展名返回格式标签(用于状态提示)
  String _formatLabel(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.pdf')) return 'PDF';
    if (lower.endsWith('.mobi')) return 'MOBI';
    if (lower.endsWith('.azw') || lower.endsWith('.azw3')) return 'Kindle';
    if (lower.endsWith('.epub')) return 'EPUB';
    return 'TXT';
  }

  /// 批量导入文件夹
  Future<void> importFolder(String folderPath, {bool recursive = false, String? author, List<String>? tags, bool deleteAfter = false}) async {
    state = state.copyWith(isImporting: true, progress: 0, error: null, statusMessage: '正在扫描文件夹...');
    try {
      final result = await _importService.importFolder(
        folderPath,
        recursive: recursive,
        author: author,
        tags: tags,
        deleteAfterImport: deleteAfter,
        encoding: _defaultEncoding(),
        progressCallback: (current, total, message) {
          state = state.copyWith(
            progress: total > 0 ? current / total : 0,
            statusMessage: message,
          );
        },
      );
      state = state.copyWith(
        isImporting: false,
        progress: 1.0,
        batchResult: result,
        statusMessage: '导入完成: 成功${result.succeeded}, 失败${result.failed}',
      );
    } catch (e) {
      state = state.copyWith(isImporting: false, error: e.toString());
    }
  }

  /// 重置状态
  void reset() {
    state = const ImportState();
  }
}

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(
    ref.watch(databaseServiceProvider),
    // 跨系统共享数据库：书籍路径按「书库根目录」相对化存储
    pathBase: () => ref.read(settingsProvider).settings.libraryRootPath,
  );
});

final importProvider = StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  return ImportNotifier(
    ref.watch(importServiceProvider),
    () => ref.read(settingsProvider).settings.defaultEncoding,
  );
});