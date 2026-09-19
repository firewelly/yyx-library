import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:novelmgt_flutter/services/database_service.dart';
import 'package:novelmgt_flutter/models/models.dart';

// searchBooks/searchChapters 内部会预加载繁简词典资产（rootBundle），
// 需要 Flutter 绑定已初始化，否则资产加载会挂起
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _runTests();
}

void _runTests() {

Future<DatabaseService> createTestDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  // 创建表结构（因为 injectedDb 跳过 onCreate）
  await db.execute('''
    CREATE TABLE books (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      author TEXT,
      summary TEXT,
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

  late DatabaseService db;

  setUp(() async {
    db = await createTestDb();
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  group('Book CRUD', () {
    test('creates and retrieves a book', () async {
      final now = DateTime.now().toIso8601String();
      final book = await db.createBook(Book(
        title: '测试小说', author: '测试作者', status: '连载中',
        createdAt: now, updatedAt: now,
      ));
      expect(book.id, isNotNull);
      expect(book.title, '测试小说');

      final retrieved = await db.getBook(book.id!);
      expect(retrieved, isNotNull);
      expect(retrieved!.title, '测试小说');
    });

    test('updates a book', () async {
      final now = DateTime.now().toIso8601String();
      final book = await db.createBook(Book(
        title: '原始标题', createdAt: now, updatedAt: now,
      ));
      await db.updateBook(book.copyWith(title: '新标题', rating: 4));
      final updated = await db.getBook(book.id!);
      expect(updated!.title, '新标题');
      expect(updated.rating, 4);
    });

    test('deletes a book', () async {
      final now = DateTime.now().toIso8601String();
      final book = await db.createBook(Book(
        title: '待删除', createdAt: now, updatedAt: now,
      ));
      expect(await db.deleteBook(book.id!), true);
      expect(await db.getBook(book.id!), isNull);
      expect(await db.getBookCount(), 0);
    });

    test('findBookByTitleAndAuthor matches correctly', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(
        title: '诡秘之主', author: '爱潜水的乌贼',
        createdAt: now, updatedAt: now,
      ));
      final found = await db.findBookByTitleAndAuthor('诡秘之主', author: '爱潜水的乌贼');
      expect(found, isNotNull);
      expect(found!.title, '诡秘之主');

      final notFound = await db.findBookByTitleAndAuthor('诡秘之主', author: '其他作者');
      expect(notFound, isNull);
    });

    test('listBooks supports pagination', () async {
      final now = DateTime.now().toIso8601String();
      for (int i = 0; i < 5; i++) {
        await db.createBook(Book(
          title: '小说$i', createdAt: now, updatedAt: now,
        ));
      }
      final page1 = await db.listBooks(page: 1, perPage: 3);
      expect(page1.length, 3);
      final page2 = await db.listBooks(page: 2, perPage: 3);
      expect(page2.length, 2);
    });
  });

  group('Chapter CRUD', () {
    late int bookId;

    setUp(() async {
      final now = DateTime.now().toIso8601String();
      final book = await db.createBook(Book(
        title: '有章节的书', createdAt: now, updatedAt: now,
      ));
      bookId = book.id!;
    });

    test('creates and lists chapters for a book', () async {
      final now = DateTime.now().toIso8601String();
      await db.createChapter(Chapter(
        bookId: bookId, chapterNumber: 1, title: '第一章',
        content: '正文内容', createdAt: now, updatedAt: now,
      ));
      await db.createChapter(Chapter(
        bookId: bookId, chapterNumber: 2, title: '第二章',
        content: '更多内容', createdAt: now, updatedAt: now,
      ));

      final chapters = await db.getChapters(bookId);
      expect(chapters.length, 2);
      expect(chapters[0].chapterNumber, 1);
      expect(chapters[1].chapterNumber, 2);
    });

    test('searchChapters matches by chapter title (content not searched)', () async {
      final now = DateTime.now().toIso8601String();
      await db.createChapter(Chapter(
        bookId: bookId, chapterNumber: 1, title: '第一章 灵根觉醒',
        content: '正文内容', createdAt: now, updatedAt: now,
      ));
      await db.createChapter(Chapter(
        bookId: bookId, chapterNumber: 2, title: '第二章',
        content: '灵根另现', createdAt: now, updatedAt: now,
      ));

      // 命中标题
      final results = await db.searchChapters(bookId, '灵根觉醒');
      expect(results.length, 1);
      expect(results.first['chapterNumber'], 1);
      // 仅内容包含的词不再命中
      final contentOnly = await db.searchChapters(bookId, '修炼有成');
      expect(contentOnly, isEmpty);
    });

    test('getChapterList returns metadata without content', () async {
      final now = DateTime.now().toIso8601String();
      await db.createChapter(Chapter(
        bookId: bookId, chapterNumber: 1, title: '第一章',
        content: '长内容', createdAt: now, updatedAt: now,
      ));
      final list = await db.getChapterList(bookId);
      expect(list.length, 1);
      expect(list.first.content, isEmpty);
    });
  });

  group('Tag operations', () {
    test('creates and retrieves tags', () async {
      final tag = await db.createTag('玄幻');
      expect(tag.id, isNotNull);
      expect(tag.name, '玄幻');

      final tags = await db.getAllTags();
      expect(tags.length, 1);
      expect(tags.first.name, '玄幻');
    });

    test('associates tags with books', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(
        title: '玄幻小说', tags: const [Tag(name: '玄幻')],
        createdAt: now, updatedAt: now,
      ));
      final tags = await db.getAllTags();
      expect(tags.length, 1);
    });
  });

  group('Reading Progress', () {
    test('saves and retrieves progress', () async {
      final now = DateTime.now().toIso8601String();
      final book = await db.createBook(Book(
        title: '阅读测试', createdAt: now, updatedAt: now,
      ));
      final chapter = await db.createChapter(Chapter(
        bookId: book.id!, chapterNumber: 1, title: '第一章',
        content: '内容', createdAt: now, updatedAt: now,
      ));
      await db.updateProgress(book.id!, chapter.id!, scrollPosition: 500);
      final progress = await db.getProgress(book.id!);
      expect(progress, isNotNull);
      expect(progress!.chapterId, chapter.id);
      expect(progress.scrollPosition, 500);
    });
  });

  group('Bookmarks', () {
    test('creates and deletes bookmarks', () async {
      final now = DateTime.now().toIso8601String();
      final book = await db.createBook(Book(title: '书签测试', createdAt: now, updatedAt: now));
      final chapter = await db.createChapter(Chapter(
        bookId: book.id!, chapterNumber: 1, title: '第一章',
        content: '内容', createdAt: now, updatedAt: now,
      ));
      final bm = await db.createBookmark(Bookmark(
        bookId: book.id!, chapterId: chapter.id!,
        title: '重要位置', createdAt: now,
      ));
      expect(bm.id, isNotNull);

      final bookmarks = await db.getBookmarks(book.id!);
      expect(bookmarks.length, 1);

      await db.deleteBookmark(bm.id!);
      expect(await db.getBookmarks(book.id!), isEmpty);
    });
  });

  group('Notes', () {
    test('creates and updates notes', () async {
      final now = DateTime.now().toIso8601String();
      final book = await db.createBook(Book(title: '笔记测试', createdAt: now, updatedAt: now));
      final chapter = await db.createChapter(Chapter(
        bookId: book.id!, chapterNumber: 1, title: '第一章',
        content: '内容', createdAt: now, updatedAt: now,
      ));
      final note = await db.createNote(Note(
        bookId: book.id!, chapterId: chapter.id!,
        content: '原始笔记', createdAt: now, updatedAt: now,
      ));
      expect(note.id, isNotNull);

      await db.updateNote(note.copyWith(content: '修改后的笔记'));
      final notes = await db.getNotesByBook(book.id!);
      expect(notes.length, 1);
      expect(notes.first.content, '修改后的笔记');
    });
  });

  group('Stats', () {
    test('getStats returns correct counts', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(title: '书1', author: '作者A', wordCount: 1000, createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '书2', author: '作者A', wordCount: 2000, createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '书3', author: '作者B', wordCount: 3000, createdAt: now, updatedAt: now));

      final stats = await db.getStats();
      expect(stats.totalBooks, 3);
      expect(stats.totalAuthors, 2);
      expect(stats.totalWords, 6000);
    });
  });

  group('Author management', () {
    test('getAllAuthorsWithCount aggregates and sorts by count', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(title: '书1', author: '作者A', createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '书2', author: '作者A', createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '书3', author: '作者B', createdAt: now, updatedAt: now));
      // 无作者的书应被忽略
      await db.createBook(Book(title: '书4', author: '', createdAt: now, updatedAt: now));

      final authors = await db.getAllAuthorsWithCount();
      expect(authors.length, 2);
      // 作者A 有 2 本，应排在前
      expect(authors.first.name, '作者A');
      expect(authors.first.count, 2);
      expect(authors.last.name, '作者B');
      expect(authors.last.count, 1);
    });

    test('getBooksByAuthor returns books of that author', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(title: '甲', author: '张三', createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '乙', author: '张三', createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '丙', author: '李四', createdAt: now, updatedAt: now));

      final books = await db.getBooksByAuthor('张三');
      expect(books.length, 2);
      expect(books.every((b) => b.author == '张三'), isTrue);

      final none = await db.getBooksByAuthor('不存在');
      expect(none, isEmpty);
    });

    test('renameAuthor updates all books of that author', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(title: '甲', author: '旧名', createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '乙', author: '旧名', createdAt: now, updatedAt: now));

      final affected = await db.renameAuthor('旧名', '新名');
      expect(affected, 2);

      final books = await db.getBooksByAuthor('新名');
      expect(books.length, 2);
      final oldBooks = await db.getBooksByAuthor('旧名');
      expect(oldBooks, isEmpty);
    });

    test('renameAuthor merges into existing author', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(title: '甲', author: '目标', createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '乙', author: '重复', createdAt: now, updatedAt: now));

      await db.renameAuthor('重复', '目标');

      final authors = await db.getAllAuthorsWithCount();
      expect(authors.length, 1);
      expect(authors.first.name, '目标');
      expect(authors.first.count, 2);
    });

    test('renameAuthor no-op on same name', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(title: '甲', author: '同名', createdAt: now, updatedAt: now));

      final affected = await db.renameAuthor('同名', '同名');
      expect(affected, 0);
    });

    test('clearAuthor empties author field, keeps books', () async {
      final now = DateTime.now().toIso8601String();
      await db.createBook(Book(title: '甲', author: '待清空', createdAt: now, updatedAt: now));
      await db.createBook(Book(title: '乙', author: '待清空', createdAt: now, updatedAt: now));

      final affected = await db.clearAuthor('待清空');
      expect(affected, 2);

      final authors = await db.getAllAuthorsWithCount();
      expect(authors, isEmpty); // 该作者已无作品

      // 书籍仍在
      final books = await db.listBooks(page: 1, perPage: 10);
      expect(books.length, 2);
      expect(books.every((b) => b.author == null || b.author!.isEmpty), isTrue);
    });
  });
}
