import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:novelmgt_flutter/services/database_service.dart';
import 'package:novelmgt_flutter/services/platform_fs.dart';
import 'package:novelmgt_flutter/models/models.dart';

/// 跨系统路径迁移场景（真实布局：程序与 novels/、H/ 同级）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final openDbs = <DatabaseService>[];

  tearDown(() async {
    for (final d in openDbs) {
      try {
        await d.close();
      } catch (_) {}
    }
    openDbs.clear();
  });

  Future<DatabaseService> createDb() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL, author TEXT, summary TEXT,
        status TEXT DEFAULT '连载中',
        sourceUrl TEXT, sourceFormat TEXT, filePath TEXT,
        coverImage TEXT, coverImagePath TEXT,
        rating INTEGER DEFAULT 0, notes TEXT, wordCount INTEGER DEFAULT 0,
        lastReadAt TEXT, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bookId INTEGER NOT NULL, chapterNumber INTEGER NOT NULL,
        originalOrder INTEGER, title TEXT NOT NULL, content TEXT NOT NULL,
        sourceUrl TEXT, sourceFormat TEXT, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE, color TEXT DEFAULT '#1976D2'
      )
    ''');
    await db.execute('''
      CREATE TABLE book_tags (
        bookId INTEGER NOT NULL, tagId INTEGER NOT NULL,
        PRIMARY KEY (bookId, tagId),
        FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
        FOREIGN KEY (tagId) REFERENCES tags(id) ON DELETE CASCADE
      )
    ''');
    final svc = DatabaseService(injectedDb: db);
    openDbs.add(svc);
    return svc;
  }

  test('迁移：macOS 绝对路径 + legacyRoots 转为相对（真实场景）', () async {
    final db = await createDb();
    await db.initialize();
    final now = DateTime.now().toIso8601String();
    const macRoot = '/Users/demo/OneDrive/bioinfo/Novel_scraber';
    await db.createBook(Book(
        title: '斗破苍穹', createdAt: now, updatedAt: now,
        filePath: '$macRoot/novels/斗破苍穹.txt'));
    await db.createBook(Book(
        title: '某书', createdAt: now, updatedAt: now,
        filePath: '$macRoot/H/某书.txt'));
    // 一本不在任何根下的书（保持不变）
    await db.createBook(Book(
        title: '外部书', createdAt: now, updatedAt: now,
        filePath: '/tmp/external/外部书.txt'));

    final count = await db.relativizeBookPaths('D:/OneDrive/bioinfo/Novel_scraber',
        legacyRoots: const [macRoot]);
    expect(count, 2, reason: 'novels 与 H 下的两本应被转换');

    final all = await db.listBooks(page: 1, perPage: 10);
    final byTitle = {for (final b in all) b.title: b.filePath};
    expect(byTitle['斗破苍穹'], 'novels/斗破苍穹.txt');
    expect(byTitle['某书'], 'H/某书.txt');
    expect(byTitle['外部书'], '/tmp/external/外部书.txt', reason: '目录外路径不变');
  });

  test('分析：从 macOS 路径推断旧库根建议', () async {
    final db = await createDb();
    await db.initialize();
    final now = DateTime.now().toIso8601String();
    const macRoot = '/Users/demo/OneDrive/bioinfo/Novel_scraber';
    await db.createBook(Book(
        title: 'a', createdAt: now, updatedAt: now, filePath: '$macRoot/novels/a.txt'));
    await db.createBook(Book(
        title: 'b', createdAt: now, updatedAt: now, filePath: '$macRoot/H/b.txt'));
    await db.createBook(Book(
        title: 'c', createdAt: now, updatedAt: now, filePath: 'novels/c.txt'));

    final analysis = await db.analyzeBookPaths();
    expect(analysis.absoluteCount, 2);
    expect(analysis.relativeCount, 1);
    // 公共前缀应落在 Novel_scraber/novels 与 H 的共同父级（即项目根）
    expect(
      analysis.suggestedRoots.any((r) => r == macRoot || r.startsWith(macRoot)),
      isTrue,
      reason: '建议列表应包含可覆盖全部绝对路径的旧根，实际: ${analysis.suggestedRoots}',
    );
  });

  test('PlatformFs（桌面 io）：相对路径以程序目录解析', () async {
    expect(PlatformFs.resolvePath('novels'), isNot(equals('novels')));
    expect(PlatformFs.resolvePath('novels'),
        contains('novels'));
    // 绝对路径原样
    expect(PlatformFs.resolvePath('/abs/path'), '/abs/path');
    if (Directory.current.path.contains(r':')) {
      // Windows：盘符形式
      expect(PlatformFs.resolvePath(r'D:\lib'), r'D:\lib');
    }
    // 未配置时以程序目录为生效基准
    expect(PlatformFs.effectiveLibraryRoot(''),
        Directory.current.path);
    expect(PlatformFs.effectiveLibraryRoot('/x'), '/x');
  });
}
