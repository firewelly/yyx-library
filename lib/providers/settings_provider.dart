import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../utils/constants.dart';

/// 设置状态
class SettingsState {
  final AppSettings settings;
  final ThemeMode themeMode;
  final bool isLoading;

  const SettingsState({
    this.settings = const AppSettings(),
    this.themeMode = ThemeMode.system,
    this.isLoading = false,
  });

  SettingsState copyWith({AppSettings? settings, ThemeMode? themeMode, bool? isLoading}) {
    return SettingsState(
      settings: settings ?? this.settings,
      themeMode: themeMode ?? this.themeMode,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 设置 Provider
class SettingsNotifier extends StateNotifier<SettingsState> {
  final SettingsService _service;

  SettingsNotifier(this._service) : super(const SettingsState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true);
    await _service.initialize();
    final settings = _service.settings;
    state = SettingsState(
      settings: settings,
      themeMode: _service.themeMode,
      isLoading: false,
    );
  }

  // 主题
  Future<void> setThemeMode(ThemeMode mode) async {
    await _service.setThemeMode(mode);
    state = state.copyWith(themeMode: mode, settings: _service.settings);
  }

  /// 切换应用配色方案
  Future<void> setThemeSeed(String id) async {
    await _service.setThemeSeed(id);
    state = state.copyWith(settings: _service.settings);
  }

  // 阅读设置
  Future<void> setFontSize(double size) async {
    await _service.setFontSize(size.clamp(AppConstants.minFontSize, AppConstants.maxFontSize));
    state = state.copyWith(settings: _service.settings);
  }

  Future<void> setMarginSize(double size) async {
    await _service.setMarginSize(size.clamp(AppConstants.minMargin, AppConstants.maxMargin));
    state = state.copyWith(settings: _service.settings);
  }

  Future<void> setLineHeight(double height) async {
    await _service.setLineHeight(height.clamp(AppConstants.minLineHeight, AppConstants.maxLineHeight));
    state = state.copyWith(settings: _service.settings);
  }

  // 阅读器主题
  Future<void> setReaderTheme(String themeId) async {
    await _service.setReaderTheme(themeId);
    state = state.copyWith(settings: _service.settings);
  }

  /// 阅读器繁简显示: 'original' / 'simplified' / 'traditional'
  Future<void> setReaderZhVariant(String variant) async {
    await _service.setReaderZhVariant(variant);
    state = state.copyWith(settings: _service.settings);
  }

  /// TXT 导入默认编码
  Future<void> setDefaultEncoding(String encoding) async {
    await _service.setDefaultEncoding(encoding);
    state = state.copyWith(settings: _service.settings);
  }

  /// 书库根目录（跨系统相对路径基准）
  Future<void> setLibraryRootPath(String path) async {
    await _service.setLibraryRootPath(path);
    state = state.copyWith(settings: _service.settings);
  }

  // 导入导出设置
  Future<void> setDefaultExportPath(String path) async {
    await _service.setDefaultExportPath(path);
    state = state.copyWith(settings: _service.settings);
  }

  Future<void> setDefaultExportFormat(String format) async {
    await _service.setDefaultExportFormat(format);
    state = state.copyWith(settings: _service.settings);
  }

  Future<void> setDeleteAfterImport(bool value) async {
    await _service.setDeleteAfterImport(value);
    state = state.copyWith(settings: _service.settings);
  }

  // 备份设置
  Future<void> setAutoBackup(bool value) async {
    await _service.setAutoBackup(value);
    state = state.copyWith(settings: _service.settings);
  }

  Future<void> setBackupFrequency(String freq) async {
    await _service.setBackupFrequency(freq);
    state = state.copyWith(settings: _service.settings);
  }

  Future<void> setBackupKeepCount(int count) async {
    await _service.setBackupKeepCount(count);
    state = state.copyWith(settings: _service.settings);
  }

  // 数据库路径设置
  Future<void> setCustomDbPath(String path) async {
    await _service.setCustomDbPath(path);
    state = state.copyWith(settings: _service.settings);
  }

  // 书库文件夹设置
  Future<void> setLibraryFolders(List<String> folders) async {
    await _service.setLibraryFolders(folders);
    state = state.copyWith(settings: _service.settings);
  }
}

final settingsServiceProvider = Provider<SettingsService>((ref) => SettingsService());

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier(ref.watch(settingsServiceProvider));
});