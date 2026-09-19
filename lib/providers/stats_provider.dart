import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import 'database_provider.dart';

/// 统计状态
class StatsState {
  final LibraryStats stats;
  final bool isLoading;
  final String? error;

  const StatsState({
    this.stats = const LibraryStats(),
    this.isLoading = false,
    this.error,
  });

  StatsState copyWith({LibraryStats? stats, bool? isLoading, String? error}) {
    return StatsState(
      stats: stats ?? this.stats,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// 统计 Provider
class StatsNotifier extends StateNotifier<StatsState> {
  final DatabaseService _db;

  StatsNotifier(this._db) : super(const StatsState()) {
    loadStats();
  }

  Future<void> loadStats() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final stats = await _db.getStats();
      state = state.copyWith(stats: stats, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> refresh() async {
    await loadStats();
  }
}

final statsProvider = StateNotifierProvider<StatsNotifier, StatsState>((ref) {
  return StatsNotifier(ref.watch(databaseServiceProvider));
});