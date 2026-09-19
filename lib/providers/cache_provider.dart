import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/cache_service.dart';

/// 缓存状态
class CacheState {
  final int cacheSize;
  final bool isLoading;
  final bool isClearing;
  final CacheCleanResult? lastResult;

  const CacheState({
    this.cacheSize = 0,
    this.isLoading = false,
    this.isClearing = false,
    this.lastResult,
  });

  CacheState copyWith({
    int? cacheSize,
    bool? isLoading,
    bool? isClearing,
    CacheCleanResult? lastResult,
  }) {
    return CacheState(
      cacheSize: cacheSize ?? this.cacheSize,
      isLoading: isLoading ?? this.isLoading,
      isClearing: isClearing ?? this.isClearing,
      lastResult: lastResult ?? this.lastResult,
    );
  }
}

/// 缓存 Provider
class CacheNotifier extends StateNotifier<CacheState> {
  final CacheService _service;

  CacheNotifier(this._service) : super(const CacheState()) {
    refresh();
  }

  /// 刷新缓存大小
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final size = await _service.computeCacheSize();
    state = state.copyWith(cacheSize: size, isLoading: false);
  }

  /// 清理缓存
  Future<CacheCleanResult> clear() async {
    state = state.copyWith(isClearing: true);
    final result = await _service.clearCache();
    final size = await _service.computeCacheSize();
    state = state.copyWith(
      cacheSize: size,
      isClearing: false,
      lastResult: result,
    );
    return result;
  }
}

final cacheServiceProvider = Provider<CacheService>((ref) => CacheService());

final cacheProvider = StateNotifierProvider<CacheNotifier, CacheState>((ref) {
  return CacheNotifier(ref.watch(cacheServiceProvider));
});
