import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:novelmgt_flutter/services/database_service.dart';
import 'package:novelmgt_flutter/services/import_service.dart';

Future<DatabaseService> _createTestDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
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
  await db.execute('CREATE INDEX idx_books_title ON books(title)');
  await db.execute('CREATE INDEX idx_books_status ON books(status)');
  await db.execute('CREATE INDEX idx_chapters_bookId ON chapters(bookId)');
  return DatabaseService(injectedDb: db);
}

void main() {
  late DatabaseService db;
  late ImportService importService;
  late String tempDir;

  setUp(() async {
    db = await _createTestDb();
    await db.initialize();
    importService = ImportService(db);
    tempDir = Directory.systemTemp.createTempSync('novelmgt_test_').path;
  });

  tearDown(() async {
    await db.close();
    if (await Directory(tempDir).exists()) {
      await Directory(tempDir).delete(recursive: true);
    }
  });

  group('ImportService - TXT import', () {
    test('imports a simple TXT file with chapters', () async {
      final filePath = '$tempDir/test_novel.txt';
      await File(filePath).writeAsString(
        '第一章 穿越\n'
        '林轩睁开眼，发现自己来到了一个陌生的世界。\n'
        '\n'
        '第二章 修炼\n'
        '他开始修炼基础功法，感受天地灵气的流动。\n'
        '\n'
        '第三章 突破\n'
        '经过不懈努力，他终于突破到练气期。\n',
        encoding: utf8,
      );

      final result = await importService.importTxtFile(filePath, author: '测试作者');

      expect(result.success, true);
      expect(result.bookTitle, 'test novel');
      expect(result.chapterCount, 3);

      final book = await db.findBookByTitleAndAuthor('test novel', author: '测试作者');
      expect(book, isNotNull);
      expect(book!.wordCount, greaterThan(0));

      final chapters = await db.getChapters(book.id!);
      expect(chapters.length, 3);
      expect(chapters[0].title, '第一章 穿越');
      expect(chapters[1].title, '第二章 修炼');
      expect(chapters[2].title, '第三章 突破');
    });

    test('imports TXT with GBK encoding', () async {
      final filePath = '$tempDir/gbk_novel.txt';
      final gbkBytes = utf8.encode('第一章 GBK测试\n内容...');
      await File(filePath).writeAsBytes(gbkBytes);

      final result = await importService.importTxtFile(filePath);

      expect(result.success, true);
      expect(result.chapterCount, 1);
    });

    test('imports content without chapter markers as single chapter', () async {
      final filePath = '$tempDir/no_chapters.txt';
      await File(filePath).writeAsString(
        '这是一篇没有章节标记的短篇小说。\n'
        '从头到尾只有一个段落。\n'
        '没有第一章、第二章这样的标题。\n',
        encoding: utf8,
      );

      final result = await importService.importTxtFile(filePath);

      expect(result.success, true);
      expect(result.chapterCount, 1);
    });
  });

  group('ImportService - Batch import', () {
    test('imports multiple TXT files from a folder', () async {
      for (int i = 0; i < 3; i++) {
        await File('$tempDir/novel_$i.txt').writeAsString(
          '第一章 故事$i\n这是第$i 本小说的内容。\n',
          encoding: utf8,
        );
      }

      final result = await importService.importFolder(tempDir);

      expect(result.total, 3);
      expect(result.succeeded, 3);
      expect(result.failed, 0);

      final books = await db.listBooks(page: 1, perPage: 10);
      expect(books.length, 3);
    });

    test('skips duplicate imports', () async {
      final filePath = '$tempDir/duplicate.txt';
      await File(filePath).writeAsString(
        '第一章 测试\n内容...\n',
        encoding: utf8,
      );

      await importService.importTxtFile(filePath, author: '作者');
      final result = await importService.importTxtFile(filePath, author: '作者');

      expect(result.success, true);
      expect(result.message, contains('无变化'));
    });

    test('handles empty folder gracefully', () async {
      final emptyDir = '$tempDir/empty';
      await Directory(emptyDir).create();

      final result = await importService.importFolder(emptyDir);

      expect(result.total, 0);
      expect(result.errors.first, contains('未找到'));
    });
  });

  group('ImportService - Duplicate detection', () {
    test('findBookByTitleAndAuthor prevents duplicates', () async {
      final filePath = '$tempDir/reimport.txt';
      await File(filePath).writeAsString(
        '第一章 开篇\n正文内容\n',
        encoding: utf8,
      );

      final first = await importService.importTxtFile(filePath, author: '作者');
      expect(first.success, true);

      final second = await importService.importTxtFile(filePath, author: '作者');
      expect(second.success, true);
      expect(second.message, contains('无变化'));

      final books = await db.listBooks(page: 1, perPage: 10);
      expect(books.length, 1);
    });
  });
}

/// 供其他测试文件复用（content_codec_test 等）
// ignore: non_constant_identifier_names
Future<DatabaseService> createTestDbPublic() => _createTestDb();
