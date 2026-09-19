import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/library_scan_service.dart';
import 'database_provider.dart';
import 'import_provider.dart';

/// 扫描状态
class ScanState {
  final bool isScanning;
  final double progress;
  final String statusMessage;
  final ScanResult? result;
  final String? error;

  const ScanState({
    this.isScanning = false,
    this.progress = 0,
    this.statusMessage = '',
    this.result,
    this.error,
  });

  ScanState copyWith({
    bool? isScanning,
    double? progress,
    String? statusMessage,
    ScanResult? result,
    String? error,
  }) {
    return ScanState(
      isScanning: isScanning ?? this.isScanning,
      progress: progress ?? this.progress,
      statusMessage: statusMessage ?? this.statusMessage,
      result: result ?? this.result,
      error: error ?? this.error,
    );
  }
}

/// 书库扫描 Provider（首页「扫描书库」）
///
/// 扫描运行中再次触发会取消扫描（「后台手动扫描」语义：可随时中止）。
class ScanNotifier extends StateNotifier<ScanState> {
  final LibraryScanService _service;

  ScanNotifier(this._service) : super(const ScanState());

  /// 开始扫描；若正在扫描则切换为取消
  Future<void> startScan(List<String> folders) async {
    if (state.isScanning) {
      _service.cancel();
      state = state.copyWith(statusMessage: '正在取消...');
      return;
    }
    state = const ScanState(isScanning: true, statusMessage: '准备扫描...');
    try {
      final result = await _service.scanFolders(
        folders,
        onProgress: (processed, total, message) {
          state = state.copyWith(
            progress: total > 0 ? processed / total : 0,
            statusMessage: message,
          );
        },
      );
      state = state.copyWith(
        isScanning: false,
        progress: 1.0,
        result: result,
        statusMessage: '扫描完成',
      );
    } catch (e) {
      state = state.copyWith(isScanning: false, error: e.toString());
    }
  }

  /// 重置状态（扫描完成后清空结果显示）
  void reset() {
    state = const ScanState();
  }
}

final libraryScanServiceProvider = Provider<LibraryScanService>((ref) {
  return LibraryScanService(
    ref.watch(databaseServiceProvider),
    ref.watch(importServiceProvider),
  );
});

final scanProvider = StateNotifierProvider<ScanNotifier, ScanState>((ref) {
  return ScanNotifier(ref.watch(libraryScanServiceProvider));
});
