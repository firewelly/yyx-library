// ignore_for_file: avoid_print
/// 扫描本地小说目录（novels / H），批量导入 Flutter 使用的 SQLite 数据库。
///
/// 特性：
/// - 自动跳过 OneDrive 占位文件（未物化，`du -ak` 占用为 0，绝不触发云端下载）
/// - 按书名（文件名去扩展名）去重，已存在的书自动跳过（支持断点续传）
/// - 可给指定目录的书打标签（如 H 目录打「成人」），便于在 App 中筛选
/// - 支持 dry-run 预检与 --limit 小批量试运行
///
/// 注意：本脚本为命令行工具，不能 import 依赖 Flutter SDK 的 database_service.dart，
/// 因此内嵌了与 lib/services/database_service.dart 保持同步的建表/迁移 SQL。
///
/// 用法（在 novelmgt_flutter/ 目录下执行，每 20 本输出一次进度百分比）：
///   dart run tool/scan_import_novels.dart \
///     --dir ../novels --dir ../H \
///     --tag-dir ../H=成人 \
///     --db ../.dart_tool/sqflite_common_ffi/databases/novelmgt.db
///
/// 常用参数：
///   --dir <path>       要扫描的目录，可多次（默认 ../novels 与 ../H）
///   --tag-dir <d>=<t>  为目录 d 下的书打标签 t，可多次
///   --db <path>        数据库文件路径（默认相对 cwd 的 novelmgt.db）
///   --dry-run          只统计不写库（预检占位/去重情况）
///   --limit <n>        最多处理 n 本（调试，先小批量试跑）
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:novelmgt_flutter/services/chapter_parser.dart';
import 'package:novelmgt_flutter/utils/book_path.dart';
import 'package:novelmgt_flutter/utils/text_decode.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ============================================================
// 文本解码（纯 Dart + 系统 iconv，不依赖 charset_converter/Flutter）
// 与 lib/utils/text_decode.dart 行为对齐：UTF-8 → GB18030 → Big5
// ============================================================


/// 自动解码字节为字符串：复用 lib/utils/text_decode.dart 的纯 Dart 解码链
/// （UTF-8 → GBK/GB18030 → Big5，含假名/私用区误码校验），桌面/CLI 行为一致。
Future<String> decodeBytes(Uint8List bytes) => TextDecode.decode(bytes);

// ============================================================
// 数据库 Schema（与 lib/services/database_service.dart 同步，v4）
// ============================================================

const int _dbVersion = 5;

Future<void> _onCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE books (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      author TEXT,
      summary TEXT,
      status TEXT DEFAULT '连载中',
      sourceUrl TEXT,
      sourceFormat TEXT,
      filePath TEXT,
      coverImage TEXT,
      coverImagePath TEXT,
      rating INTEGER DEFAULT 0,
      notes TEXT,
      wordCount INTEGER DEFAULT 0,
      lastReadAt TEXT,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE chapters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL,
      chapterNumber INTEGER NOT NULL,
      originalOrder INTEGER,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      sourceUrl TEXT,
      sourceFormat TEXT,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      color TEXT DEFAULT '#1976D2'
    )
  ''');
  await db.execute('''
    CREATE TABLE book_tags (
      bookId INTEGER NOT NULL,
      tagId INTEGER NOT NULL,
      PRIMARY KEY (bookId, tagId),
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
      FOREIGN KEY (tagId) REFERENCES tags(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE reading_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL UNIQUE,
      chapterId INTEGER NOT NULL,
      scrollPosition INTEGER DEFAULT 0,
      lastReadAt TEXT,
      createdAt TEXT NOT NULL,
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
      FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE bookmarks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL,
      chapterId INTEGER NOT NULL,
      position INTEGER DEFAULT 0,
      title TEXT,
      note TEXT,
      createdAt TEXT NOT NULL,
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
      FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL,
      chapterId INTEGER NOT NULL,
      position INTEGER DEFAULT 0,
      content TEXT NOT NULL,
      createdAt TEXT NOT NULL,
      updatedAt TEXT NOT NULL,
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
      FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('CREATE INDEX idx_books_title ON books(title)');
  await db.execute('CREATE INDEX idx_books_status ON books(status)');
  await db.execute('CREATE INDEX idx_chapters_bookId ON chapters(bookId)');
  await db.execute('CREATE INDEX idx_reading_progress_book ON reading_progress(bookId)');
  await db.execute('CREATE INDEX idx_bookmarks_book ON bookmarks(bookId)');
  await db.execute('CREATE INDEX idx_notes_book ON notes(bookId)');
  await db.execute('CREATE INDEX idx_notes_chapter ON notes(chapterId)');
}

Future<void> _addColumnIfMissing(Database db, String table, String column, String type) async {
  final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
  final hasColumn = tableInfo.any((col) => col['name'] == column);
  if (!hasColumn) {
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }
}

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('DROP TABLE IF EXISTS notes');
    await db.execute('DROP TABLE IF EXISTS bookmarks');
    await db.execute('DROP TABLE IF EXISTS reading_progress');
    await db.execute('DROP TABLE IF EXISTS book_tags');
    await db.execute('DROP TABLE IF EXISTS tags');
    await db.execute('DROP TABLE IF EXISTS chapters');
    await db.execute('DROP TABLE IF EXISTS books');
    await _onCreate(db, newVersion);
  }
  if (oldVersion < 3) {
    final tableInfo = await db.rawQuery('PRAGMA table_info(chapters)');
    final hasUpdatedAt = tableInfo.any((col) => col['name'] == 'updatedAt');
    if (!hasUpdatedAt) {
      await db.execute('ALTER TABLE chapters ADD COLUMN updatedAt TEXT');
    }
    await db.execute("UPDATE chapters SET updatedAt = createdAt WHERE updatedAt IS NULL OR updatedAt = ''");
  }
  if (oldVersion < 4) {
    await _addColumnIfMissing(db, 'books', 'sourceFormat', 'TEXT');
    await _addColumnIfMissing(db, 'chapters', 'sourceFormat', 'TEXT');
  }
  if (oldVersion < 5) {
    final tableInfo = await db.rawQuery('PRAGMA table_info(books)');
    final hasFilePath = tableInfo.any((col) => col['name'] == 'filePath');
    if (!hasFilePath) {
      await db.execute('ALTER TABLE books ADD COLUMN filePath TEXT');
    }
  }
}

// ============================================================
// 命令行参数
// ============================================================

class Options {
  final List<String> dirs;
  final Map<String, String> tagByDir; // 目录绝对路径 -> 标签名
  final String dbPath;
  final bool dryRun;
  final int? limit;

  Options({
    required this.dirs,
    required this.tagByDir,
    required this.dbPath,
    required this.dryRun,
    this.limit,
  });
}

/// App 稳定数据库路径（与 lib/services/platform_fs_io.dart 的 stableDatabaseDir 对齐）。
/// Windows 用应用支持目录；其余平台沿用旧默认。
String defaultDbPath() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'] ?? '';
    if (appData.isNotEmpty) {
      return p.join(appData, 'com.example', 'novelmgt_flutter', 'novelmgt.db');
    }
  }
  return p.join('.dart_tool', 'sqflite_common_ffi', 'databases', 'novelmgt.db');
}

Options parseArgs(List<String> args) {
  final dirs = <String>[];
  final tagByDir = <String, String>{};
  // 默认库路径与 App 的稳定位置一致
  var dbPath = defaultDbPath();
  var dryRun = false;
  int? limit;

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String value(String flag) {
      if (i + 1 >= args.length) throw ArgumentError('$flag 缺少参数值');
      return args[++i];
    }

    switch (a) {
      case '--dir':
        dirs.add(value(a));
      case '--tag-dir':
        final raw = value(a);
        final eq = raw.indexOf('=');
        if (eq <= 0) throw ArgumentError('--tag-dir 格式应为 <目录>=<标签>，收到: $raw');
        tagByDir[p.normalize(raw.substring(0, eq))] = raw.substring(eq + 1);
      case '--db':
        dbPath = value(a);
      case '--limit':
        limit = int.tryParse(value(a));
      case '--dry-run':
        dryRun = true;
      default:
        throw ArgumentError('未知参数: $a');
    }
  }

  final resolvedDirs = dirs.isEmpty ? ['../novels', '../H'] : dirs;
  return Options(
    dirs: resolvedDirs.map((d) => p.normalize(d)).toList(),
    tagByDir: tagByDir,
    dbPath: p.normalize(dbPath),
    dryRun: dryRun,
    limit: limit,
  );
}

// ============================================================
// 占位文件检测（OneDrive 未物化）
// ============================================================

/// 使用 `du -ak` 一次性扫描目录树，返回「实际占用为 0 KB」的文件绝对/相对路径集合。
/// OneDrive 占位文件物理块为 0，du 报告 0，且此操作只读元数据、不会触发云端下载。
Future<Set<String>> findPlaceholders(String dirPath) async {
  final proc = await Process.run('du', ['-ak', dirPath]);
  if (proc.exitCode != 0) {
    // Windows 无 du：改用 PowerShell 按文件属性检测 OneDrive 按需占位文件
    // （RecallOnDataAccess 0x400000 / RecallOnOpen 0x40000 / Offline 0x1000），
    // 一次调用批量枚举，同样只读元数据不触发下载。
    if (Platform.isWindows) {
      return findPlaceholdersWindows(dirPath);
    }
    stderr.writeln('警告: du 执行失败 (exit ${proc.exitCode})，将不跳过任何文件');
    return {};
  }
  final set = <String>{};
  final stdoutText = proc.stdout.toString();
  for (final line in stdoutText.split('\n')) {
    final tab = line.indexOf('\t');
    if (tab < 0) continue;
    final kb = int.tryParse(line.substring(0, tab));
    if (kb != null && kb == 0) {
      set.add(p.normalize(line.substring(tab + 1)));
    }
  }
  return set;
}

/// Windows: 通过 PowerShell 批量枚举 OneDrive 按需占位文件（只读属性，不触发下载）。
Future<Set<String>> findPlaceholdersWindows(String dirPath) async {
  // 注意：Dart r''' 原始字符串内的 $ 会被原样传递给 PowerShell（PS 变量符号）
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
      ['-NoProfile', '-Command', ps, dirPath],
      stdoutEncoding: utf8,
    );
    if (proc.exitCode != 0) {
      stderr.writeln('警告: PowerShell 占位检测失败 (exit ${proc.exitCode})');
      return {};
    }
    final nl = String.fromCharCode(10);
    return {
      for (final line in (proc.stdout as String).split(nl))
        if (line.trim().isNotEmpty) p.normalize(line.trim())
    };
  } catch (e) {
    stderr.writeln('警告: PowerShell 不可用，占位检测回退为空: $e');
    return {};
  }
}


// ============================================================
// 文件收集
// ============================================================

final RegExp _conflictCopyRe = RegExp(r'\(\d{4}-\d{2}-\d{2}');

List<File> collectTxtFiles(String dir, Set<String> placeholders) {
  final files = <File>[];
  final stack = <Directory>[Directory(dir)];
  while (stack.isNotEmpty) {
    final d = stack.removeLast();
    if (!d.existsSync()) continue;
    for (final e in d.listSync()) {
      if (e is Directory) {
        stack.add(e);
      } else if (e is File) {
        final path = e.path;
        final lower = path.toLowerCase();
        if (!lower.endsWith('.txt')) continue;
        if (lower.endsWith('.bak') || lower.endsWith('.crdownload')) continue;
        if (_conflictCopyRe.hasMatch(path)) continue; // Finder 冲突副本
        if (placeholders.contains(p.normalize(path))) continue; // 占位文件跳过
        files.add(e);
      }
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

// ============================================================
// 主逻辑
// ============================================================

enum BookStatus { imported, skipped, failed }

class BookOutcome {
  final String title;
  final BookStatus status;
  final int chapters;
  final String? error;

  BookOutcome(this.title, this.status, this.chapters, [this.error]);
}

Future<BookOutcome> importOneBook(
  Database db,
  File file,
  String tag, {
  required bool skipExisting,
}) async {
  final title = p.basenameWithoutExtension(file.path).trim();
  if (title.isEmpty) {
    return BookOutcome(p.basename(file.path), BookStatus.failed, 0, '文件名为空');
  }

  if (skipExisting) {
    final rows = await db.query('books', columns: ['id'], where: 'title = ?', whereArgs: [title], limit: 1);
    if (rows.isNotEmpty) {
      return BookOutcome(title, BookStatus.skipped, 0);
    }
  }

  try {
    final bytes = await file.readAsBytes();
    final content = await decodeBytes(bytes);
    if (content.trim().isEmpty) {
      return BookOutcome(title, BookStatus.failed, 0, '内容为空');
    }

    final chapters = ChapterParser.parseChapters(content, bookTitle: title);
    if (chapters.isEmpty) {
      return BookOutcome(title, BookStatus.failed, 0, '未解析出章节');
    }

    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      final bookId = await txn.insert('books', {
        'title': title,
        'status': '连载中',
        'sourceUrl': file.path,
        'sourceFormat': 'txt',
        // 与 App 一致：存相对程序目录的路径（跨系统共享库）
        'filePath': BookPath.relativize(file.path, Directory.current.path),
        'wordCount': content.length,
        'createdAt': now,
        'updatedAt': now,
      });

      for (final ch in chapters) {
        await txn.insert('chapters', {
          'bookId': bookId,
          'chapterNumber': ch.chapterNumber,
          'originalOrder': ch.originalOrder,
          'title': ch.title,
          'content': ch.content,
          'sourceUrl': file.path,
          'sourceFormat': 'txt',
          'createdAt': now,
          'updatedAt': now,
        });
      }

      if (tag.isNotEmpty) {
        final existing = await txn.query('tags', where: 'name = ?', whereArgs: [tag], limit: 1);
        int tagId;
        if (existing.isNotEmpty) {
          tagId = existing.first['id'] as int;
        } else {
          tagId = await txn.insert('tags', {'name': tag, 'color': '#E91E63'});
        }
        await txn.insert('book_tags', {'bookId': bookId, 'tagId': tagId});
      }
    });

    return BookOutcome(title, BookStatus.imported, chapters.length);
  } catch (e) {
    return BookOutcome(title, BookStatus.failed, 0, e.toString());
  }
}

Future<void> main(List<String> args) async {
  final opts = parseArgs(args);

  // 解析目录 -> 标签映射（用绝对路径归一化）
  final tagForDir = <String, String>{};
  for (final entry in opts.tagByDir.entries) {
    tagForDir[p.normalize(p.absolute(entry.key))] = entry.value;
  }

  print('===== 小说扫描导入 =====');
  print('数据库: ${opts.dbPath} (绝对路径: ${p.absolute(opts.dbPath)})');
  print('扫描目录: ${opts.dirs.join(', ')}');
  print('标签映射: ${tagForDir.isEmpty ? '无' : tagForDir}');
  if (opts.dryRun) print('模式: dry-run（仅统计，不写库）');
  if (opts.limit != null) print('限制处理: ${opts.limit} 本');
  print('');

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 使用绝对路径打开，避免 sqflite_common_ffi 拼接到默认数据库目录
  final dbAbsPath = p.absolute(opts.dbPath);
  final dbDir = p.dirname(dbAbsPath);
  Directory(dbDir).createSync(recursive: true);

  final db = await databaseFactory.openDatabase(
    dbAbsPath,
    options: OpenDatabaseOptions(
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // App 可能同时打开同一库：忙等重试，避免立即 SQLITE_BUSY
        await db.execute('PRAGMA busy_timeout=8000');
      },
    ),
  );
  // 导入期性能优化（App 正占用时切 WAL 可能失败，忽略即可）
  try {
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('PRAGMA synchronous=OFF');
  } catch (_) {}

  try {
    // 已有书名集合（去重）
    final existingTitles = <String>{};
    for (final row in await db.query('books', columns: ['title'])) {
      existingTitles.add(row['title'] as String);
    }
    print('数据库中已有书籍: ${existingTitles.length} 本');
    print('');

    int totalFiles = 0;
    int placeholderTotal = 0;
    final outcomes = <BookOutcome>[];
    final failed = <String>[];

    for (final dir in opts.dirs) {
      final absDir = p.absolute(dir);
      print('--- 扫描目录: $dir (绝对: $absDir) ---');

      final placeholders = await findPlaceholders(absDir);
      placeholderTotal += placeholders.length;
      print('未物化(占位)文件: ${placeholders.length} 个（跳过，不触发下载）');

      final files = collectTxtFiles(absDir, placeholders);
      totalFiles += files.length;
      print('可导入 TXT: ${files.length} 本');

      if (opts.dryRun) {
        // dry-run: 统计将导入/将跳过的数量
        int wouldImport = 0, wouldSkip = 0;
        for (final f in files) {
          final title = p.basenameWithoutExtension(f.path).trim();
          if (existingTitles.contains(title)) {
            wouldSkip++;
          } else {
            wouldImport++;
          }
        }
        print('dry-run: 将新增 $wouldImport 本，已存在跳过 $wouldSkip 本');
        print('');
        continue;
      }

      final tag = tagForDir[p.normalize(absDir)] ?? '';

      final processed = opts.limit != null ? files.take(opts.limit!).toList() : files;
      final totalToProcess = processed.length;
      var i = 0;
      for (final file in processed) {
        i++;
        final outcome = await importOneBook(db, file, tag, skipExisting: true);
        outcomes.add(outcome);
        if (outcome.status == BookStatus.imported) {
          existingTitles.add(outcome.title);
        }
        if (outcome.status == BookStatus.failed) {
          failed.add('${file.path}: ${outcome.error}');
        }
        if (i % 20 == 0 || i == totalToProcess) {
          final imp = outcomes.where((o) => o.status == BookStatus.imported).length;
          final skp = outcomes.where((o) => o.status == BookStatus.skipped).length;
          final fl = outcomes.where((o) => o.status == BookStatus.failed).length;
          final percent = totalToProcess > 0
              ? (i / totalToProcess * 100).toStringAsFixed(1)
              : '0.0';
          print('[$dir] 进度 $i/$totalToProcess ($percent%) | 已导入 $imp 跳过 $skp 失败 $fl | 当前: ${p.basename(file.path)}');
        }
      }
      print('');
    }

    // 汇总
    if (!opts.dryRun) {
      final imp = outcomes.where((o) => o.status == BookStatus.imported).length;
      final skp = outcomes.where((o) => o.status == BookStatus.skipped).length;
      final fl = outcomes.where((o) => o.status == BookStatus.failed).length;
      print('===== 结果汇总 =====');
      print('扫描文件总数: $totalFiles');
      print('占位文件跳过: $placeholderTotal');
      print('本次导入成功: $imp 本');
      print('已存在跳过: $skp 本');
      print('导入失败: $fl 本');

      if (failed.isNotEmpty) {
        print('');
        print('--- 失败明细（前 50 条）---');
        failed.take(50).forEach((e) => print(e));
        if (failed.length > 50) print('... 共 ${failed.length} 条失败');
      }

      final totals = await db.rawQuery('SELECT COUNT(*) as c FROM books');
      final chapterTotals = await db.rawQuery('SELECT COUNT(*) as c FROM chapters');
      print('');
      print('数据库现状: books=${totals.first['c']} chapters=${chapterTotals.first['c']}');
    }
  } finally {
    await db.close();
  }
}
