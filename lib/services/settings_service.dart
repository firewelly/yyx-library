import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../models/app_settings.dart';
import '../utils/constants.dart';

/// 设置服务 - 基于 Hive 的偏好存储
class SettingsService {
  late Box<Map> _box;
  AppSettings _settings = const AppSettings();
  final StreamController<AppSettings> _controller = StreamController<AppSettings>.broadcast();

  /// 获取设置变更流
  Stream<AppSettings> get settingsStream => _controller.stream;

  /// 当前设置（内存缓存）
  AppSettings get settings => _settings;

  /// 初始化：打开 Hive box 并加载设置
  Future<void> initialize() async {
    _box = await Hive.openBox<Map>(AppConstants.settingsBox);
    _loadSettings();
  }

  void _loadSettings() {
    final saved = _box.get('settings');
    if (saved != null) {
      _settings = AppSettings.fromJson(Map<String, dynamic>.from(saved));
    }
    _controller.add(_settings);
  }

  Future<void> _save() async {
    await _box.put('settings', _settings.toJson());
    _controller.add(_settings);
  }

  // ==================== 主题 ====================

  ThemeMode get themeMode {
    switch (_settings.themeMode) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final modeStr = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    _settings = _settings.copyWith(themeMode: modeStr);
    await _save();
  }

  /// 应用配色方案 id: 'a' / 'b' / 'c' / 'd'
  String get themeSeed => _settings.themeSeed;
  Future<void> setThemeSeed(String id) async {
    _settings = _settings.copyWith(themeSeed: id);
    await _save();
  }

  // ==================== 阅读设置 ====================

  /// 阅读器主题 id: 'paper' / 'sepia' / 'dark' / 'green'
  String get readerTheme => _settings.readerTheme;
  Future<void> setReaderTheme(String themeId) async {
    _settings = _settings.copyWith(readerTheme: themeId);
    await _save();
  }

  double get fontSize => _settings.fontSize;
  Future<void> setFontSize(double size) async {
    _settings = _settings.copyWith(fontSize: size);
    await _save();
  }

  double get marginSize => _settings.marginSize;
  Future<void> setMarginSize(double size) async {
    _settings = _settings.copyWith(marginSize: size);
    await _save();
  }

  double get lineHeight => _settings.lineHeight;
  Future<void> setLineHeight(double height) async {
    _settings = _settings.copyWith(lineHeight: height);
    await _save();
  }

  /// 阅读器繁简显示: 'original' / 'simplified' / 'traditional'
  String get readerZhVariant => _settings.readerZhVariant;
  Future<void> setReaderZhVariant(String variant) async {
    _settings = _settings.copyWith(readerZhVariant: variant);
    await _save();
  }

  // ==================== 导入导出设置 ====================

  /// TXT 导入默认编码: 'auto' / 'utf-8' / 'gbk' / 'gb18030' / 'big5'
  String get defaultEncoding => _settings.defaultEncoding;
  Future<void> setDefaultEncoding(String encoding) async {
    _settings = _settings.copyWith(defaultEncoding: encoding);
    await _save();
  }

  /// 书库根目录（跨系统共享数据库时，书籍路径存为相对该目录）
  String get libraryRootPath => _settings.libraryRootPath;
  Future<void> setLibraryRootPath(String path) async {
    _settings = _settings.copyWith(libraryRootPath: path);
    await _save();
  }

  String get defaultExportPath => _settings.defaultExportPath;
  Future<void> setDefaultExportPath(String path) async {
    _settings = _settings.copyWith(defaultExportPath: path);
    await _save();
  }

  String get defaultExportFormat => _settings.defaultExportFormat;
  Future<void> setDefaultExportFormat(String format) async {
    _settings = _settings.copyWith(defaultExportFormat: format);
    await _save();
  }

  bool get deleteAfterImport => _settings.deleteAfterImport;
  Future<void> setDeleteAfterImport(bool value) async {
    _settings = _settings.copyWith(deleteAfterImport: value);
    await _save();
  }

  // ==================== 备份设置 ====================

  bool get autoBackup => _settings.autoBackup;
  Future<void> setAutoBackup(bool value) async {
    _settings = _settings.copyWith(autoBackup: value);
    await _save();
  }

  String get backupFrequency => _settings.backupFrequency;
  Future<void> setBackupFrequency(String freq) async {
    _settings = _settings.copyWith(backupFrequency: freq);
    await _save();
  }

  int get backupKeepCount => _settings.backupKeepCount;
  Future<void> setBackupKeepCount(int count) async {
    _settings = _settings.copyWith(backupKeepCount: count);
    await _save();
  }

  // ==================== 数据库路径设置 ====================

  String get customDbPath => _settings.customDbPath;
  Future<void> setCustomDbPath(String path) async {
    _settings = _settings.copyWith(customDbPath: path);
    await _save();
  }

  // ==================== 书库文件夹设置 ====================

  List<String> get libraryFolders => _settings.libraryFolders;
  Future<void> setLibraryFolders(List<String> folders) async {
    // 去重 + 去空
    final cleaned = <String>[];
    for (final f in folders) {
      final t = f.trim();
      if (t.isNotEmpty && !cleaned.contains(t)) cleaned.add(t);
    }
    _settings = _settings.copyWith(libraryFolders: cleaned);
    await _save();
  }

  /// 关闭 Hive box
  Future<void> close() async {
    await _controller.close();
    await _box.close();
  }
}