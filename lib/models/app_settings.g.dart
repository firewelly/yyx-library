// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AppSettings _$AppSettingsFromJson(Map<String, dynamic> json) => AppSettings(
  themeMode: json['themeMode'] as String? ?? 'system',
  themeSeed: json['themeSeed'] as String? ?? 'b',
  fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
  marginSize: (json['marginSize'] as num?)?.toDouble() ?? 60.0,
  lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.8,
  defaultExportPath: json['defaultExportPath'] as String? ?? '',
  defaultExportFormat: json['defaultExportFormat'] as String? ?? 'txt',
  deleteAfterImport: json['deleteAfterImport'] as bool? ?? false,
  autoBackup: json['autoBackup'] as bool? ?? true,
  backupFrequency: json['backupFrequency'] as String? ?? 'daily',
  backupKeepCount: (json['backupKeepCount'] as num?)?.toInt() ?? 7,
  customDbPath: json['customDbPath'] as String? ?? '',
  libraryFolders:
      (json['libraryFolders'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  readerTheme: json['readerTheme'] as String? ?? 'sepia',
  readerZhVariant: json['readerZhVariant'] as String? ?? 'original',
  defaultEncoding: json['defaultEncoding'] as String? ?? 'auto',
  libraryRootPath: json['libraryRootPath'] as String? ?? '',
);

Map<String, dynamic> _$AppSettingsToJson(AppSettings instance) =>
    <String, dynamic>{
      'themeMode': instance.themeMode,
      'themeSeed': instance.themeSeed,
      'fontSize': instance.fontSize,
      'marginSize': instance.marginSize,
      'lineHeight': instance.lineHeight,
      'defaultExportPath': instance.defaultExportPath,
      'defaultExportFormat': instance.defaultExportFormat,
      'deleteAfterImport': instance.deleteAfterImport,
      'autoBackup': instance.autoBackup,
      'backupFrequency': instance.backupFrequency,
      'backupKeepCount': instance.backupKeepCount,
      'customDbPath': instance.customDbPath,
      'libraryFolders': instance.libraryFolders,
      'readerTheme': instance.readerTheme,
      'readerZhVariant': instance.readerZhVariant,
      'defaultEncoding': instance.defaultEncoding,
      'libraryRootPath': instance.libraryRootPath,
    };
