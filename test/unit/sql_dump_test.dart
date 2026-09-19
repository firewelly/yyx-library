import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:novelmgt_flutter/services/database_service.dart';
import 'package:novelmgt_flutter/services/crawler_service.dart';
import 'package:novelmgt_flutter/models/models.dart';

/// 建立与 app schema 一致的内存库（injectedDb 跳过 onCreate）。
///
/// [singleInstance] 为 false 时每次打开得到独立的内存库
/// （sqflite_ffi 默认把 :memory: 当单例，多库场景必须关掉）。
final _openDbs = <DatabaseService>[];

Future<DatabaseService> _createTestDb({bool singleInstance = true}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: singleInstance));
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
  await db.execute('''
    CREATE TABLE reading_progress (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL UNIQUE, chapterId INTEGER NOT NULL,
      scrollPosition INTEGER DEFAULT 0, lastReadAt TEXT, createdAt TEXT NOT NULL,
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
      FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE bookmarks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL, chapterId INTEGER NOT NULL,
      position INTEGER DEFAULT 0, title TEXT, note TEXT, createdAt TEXT NOT NULL,
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
      FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      bookId INTEGER NOT NULL, chapterId INTEGER NOT NULL,
      position INTEGER DEFAULT 0, content TEXT NOT NULL,
      createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
      FOREIGN KEY (bookId) REFERENCES books(id) ON DELETE CASCADE,
      FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
    )
  ''');
  await db.execute('CREATE INDEX idx_chapters_bookId ON chapters(bookId)');
  final svc = DatabaseService(injectedDb: db);
  _openDbs.add(svc);
  return svc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // :memory: 默认单例，不关闭会跨测试泄漏表结构
  tearDown(() async {
    for (final d in _openDbs) {
      try {
        await d.close();
      } catch (_) {}
    }
    _openDbs.clear();
  });

  test('T-010: SQL dump 备份→清空→恢复，数据完整往返', () async {
    // 1. 源库写入多样化数据
    final src = await _createTestDb();
    await src.initialize();
    final now = DateTime.now().toIso8601String();
    final book = await src.createBook(Book(
      title: '备份' '测试书', // 含单引号场景在书名里更极端，这里测普通中文
      author: '作者',
      status: '已完结',
      wordCount: 100,
      rating: 5,
      createdAt: now,
      updatedAt: now,
      tags: const [Tag(name: '测试')],
    )); 
    for (var i = 1; i <= 3; i++) {
      await src.createChapter(Chapter(
        bookId: book.id!,
        chapterNumber: i,
        title: '第$i章',
        content: '内容$i，含特殊字符: 引号\' 反斜杠\\ 换行\n结束。',
        createdAt: now,
        updatedAt: now,
      ));
    }
    final statsBefore = await src.getStats();

    // 2. 导出 dump
    final sql = await src.exportSqlDump();
    expect(sql, contains('BEGIN TRANSACTION;'));
    expect(sql, contains('INSERT INTO books'));
    expect(sql, contains('INSERT INTO chapters'));

    // 3. 目标库（全新空库）恢复
    final dst = await _createTestDb(singleInstance: false);
    await dst.initialize();
    await dst.restoreFromSqlDump(sql);

    // 4. 校验往返一致
    final statsAfter = await dst.getStats();
    expect(statsAfter.totalBooks, statsBefore.totalBooks);
    expect(statsAfter.totalChapters, statsBefore.totalChapters);
    expect(statsAfter.totalWords, statsBefore.totalWords);

    final restored = await dst.findBookByTitleAndAuthor('备份测试书', author: '作者');
    expect(restored, isNotNull, reason: '书应恢复');
    expect(restored!.rating, 5);
    final chapters = await dst.getChapters(restored.id!);
    expect(chapters.length, 3);
    expect(chapters[0].content, contains('引号\' 反斜杠\\ 换行'));
    // 标签也应恢复
    final tags = await dst.getBook(restored.id!);
    expect(tags!.tags.map((t) => t.name), contains('测试'));

    // 5. 恢复后再导入一次（幂等性：清空重建不报错、不重复）
    await dst.restoreFromSqlDump(sql);
    final statsAgain = await dst.getStats();
    expect(statsAgain.totalBooks, 1, reason: '重复恢复不应产生重复数据');
    expect(statsAgain.totalChapters, 3);
  });

  test('SQL dump 恢复会清空目标库原有数据', () async {
    final src = await _createTestDb();
    await src.initialize();
    final now = DateTime.now().toIso8601String();
    await src.createBook(Book(title: '源库书', createdAt: now, updatedAt: now));
    final sql = await src.exportSqlDump();

    // 目标库（独立内存库）预置一条会被清掉的数据
    final dst = await _createTestDb(singleInstance: false);
    await dst.initialize();
    await dst.createBook(Book(title: '目标库旧书', createdAt: now, updatedAt: now));

    await dst.restoreFromSqlDump(sql);
    final books = await dst.listBooks(page: 1, perPage: 10);
    expect(books.length, 1);
    expect(books.first.title, '源库书', reason: '旧数据应被清空，只留 dump 内容');
  });

  test('CrawlImporter 新书入库无死锁（事务走 executor）', () async {
    final db = await _createTestDb();
    await db.initialize();
    final importer = CrawlImporter(db);

    final result = await importer.importChapters(
      title: '爬虫测试书',
      author: '网络作者',
      bookUrl: 'https://example.com/book/1',
      sourceName: '测试源',
      chapters: [
        for (var i = 1; i <= 3; i++)
          CrawledChapterWithContent(
            title: '第$i章',
            url: 'https://example.com/book/1/$i',
            chapterNumber: i,
            content: '第$i章正文内容。',
          ),
      ],
    );

    expect(result.isNewBook, isTrue);
    expect(result.chapterCount, 3);
    final book = await db.getBook(result.bookId);
    expect(book, isNotNull);
    expect(book!.sourceFormat, 'web');
    expect(book.wordCount, greaterThan(0), reason: '字数应在入库后统计');
    final chapters = await db.getChapters(result.bookId);
    expect(chapters.length, 3);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('CrawlImporter 追更路径：已有书新增章节不重复', () async {
    final db = await _createTestDb();
    await db.initialize();
    final importer = CrawlImporter(db);

    // 首次入库 2 章
    await importer.importChapters(
      title: '追更书',
      author: null,
      bookUrl: 'https://example.com/b/2',
      sourceName: '测试源',
      chapters: [
        for (var i = 1; i <= 2; i++)
          CrawledChapterWithContent(
              title: '第$i章', url: 'https://example.com/b/2/$i', chapterNumber: i, content: '内容$i'),
      ],
    );

    // 追更：全书 3 章（含已有 2 章 + 新 1 章）
    final result = await importer.importChapters(
      title: '追更书',
      author: null,
      bookUrl: 'https://example.com/b/2',
      sourceName: '测试源',
      chapters: [
        for (var i = 1; i <= 3; i++)
          CrawledChapterWithContent(
              title: '第$i章', url: 'https://example.com/b/2/$i', chapterNumber: i, content: '内容$i'),
      ],
    );

    expect(result.isNewBook, isFalse);
    expect(result.addedCount, 1, reason: '只应新增第 3 章');
    final books = await db.listBooks(page: 1, perPage: 10);
    expect(books.length, 1, reason: '不重复建书');
    final chapters = await db.getChapters(books.first.id!);
    expect(chapters.length, 3);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
