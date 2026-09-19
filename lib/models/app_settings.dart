import 'package:json_annotation/json_annotation.dart';

part 'app_settings.g.dart';

/// 应用设置模型（存储于 Hive）
@JsonSerializable()
class AppSettings {
  /// 主题模式: 'light', 'dark', 'system'
  final String themeMode;

  /// 应用配色方案 id: 'a' 墨韵书阁 | 'b' 靛蓝墨海 | 'c' 暮色书房 | 'd' 墨夜星河
  final String themeSeed;

  /// 字体大小 (12-30)
  final double fontSize;

  /// 左右边距 (20-200)
  final double marginSize;

  /// 行间距 (1.0-3.0)
  final double lineHeight;

  /// 默认导出路径
  final String defaultExportPath;

  /// 默认导出格式: 'txt', 'epub', 'pdf'
  final String defaultExportFormat;

  /// 是否导入后删除原文件
  final bool deleteAfterImport;

  /// 自动备份开关
  final bool autoBackup;

  /// 备份频率: 'daily', 'weekly', 'monthly'
  final String backupFrequency;

  /// 备份保留份数
  final int backupKeepCount;

  /// 自定义数据库路径（用于跨平台共享，如 OneDrive/NAS）
  /// 为空时使用默认平台路径
  final String customDbPath;

  /// 书库文件夹列表（可多个）：首页「扫描书库」会遍历这些目录，
  /// 发现新文件/更新文件自动导入；OneDrive 占位（未物化）文件自动跳过。
  final List<String> libraryFolders;

  /// 阅读器主题: 'paper', 'sepia', 'dark', 'green'
  final String readerTheme;

  /// 阅读器繁简显示: 'original'（原文）| 'simplified'（简体）| 'traditional'（繁体）
  final String readerZhVariant;

  /// TXT 导入默认编码: 'auto' | 'utf-8' | 'gbk' | 'gb18030' | 'big5'
  /// 'auto' 时按 UTF-8 → GBK → Big5 顺序自动探测
  final String defaultEncoding;

  /// 书库根目录（跨系统共享数据库用）：
  /// 非空时，导入的书籍 filePath 存为相对该目录的路径（正斜杠分隔），
  /// 各设备配置各自的本机根目录即可共用同一数据库
  final String libraryRootPath;

  const AppSettings({
    this.themeMode = 'system',
    this.themeSeed = 'b',
    this.fontSize = 18.0,
    this.marginSize = 60.0,
    this.lineHeight = 1.8,
    this.defaultExportPath = '',
    this.defaultExportFormat = 'txt',
    this.deleteAfterImport = false,
    this.autoBackup = true,
    this.backupFrequency = 'daily',
    this.backupKeepCount = 7,
    this.customDbPath = '',
    this.libraryFolders = const [],
    this.readerTheme = 'sepia',
    this.readerZhVariant = 'original',
    this.defaultEncoding = 'auto',
    this.libraryRootPath = '',
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);
  Map<String, dynamic> toJson() => _$AppSettingsToJson(this);

  AppSettings copyWith({
    String? themeMode,
    String? themeSeed,
    double? fontSize,
    double? marginSize,
    double? lineHeight,
    String? defaultExportPath,
    String? defaultExportFormat,
    bool? deleteAfterImport,
    bool? autoBackup,
    String? backupFrequency,
    int? backupKeepCount,
    String? customDbPath,
    List<String>? libraryFolders,
    String? readerTheme,
    String? readerZhVariant,
    String? defaultEncoding,
    String? libraryRootPath,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      themeSeed: themeSeed ?? this.themeSeed,
      fontSize: fontSize ?? this.fontSize,
      marginSize: marginSize ?? this.marginSize,
      lineHeight: lineHeight ?? this.lineHeight,
      defaultExportPath: defaultExportPath ?? this.defaultExportPath,
      defaultExportFormat: defaultExportFormat ?? this.defaultExportFormat,
      deleteAfterImport: deleteAfterImport ?? this.deleteAfterImport,
      autoBackup: autoBackup ?? this.autoBackup,
      backupFrequency: backupFrequency ?? this.backupFrequency,
      backupKeepCount: backupKeepCount ?? this.backupKeepCount,
      customDbPath: customDbPath ?? this.customDbPath,
      libraryFolders: libraryFolders ?? this.libraryFolders,
      readerTheme: readerTheme ?? this.readerTheme,
      readerZhVariant: readerZhVariant ?? this.readerZhVariant,
      defaultEncoding: defaultEncoding ?? this.defaultEncoding,
      libraryRootPath: libraryRootPath ?? this.libraryRootPath,
    );
  }
}
