/// 桌面端（dart:io）文件系统门面实现。
library;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'platform_fs_types.dart';

export 'platform_fs_types.dart';

/// 平台文件系统门面（桌面端实现）
class PlatformFs {
  PlatformFs._();

  static Future<bool> fileExists(String path) => File(path).exists();

  static Future<bool> dirExists(String path) => Directory(path).exists();

  static Future<void> ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 读取文件字节；文件不存在返回 null
  static Future<Uint8List?> readBytes(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  /// 写入文本文件到 [dir]/[fileName]（自动创建目录），返回完整路径
  static Future<String> writeTextFile(String dir, String fileName, String content) async {
    await ensureDir(dir);
    final path = p.join(dir, fileName);
    await File(path).writeAsString(content, encoding: utf8);
    return path;
  }

  /// 写入二进制文件到 [dir]/[fileName]（自动创建目录），返回完整路径
  static Future<String> writeBytesFile(String dir, String fileName, List<int> bytes) async {
    await ensureDir(dir);
    final path = p.join(dir, fileName);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  static Future<void> copyFile(String from, String to) => File(from).copy(to);

  /// 重命名/移动文件（同目录下即重命名）
  static Future<void> moveFile(String from, String to) => File(from).rename(to);

  /// 删除文件（不存在时静默返回）
  static Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<DateTime?> lastModified(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      return file.lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  static Future<FileStatInfo?> statFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final stat = file.statSync();
    return FileStatInfo(size: stat.size, modified: stat.modified);
  }

  /// 列出目录下匹配扩展名的文件路径。
  /// [extensions] 为 null 表示不过滤；[skipZeroByte] 跳过空文件。
  static Future<List<String>> listFiles(
    String dir, {
    bool recursive = false,
    Set<String>? extensions,
    bool skipZeroByte = false,
  }) async {
    final results = <String>[];
    final directory = Directory(dir);
    if (!await directory.exists()) return results;

    await for (final entity in directory.list(recursive: recursive)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (extensions != null) {
        final lower = path.toLowerCase();
        if (!extensions.any(lower.endsWith)) continue;
      }
      if (skipZeroByte) {
        try {
          if (entity.lengthSync() <= 0) continue;
        } catch (_) {
          continue; // 无法读取大小的文件（如权限问题）跳过
        }
      }
      results.add(path);
    }
    return results;
  }

  /// 用 `du -ak` 检测目录树中的 OneDrive 占位（未物化）文件。
  /// 只读元数据不触发云端下载；无 du 命令的平台返回空集合。
  static Future<Set<String>> findPlaceholderFiles(String dir) async {
    try {
      final proc = await Process.run('du', ['-ak', dir]);
      if (proc.exitCode != 0) {
        return await (Platform.isWindows ? _findPlaceholdersWindows(dir) : Future.value(<String>{}));
      }
      final set = <String>{};
      for (final line in proc.stdout.toString().split('\n')) {
        final tab = line.indexOf('\t');
        if (tab < 0) continue;
        if (int.tryParse(line.substring(0, tab)) == 0) {
          set.add(p.normalize(line.substring(tab + 1)));
        }
      }
      return set;
    } catch (_) {
      // 无 du 命令的平台：Windows 用文件属性检测，其余不做（靠 0 字节兜底）
      return await (Platform.isWindows ? _findPlaceholdersWindows(dir) : Future.value(<String>{}));
    }
  }

  /// Windows：PowerShell 批量枚举 OneDrive 按需占位文件（只读属性，不触发下载）。
  /// RecallOnDataAccess 0x400000 / RecallOnOpen 0x40000 / Offline 0x1000。
  static Future<Set<String>> _findPlaceholdersWindows(String dir) async {
    // 注意：非原始字符串中 \$ 转义为 PowerShell 需要的 $ 变量符号
    const ps = '''
\$ErrorActionPreference = 'SilentlyContinue'
Get-ChildItem -LiteralPath \$args[0] -Recurse -File | ForEach-Object {
  \$a = \$_.Attributes
  if ((\$a -band 0x400000) -or (\$a -band 0x40000) -or (\$a -band 0x1000)) {
    Write-Output \$_.FullName
  }
}
''';
    try {
      final proc = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', ps, dir],
      );
      if (proc.exitCode != 0) return {};
      final out = proc.stdout.toString();
      final nl = String.fromCharCode(10);
      return {
        for (final line in out.split(nl))
          if (line.trim().isNotEmpty) p.normalize(line.trim())
      };
    } catch (_) {
      return {};
    }
  }

  /// 待清理的缓存目录列表（系统临时目录 + 应用支持目录）
  static Future<List<String>> cacheDirPaths() async {
    final dirs = <String>[];
    try {
      dirs.add((await getTemporaryDirectory()).path);
    } catch (e) {
      debugPrint('getTemporaryDirectory 失败: $e');
    }
    try {
      dirs.add((await getApplicationSupportDirectory()).path);
    } catch (e) {
      debugPrint('getApplicationSupportDirectory 失败: $e');
    }
    return dirs;
  }

  /// 递归统计目录大小，跳过指定后缀的文件（数据库/配置）
  static Future<int> dirSizeExcluding(String dirPath, List<String> keepExtensions) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;

    int total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (keepExtensions.any((keep) => ext.endsWith(keep))) continue;
        try {
          total += await entity.length();
        } catch (_) {
          // 忽略无法读取的文件
        }
      }
    } catch (_) {
      // 忽略目录遍历错误
    }
    return total;
  }

  /// 删除目录下非保留后缀的文件，返回释放字节数/删除数/错误列表
  static Future<({int freedBytes, int removedFiles, List<String> errors})>
      clearDirExcluding(String dirPath, List<String> keepExtensions) async {
    int freedBytes = 0;
    int removedFiles = 0;
    final errors = <String>[];

    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      return (freedBytes: freedBytes, removedFiles: removedFiles, errors: errors);
    }
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (keepExtensions.any((keep) => ext.endsWith(keep))) continue;
        try {
          final size = await entity.length();
          await entity.delete();
          freedBytes += size;
          removedFiles++;
        } catch (e) {
          errors.add('${p.basename(entity.path)}: $e');
        }
      }
    } catch (e) {
      errors.add('$dirPath: $e');
    }
    return (freedBytes: freedBytes, removedFiles: removedFiles, errors: errors);
  }

  /// Hive 初始化目录（桌面端固定在应用支持目录下，避开 OneDrive 重定向的
  /// 文档目录——文档目录会被同步/锁竞争搞坏 .lock 文件）。
  /// 一次性迁移旧位置（文档目录）的 box 文件。
  static Future<String> hiveInitDir() async {
    final appDir = await getApplicationSupportDirectory();
    final hiveDir = Directory(p.join(appDir.path, 'hive'));
    if (!await hiveDir.exists()) {
      await hiveDir.create(recursive: true);
      // 迁移旧文档目录下的 box 文件（.lock 不迁移，会自动重建）
      try {
        final docs = await getApplicationDocumentsDirectory();
        for (final name in ['app_settings.hive', 'book_sources.hive']) {
          final src = File(p.join(docs.path, name));
          if (await src.exists()) {
            await src.copy(p.join(hiveDir.path, name));
            debugPrint('已迁移 Hive box: ${src.path}');
          }
        }
      } catch (e) {
        debugPrint('Hive box 迁移检查失败: $e');
      }
    }
    return hiveDir.path;
  }

  /// 旧 customDbPath 指向 .dart_tool（flutter clean 会清掉）时，把库文件
  /// 迁到稳定的应用支持目录并返回新目录；其余情况返回 null（保持原值）。
  static Future<String?> normalizeLegacyCustomDbPath(String customDbPath, {required String dbName}) async {
    if (!customDbPath.contains('.dart_tool')) return null;
    final appDir = await getApplicationSupportDirectory();
    final targetPath = p.join(appDir.path, dbName);
    final sourcePath = p.join(customDbPath, dbName);
    try {
      if (!File(targetPath).existsSync() && File(sourcePath).existsSync()) {
        await File(sourcePath).copy(targetPath);
        debugPrint('已迁移 customDb 数据库: $sourcePath -> $targetPath');
      }
    } catch (e) {
      debugPrint('customDb 迁移失败: $e');
    }
    return appDir.path;
  }

  /// Windows/Linux 桌面端返回稳定的数据库目录（应用支持目录），并一次性
  /// 迁移旧版散落在启动目录 .dart_tool 下的库文件；macOS 返回 null
  /// （走 sqflite 原生 getDatabasesPath，位置本身稳定）。
  ///
  /// 背景：sqflite_ffi 的默认 getDatabasesPath() 是
  /// 「当前工作目录/.dart_tool/sqflite_common_ffi/databases」——从不同
  /// 目录启动会开到不同的库（表现为书时有时无）。
  static Future<String?> stableDatabaseDir({required String dbName}) async {
    if (!Platform.isWindows && !Platform.isLinux) return null;

    final appDir = await getApplicationSupportDirectory();
    final targetPath = p.join(appDir.path, dbName);
    debugPrint('数据库稳定目录: ${appDir.path} (目标文件存在: ${File(targetPath).existsSync()})');
    if (File(targetPath).existsSync()) return appDir.path;

    // 旧位置 1：当前工作目录的 .dart_tool（App/Flutter 工具链共用形态）
    final legacy1 = File(p.join(Directory.current.path,
        '.dart_tool', 'sqflite_common_ffi', 'databases', dbName));
    // 旧位置 2：可执行文件同目录（便携部署早期形态）
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final legacy2 = File(p.join(exeDir, dbName));

    for (final legacy in [legacy1, legacy2]) {
      try {
        if (await legacy.exists() && await legacy.length() > 0) {
          await legacy.copy(targetPath);
          debugPrint('已迁移数据库: ${legacy.path} -> $targetPath');
          break;
        }
      } catch (e) {
        debugPrint('数据库迁移检查失败(${legacy.path}): $e');
      }
    }
    return appDir.path;
  }

  /// 路径显示用：转换为当前平台原生分隔符（Windows 反斜杠；存储统一正斜杠）
  static const String _winSep = r'';

  static String nativeSeparators(String path) =>
      Platform.isWindows ? path.replaceAll('/', _winSep) : path;

  /// 程序所在目录（作为相对路径的默认基准：便携部署时程序与书库同级）
  static String programDir() => Directory.current.path;

  /// 解析用户配置的路径：相对路径以程序目录为基准拼接，绝对路径原样返回
  static String resolvePath(String path) {
    if (path.isEmpty) return path;
    // 绝对路径（含盘符 / 斜杠开头）直接返回
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path) ||
        path.startsWith('/') ||
        path.startsWith(r'\')) {
      return path;
    }
    return p.join(Directory.current.path, path);
  }

  /// 书库根目录的生效值：显式配置优先，否则用程序目录（便携/跨系统默认基准）
  static String effectiveLibraryRoot(String configuredRoot) =>
      configuredRoot.isNotEmpty ? configuredRoot : programDir();

  /// 默认备份目录（文档目录/novelmgt_flutter/backups）
  static Future<String> defaultBackupDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, 'novelmgt_flutter', 'backups');
  }
}
