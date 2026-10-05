import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';
import '../utils/book_path.dart';
import '../utils/content_codec.dart';
import '../utils/zh_converter.dart';
import 'platform_fs.dart';

/// 数据库版本
const int _dbVersion = 5;

/// 数据库名称
const String _dbName = 'novelmgt.db';

/// 数据库服务 - 封装 sqflite 所有 CRUD 操作
///
/// 支持依赖注入：可通过构造函数注入 [Database] 实例，
/// 便于单元测试时使用内存数据库。
class DatabaseService {
  Database? _db;
  String? _dbFilePath;

  /// 用于依赖注入的数据库实例（测试时使用内存数据库）
  final Database? injectedDb;

  /// 自定义数据库路径（用于跨平台共享，如 OneDrive/NAS）
  final String? customDbPath;

  /// 本地库名。默认 novelmgt.db；NAS 只读模式下本地进度库使用独立名称
  /// （kNasLocalDbName），避免与普通 Web 模式的库混用。
  final String dbName;

  DatabaseService({this.injectedDb, this.customDbPath, this.dbName = _dbName});

  /// 获取数据库实例
  Database get db {
    if (_db == null && injectedDb == null) {
      throw StateError('DatabaseService not initialized. Call initialize() first.');
    }
    return _db ?? injectedDb!;
  }

  /// 获取数据库文件路径（供备份使用）
  String? get dbFilePath => _dbFilePath;

  /// 初始化数据库
  Future<void> initialize() async {
    if (injectedDb != null) {
      _db = injectedDb;
      return;
    }
    final path = await _getDatabasePath();
    _dbFilePath = path;
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 获取数据库存储路径（兼容桌面端、自定义路径与 Web）
  Future<String> _getDatabasePath() async {
    // Web 端：sqflite_common_ffi_web 使用 IndexedDB 持久化的虚拟文件系统，
    // 数据库「路径」仅为一个逻辑名，不能调用 path_provider（Web 无实现，
    // 会抛 MissingPluginException）或 dart:io 的 Directory。
    if (kIsWeb) {
      return dbName; // ffi_web 下路径就是文件名本身
    }

    // 如果设置了自定义路径，优先使用（仅桌面端）
    if (customDbPath != null && customDbPath!.isNotEmpty) {
      // 确保目录存在（Web 端不会走到这里：kIsWeb 已提前返回）
      await PlatformFs.ensureDir(customDbPath!);
      return p.join(customDbPath!, dbName);
    }

    // Windows/Linux 桌面端：sqflite_ffi 的 getDatabasesPath() 跟随启动目录
    // 变化（.dart_tool/...），换目录启动会开到不同的库。改用固定的
    // 应用支持目录，并自动迁移旧位置的库（见 PlatformFs.stableDatabaseDir）。
    final stableDir = await PlatformFs.stableDatabaseDir(dbName: dbName);
    if (stableDir != null) {
      return p.join(stableDir, dbName);
    }

    try {
      final base = await getDatabasesPath();
      return p.join(base, dbName);
    } catch (_) {
      // sqflite_ffi 可能无法返回正确路径，使用应用数据目录
      final appDir = await getApplicationSupportDirectory();
      return p.join(appDir.path, _dbName);
    }
  }

  /// 关闭数据库
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  // ============================================================
  // 数据库创建与迁移
  // ============================================================

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

    // 创建索引
    await db.execute('CREATE INDEX idx_books_title ON books(title)');
    await db.execute('CREATE INDEX idx_books_status ON books(status)');
    await db.execute('CREATE INDEX idx_chapters_bookId ON chapters(bookId)');
    await db.execute('CREATE INDEX idx_reading_progress_book ON reading_progress(bookId)');
    await db.execute('CREATE INDEX idx_bookmarks_book ON bookmarks(bookId)');
    await db.execute('CREATE INDEX idx_notes_book ON notes(bookId)');
    await db.execute('CREATE INDEX idx_notes_chapter ON notes(chapterId)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: 迁移列名从 snake_case 到 camelCase（与模型 toJson 一致）
      // 因为是早期版本，直接重建所有表
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
      // v2 → v3: 给 chapters 表添加 updatedAt 字段
      // 先检查字段是否已存在（防止重复迁移）
      final tableInfo = await db.rawQuery('PRAGMA table_info(chapters)');
      final hasUpdatedAt = tableInfo.any((col) => col['name'] == 'updatedAt');
      if (!hasUpdatedAt) {
        await db.execute('ALTER TABLE chapters ADD COLUMN updatedAt TEXT');
      }
      // 更新现有记录：updatedAt 为空时设为 createdAt
      await db.execute("UPDATE chapters SET updatedAt = createdAt WHERE updatedAt IS NULL OR updatedAt = ''");
    }
    if (oldVersion < 4) {
      // v3 → v4: 添加 sourceFormat 列(追踪书籍/章节来源格式 txt/epub/pdf/mobi)
      await _addColumnIfMissing(db, 'books', 'sourceFormat', 'TEXT');
      await _addColumnIfMissing(db, 'chapters', 'sourceFormat', 'TEXT');
    }
    if (oldVersion < 5) {
      // v4 → v5: 添加 filePath 列(本地导入时记录的文件相对路径)
      await _addColumnIfMissing(db, 'books', 'filePath', 'TEXT');
    }
  }

  /// 安全添加列(若已存在则跳过)
  Future<void> _addColumnIfMissing(Database db, String table, String column, String type) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($table)');
    final hasColumn = tableInfo.any((col) => col['name'] == column);
    if (!hasColumn) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  // ============================================================
  // 书籍 CRUD
  // ============================================================

  /// 创建书籍
  /// 创建书籍（含标签关联）。
  ///
  /// [executor] 指定执行器：在事务内调用时必须传入事务对象（sqflite 要求，
  /// 否则会等锁死锁），独立调用时留空用默认连接。
  Future<Book> createBook(Book book, {DatabaseExecutor? executor}) async {
    final dbx = executor ?? db;
    final now = DateTime.now().toIso8601String();
    final map = book.toJson();
    map['createdAt'] = now;
    map['updatedAt'] = now;
    map.remove('id');
    map.remove('tags'); // tags are handled separately

    final id = await dbx.insert('books', map);

    // 处理标签
    if (book.tags.isNotEmpty) {
      for (final tag in book.tags) {
        final tagId = await _ensureTag(tag, executor: dbx);
        await dbx.insert('book_tags', {'bookId': id, 'tagId': tagId});
      }
    }

    return book.copyWith(id: id, createdAt: now, updatedAt: now);
  }

  /// 根据 ID 获取书籍（含标签）
  Future<Book?> getBook(int id) async {
    final rows = await db.query('books', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;

    final book = Book.fromJson(rows.first);
    final tags = await _getTagsForBook(id);
    return book.copyWith(tags: tags);
  }

  /// 查找同标题同作者的书籍（用于导入去重）
  /// 如果 author 为 null 或空，则仅按标题匹配
  Future<Book?> findBookByTitleAndAuthor(String title, {String? author}) async {
    String where;
    List<dynamic> whereArgs;
    if (author != null && author.isNotEmpty) {
      where = 'title = ? AND author = ?';
      whereArgs = [title, author];
    } else {
      where = 'title = ? AND (author IS NULL OR author = \'\')';
      whereArgs = [title];
    }

    final rows = await db.query('books', where: where, whereArgs: whereArgs, limit: 1);
    if (rows.isEmpty) return null;

    final book = Book.fromJson(rows.first);
    final tags = await _getTagsForBook(book.id!);
    return book.copyWith(tags: tags);
  }

  /// 获取书籍列表（分页、排序、筛选）
  Future<List<Book>> listBooks({
    int page = 1,
    int perPage = 20,
    String sortBy = 'createdAt',
    String order = 'desc',
    int? tagId,
    String? status,
    int? minRating,
    String? searchQuery,
  }) async {
    String whereClause = '';
    final whereArgs = <dynamic>[];

    if (status != null && status != '全部状态') {
      whereClause += 'status = ?';
      whereArgs.add(status);
    }

    if (minRating != null && minRating > 0) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'rating >= ?';
      whereArgs.add(minRating);
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += '(title LIKE ? OR summary LIKE ?)';
      whereArgs.add('%$searchQuery%');
      whereArgs.add('%$searchQuery%');
    }

    if (tagId != null) {
      // 通过子查询筛选标签
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'id IN (SELECT bookId FROM book_tags WHERE tagId = ?)';
      whereArgs.add(tagId);
    }

    final orderBy = '$sortBy ${order == 'desc' ? 'DESC' : 'ASC'}';
    final offset = (page - 1) * perPage;

    final rows = await db.query(
      'books',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: orderBy,
      limit: perPage,
      offset: offset,
    );

    final books = <Book>[];
    for (final row in rows) {
      final book = Book.fromJson(row);
      final tags = await _getTagsForBook(book.id!);
      // 查询章节数
      final chapterCount = await getChapterCount(book.id!);
      books.add(book.copyWith(tags: tags, chapterCount: chapterCount));
    }
    return books;
  }

  /// 获取书籍总数
  Future<int> getBookCount({String? status, int? tagId}) async {
    String? where;
    final whereArgs = <dynamic>[];

    if (status != null && status != '全部状态') {
      where = 'status = ?';
      whereArgs.add(status);
    }

    if (tagId != null) {
      where = '${where != null ? '$where AND ' : ''}id IN (SELECT bookId FROM book_tags WHERE tagId = ?)';
      whereArgs.add(tagId);
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM books${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    return result.first['count'] as int;
  }

  /// 搜索书籍（书名/作者/简介/章节标题）。
  ///
  /// 不做章节内容扫描（内容为 gzip blob 且无全文检索需求），
  /// 全部命中走 SQL LIKE，利用索引列，速度快、内存零开销。
  ///
  /// 查询词自动展开为简/繁变体：简体查询可命中繁体书名，反之亦然。
  /// 词典资产不可用（如纯 dart 测试环境）时回退原始查询词。
  Future<List<Book>> searchBooks(String query, {bool searchContent = false}) async {
    if (query.trim().isEmpty) return [];

    var variants = <String>[query.trim()];
    try {
      await ZhConverter.instance.ensureLoaded();
      variants = ZhConverter.instance.searchVariants(query);
    } catch (_) {}
    if (variants.isEmpty) return [];

    // 书名/作者/简介搜索（各变体 OR）
    final bookConds = <String>[];
    final bookArgs = <Object>[];
    for (final v in variants) {
      bookConds.add('title LIKE ? OR author LIKE ? OR summary LIKE ?');
      bookArgs..add('%$v%')..add('%$v%')..add('%$v%');
    }
    final bookRows = await db.query(
      'books',
      where: bookConds.join(' OR '),
      whereArgs: bookArgs,
    );

    final bookIds = bookRows.map((r) => r['id'] as int).toSet();

    // 章节标题搜索（searchContent 参数保留兼容旧调用，含义为「含章节标题」）
    if (searchContent) {
      final titleConds = List.filled(variants.length, 'title LIKE ?').join(' OR ');
      final titleRows = await db.query(
        'chapters',
        columns: ['DISTINCT bookId'],
        where: titleConds,
        whereArgs: [for (final v in variants) '%$v%'],
      );
      for (final row in titleRows) {
        bookIds.add(row['bookId'] as int);
      }
    }

    // 获取完整书籍（含标签与章节数）
    final books = <Book>[];
    for (final id in bookIds) {
      final book = await getBook(id);
      if (book != null) {
        final chapterCount = await getChapterCount(id);
        books.add(book.copyWith(chapterCount: chapterCount));
      }
    }
    return books;
  }

  /// 更新书籍
  Future<Book> updateBook(Book book) async {
    if (book.id == null) throw ArgumentError('Book ID cannot be null for update');

    final updatedAt = DateTime.now().toIso8601String();
    final map = book.toJson();
    map['updatedAt'] = updatedAt;
    map.remove('id');
    map.remove('tags');

    await db.update('books', map, where: 'id = ?', whereArgs: [book.id]);

    // 更新标签：先删除旧关联再插入新的
    await db.delete('book_tags', where: 'bookId = ?', whereArgs: [book.id]);
    if (book.tags.isNotEmpty) {
      for (final tag in book.tags) {
        final tagId = await _ensureTag(tag);
        await db.insert('book_tags', {'bookId': book.id, 'tagId': tagId});
      }
    }

    return book.copyWith(updatedAt: updatedAt);
  }

  /// 删除书籍（级联删除章节、进度、书签、笔记、标签关联）
  Future<bool> deleteBook(int id) async {
    // SQLite 外键 CASCADE 会自动删除关联数据（如果启用）
    // 手动删除以确保兼容性
await db.delete('reading_progress', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('bookmarks', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('notes', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('chapters', where: 'bookId = ?', whereArgs: [id]);
    await db.delete('book_tags', where: 'bookId = ?', whereArgs: [id]);
    final count = await db.delete('books', where: 'id = ?', whereArgs: [id]);
    if (count > 0) {
      // 回收空闲页：SQLite 默认删数据不缩文件，大库删书后体积会一直膨胀。
      // VACUUM 不能在事务内执行，单独跑；失败不阻断删除结果。
      try {
        await db.execute('VACUUM');
      } catch (_) {}
    }
    return count > 0;
  }

  // ============================================================
  // 章节 CRUD
  // ============================================================

  /// 创建章节
  /// 创建章节。事务内调用时经 [executor] 传入事务对象（见 [createBook]）。
  ///
  /// 内容超阈值时 gzip 压缩为 blob 存储（见 [ContentCodec]）。
  Future<Chapter> createChapter(Chapter chapter, {DatabaseExecutor? executor}) async {
    final dbx = executor ?? db;
    final now = DateTime.now().toIso8601String();
    final map = chapter.toJson();
    map.remove('id');
    map['createdAt'] = now;
    map['updatedAt'] = now;
    map['content'] = ContentCodec.encode(chapter.content);
    final id = await dbx.insert('chapters', map);
    return chapter.copyWith(id: id, createdAt: now, updatedAt: now);
  }

  /// 批量创建章节（batch 一次性提交，减少逐条 insert 的 journal 开销）。
  /// 事务内调用时经 [executor] 传入事务对象（见 [createBook]）。
  Future<List<Chapter>> createChaptersBatch(
    List<Chapter> chapters, {
    DatabaseExecutor? executor,
  }) async {
    if (chapters.isEmpty) return const [];
    final dbx = executor ?? db;
    final now = DateTime.now().toIso8601String();
    final batch = dbx.batch();
    for (final chapter in chapters) {
      final map = chapter.toJson();
      map.remove('id');
      map['createdAt'] = now;
      map['updatedAt'] = now;
      map['content'] = ContentCodec.encode(chapter.content);
      batch.insert('chapters', map);
    }
    final results = await batch.commit();
    return [
      for (var i = 0; i < chapters.length; i++)
        chapters[i].copyWith(id: results[i] as int?, createdAt: now, updatedAt: now),
    ];
  }

  /// 获取书籍的章节列表（分页）
  Future<List<Chapter>> getChapters(int bookId, {int page = 1, int perPage = 50}) async {
    final offset = (page - 1) * perPage;
    final rows = await db.query(
      'chapters',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'chapterNumber ASC',
      limit: perPage,
      offset: offset,
    );
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['content'] = ContentCodec.decode(m['content']);
      return Chapter.fromJson(m);
    }).toList();
  }

  /// 获取书籍的章节索引（不含内容，用于导航列表）
  /// 比 getChapters 轻量很多：只加载 id、标题、序号等元数据
  Future<List<Chapter>> getChapterList(int bookId) async {
    final rows = await db.rawQuery(
      'SELECT id, bookId, chapterNumber, originalOrder, title, \'\' as content, sourceUrl, sourceFormat, createdAt, updatedAt FROM chapters WHERE bookId = ? ORDER BY chapterNumber ASC',
      [bookId],
    );
    return rows.map((r) => Chapter.fromJson(r)).toList();
  }

  /// 获取单个章节的完整内容（按需加载）
  Future<String?> getChapterContent(int chapterId) async {
    final rows = await db.query(
      'chapters',
      columns: ['content'],
      where: 'id = ?',
      whereArgs: [chapterId],
    );
    if (rows.isEmpty) return null;
    return ContentCodec.decode(rows.first['content']);
  }

  /// 获取书籍的全部章节（用于导出等需要全量数据的场景）
  Future<List<Chapter>> getAllChapters(int bookId) async {
    final rows = await db.query(
      'chapters',
      where: 'bookId = ?',
      whereArgs: [bookId],
      orderBy: 'chapterNumber ASC',
    );
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['content'] = ContentCodec.decode(m['content']);
      return Chapter.fromJson(m);
    }).toList();
  }

  /// 获取书籍的章节总数
  Future<int> getChapterCount(int bookId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM chapters WHERE bookId = ?',
      [bookId],
    );
    return result.first['count'] as int;
  }

  /// 搜索书籍内的章节（按章节标题匹配）。
  ///
  /// 查询词自动展开为简/繁变体：简体查询可命中繁体标题，反之亦然。
  /// 词典资产不可用（如纯 dart 测试环境）时回退原始查询词。
  ///
  /// 不做章节内容扫描（内容为 gzip blob，无全文检索需求），
  /// 走 SQL LIKE 命中 title 列，返回结构保持 id/chapterNumber/title/context
  /// 与旧版一致（context 恒为空字符串，兼容调用方字段）。
  Future<List<Map<String, dynamic>>> searchChapters(int bookId, String query) async {
    if (query.trim().isEmpty) return [];

    var variants = <String>[query.trim()];
    try {
      await ZhConverter.instance.ensureLoaded();
      variants = ZhConverter.instance.searchVariants(query);
    } catch (_) {}
    if (variants.isEmpty) return [];

    final titleConds = List.filled(variants.length, 'title LIKE ?').join(' OR ');
    final rows = await db.query(
      'chapters',
      columns: ['id', 'chapterNumber', 'title'],
      where: 'bookId = ? AND ($titleConds)',
      whereArgs: [bookId, ...variants.map((v) => '%$v%')],
      orderBy: 'chapterNumber ASC',
    );

    return [
      for (final r in rows)
        {
          'id': r['id'],
          'chapterNumber': r['chapterNumber'],
          'title': r['title'],
          'context': '',
        },
    ];
  }

  /// 更新章节
  Future<Chapter> updateChapter(Chapter chapter) async {
    if (chapter.id == null) throw ArgumentError('Chapter ID cannot be null for update');
    final now = DateTime.now().toIso8601String();
    final map = chapter.toJson();
    map.remove('id');
    map['updatedAt'] = now;
    map['content'] = ContentCodec.encode(chapter.content);
    await db.update('chapters', map, where: 'id = ?', whereArgs: [chapter.id]);
    return chapter.copyWith(updatedAt: now);
  }

  /// 更新章节内容（用于导入时检测内容变化）。
  ///
  /// 返回值：-1 = 章节不存在；0 = 内容无变化；>0 = 已更新，值为更新前的内容长度
  /// （字符数），调用方可据此增量重算书籍字数，无需全量加载章节。
  Future<int> updateChapterContent(int chapterId, String newContent) async {
    // 获取当前章节内容
    final rows = await db.query(
      'chapters',
      columns: ['content'],
      where: 'id = ?',
      whereArgs: [chapterId],
    );
    if (rows.isEmpty) return -1;

    final oldContent = ContentCodec.decode(rows.first['content']);
    // 检查内容是否有变化
    if (oldContent == newContent) return 0;

    // 更新内容和时间戳（压缩写入）
    final now = DateTime.now().toIso8601String();
    await db.update(
      'chapters',
      {'content': ContentCodec.encode(newContent), 'updatedAt': now},
      where: 'id = ?',
      whereArgs: [chapterId],
    );
    return oldContent.length;
  }

  /// 更新书籍的 updatedAt 时间戳
  Future<void> touchBook(int bookId) async {
    final now = DateTime.now().toIso8601String();
    await db.update(
      'books',
      {'updatedAt': now},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  /// 删除章节
  Future<bool> deleteChapter(int id) async {
    final count = await db.delete('chapters', where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }

  // ============================================================
  // 标签管理
  // ============================================================

  /// 创建标签（如果已存在则返回现有ID）
  Future<int> _ensureTag(Tag tag, {DatabaseExecutor? executor}) async {
    final dbx = executor ?? db;
    final existing = await dbx.query('tags', where: 'name = ?', whereArgs: [tag.name]);
    if (existing.isNotEmpty) return existing.first['id'] as int;
    return await dbx.insert('tags', tag.toJson()..remove('id'));
  }

  /// 创建新标签
  Future<Tag> createTag(String name, {String color = '#1976D2'}) async {
    final existing = await db.query('tags', where: 'name = ?', whereArgs: [name]);
    if (existing.isNotEmpty) {
      throw ArgumentError('标签"$name"已存在');
    }
    final id = await db.insert('tags', {'name': name, 'color': color});
    return Tag(id: id, name: name, color: color);
  }

  /// 获取所有标签
  Future<List<Tag>> getAllTags() async {
    final rows = await db.query('tags', orderBy: 'name ASC');
    return rows.map((r) => Tag.fromJson(r)).toList();
  }

  /// 删除标签
  Future<bool> deleteTag(int id) async {
    // 先删除关联
    await db.delete('book_tags', where: 'tagId = ?', whereArgs: [id]);
    final count = await db.delete('tags', where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }

  /// 更新标签
  Future<Tag> updateTag(int id, {String? name, String? color}) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (color != null) updates['color'] = color;
    
    if (updates.isNotEmpty) {
      await db.update('tags', updates, where: 'id = ?', whereArgs: [id]);
    }
    
    final rows = await db.query('tags', where: 'id = ?', whereArgs: [id]);
    return Tag.fromJson(rows.first);
  }

  /// 获取标签关联的书籍数量
  Future<int> getBookCountByTag(int tagId) async {
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM book_tags WHERE tagId = ?',
      [tagId],
    );
    return result.first['count'] as int;
  }

  /// 获取标签关联的所有书籍
  Future<List<Book>> getBooksByTag(int tagId) async {
    final rows = await db.rawQuery('''
      SELECT b.* FROM books b
      INNER JOIN book_tags bt ON b.id = bt.bookId
      WHERE bt.tagId = ?
      ORDER BY b.title ASC
    ''', [tagId]);
    
    final books = <Book>[];
    for (final row in rows) {
      final book = Book.fromJson(row);
      final tags = await _getTagsForBook(book.id!);
      final chapterCount = await getChapterCount(book.id!);
      books.add(book.copyWith(tags: tags, chapterCount: chapterCount));
    }
    return books;
  }

  // ==================== 作者管理 ====================

  /// 获取所有作者及其作品数（按作品数降序）
  /// 作者来自 books.author 字段聚合，非独立表
  Future<List<AuthorCount>> getAllAuthorsWithCount() async {
    final rows = await db.rawQuery('''
      SELECT author, COUNT(*) as c
      FROM books
      WHERE author IS NOT NULL AND author != ''
      GROUP BY author
      ORDER BY c DESC, author ASC
    ''');
    return rows
        .map((r) => AuthorCount(name: r['author'] as String, count: r['c'] as int))
        .toList();
  }

  /// 获取指定作者的所有书籍
  Future<List<Book>> getBooksByAuthor(String author) async {
    final rows = await db.rawQuery(
      'SELECT * FROM books WHERE author = ? ORDER BY title ASC',
      [author],
    );
    return rows.map((r) => Book.fromJson(r)).toList();
  }

  /// 重命名作者（批量更新其所有书籍的 author 字段）
  /// 用于修正拼写错误、统一笔名、或合并两个作者（newName 已存在时即合并）
  /// 返回受影响的书籍数
  Future<int> renameAuthor(String oldName, String newName) async {
    if (oldName.trim().isEmpty || newName.trim().isEmpty) return 0;
    if (oldName == newName) return 0;
    final now = DateTime.now().toIso8601String();
    return db.update(
      'books',
      {'author': newName.trim(), 'updatedAt': now},
      where: 'author = ?',
      whereArgs: [oldName],
    );
  }

  /// 清空指定作者归属（将其所有书籍的 author 字段置空，保留书籍本身）
  /// 返回受影响的书籍数
  Future<int> clearAuthor(String author) async {
    if (author.trim().isEmpty) return 0;
    final now = DateTime.now().toIso8601String();
    return db.update(
      'books',
      {'author': '', 'updatedAt': now},
      where: 'author = ?',
      whereArgs: [author],
    );
  }

  /// 添加标签到书籍
  Future<void> addTagToBook(int bookId, int tagId) async {
    await db.insert('book_tags', {'bookId': bookId, 'tagId': tagId});
  }

  /// 从书籍移除标签
  Future<void> removeTagFromBook(int bookId, int tagId) async {
    await db.delete('book_tags',
        where: 'bookId = ? AND tagId = ?', whereArgs: [bookId, tagId]);
  }

  /// 获取书籍的所有标签
  Future<List<Tag>> _getTagsForBook(int bookId) async {
    final rows = await db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN book_tags bt ON t.id = bt.tagId
      WHERE bt.bookId = ?
      ORDER BY t.name ASC
    ''', [bookId]);
    return rows.map((r) => Tag.fromJson(r)).toList();
  }

  // ============================================================
  // 阅读进度
  // ============================================================

  /// 获取阅读进度
  Future<ReadingProgress?> getProgress(int bookId) async {
    final rows = await db.query(
      'reading_progress',
      where: 'bookId = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return null;

    final progress = ReadingProgress.fromJson(rows.first);
    // 获取章节信息
    final chapterRow = await db.query('chapters',
        where: 'id = ?', whereArgs: [progress.chapterId],
        limit: 1);
    if (chapterRow.isNotEmpty) {
      final chapter = Chapter.fromJson(chapterRow.first);
      return progress.copyWith(
        chapterNumber: chapter.chapterNumber,
        chapterTitle: chapter.title,
      );
    }
    return progress;
  }

  /// 更新阅读进度（upsert）
  Future<ReadingProgress> updateProgress(int bookId, int chapterId, {int scrollPosition = 0}) async {
    final now = DateTime.now().toIso8601String();
    final existing = await db.query(
      'reading_progress',
      where: 'bookId = ?',
      whereArgs: [bookId],
    );

    if (existing.isNotEmpty) {
      await db.update(
        'reading_progress',
        {
          'chapterId': chapterId,
          'scrollPosition': scrollPosition,
          'lastReadAt': now,
        },
        where: 'bookId = ?',
        whereArgs: [bookId],
      );
      final chapterRow = await db.query('chapters', where: 'id = ?', whereArgs: [chapterId], limit: 1);
      return ReadingProgress.fromJson({
        ...existing.first,
        'chapterId': chapterId,
        'scrollPosition': scrollPosition,
        'lastReadAt': now,
        if (chapterRow.isNotEmpty) 'chapterNumber': chapterRow.first['chapterNumber'],
        if (chapterRow.isNotEmpty) 'chapterTitle': chapterRow.first['title'],
      });
    } else {
      final id = await db.insert('reading_progress', {
        'bookId': bookId,
        'chapterId': chapterId,
        'scrollPosition': scrollPosition,
        'lastReadAt': now,
        'createdAt': now,
      });
      return ReadingProgress(
        id: id,
        bookId: bookId,
        chapterId: chapterId,
        scrollPosition: scrollPosition,
        lastReadAt: now,
        createdAt: now,
      );
    }
  }

  // ============================================================
  // 书签
  // ============================================================

  Future<Bookmark> createBookmark(Bookmark bookmark) async {
    final map = bookmark.toJson();
    map.remove('id');
    map.remove('chapterNumber');
    map.remove('chapterTitle');
    final id = await db.insert('bookmarks', map);
    return bookmark.copyWith(id: id);
  }

  Future<List<Bookmark>> getBookmarks(int bookId) async {
    final rows = await db.rawQuery('''
      SELECT b.*, c.chapterNumber, c.title as chapterTitle
      FROM bookmarks b
      LEFT JOIN chapters c ON b.chapterId = c.id
      WHERE b.bookId = ?
      ORDER BY b.createdAt DESC
    ''', [bookId]);
    return rows.map((r) => Bookmark.fromJson(r)).toList();
  }

  Future<bool> deleteBookmark(int id) async {
    final count = await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }

  // ============================================================
  // 笔记
  // ============================================================

  Future<Note> createNote(Note note) async {
    final map = note.toJson();
    map.remove('id');
    map.remove('chapterNumber');
    map.remove('chapterTitle');
    final id = await db.insert('notes', map);
    return note.copyWith(id: id);
  }

  Future<List<Note>> getNotesByBook(int bookId) async {
    final rows = await db.rawQuery('''
      SELECT n.*, c.chapterNumber, c.title as chapterTitle
      FROM notes n
      LEFT JOIN chapters c ON n.chapterId = c.id
      WHERE n.bookId = ?
      ORDER BY n.createdAt DESC
    ''', [bookId]);
    return rows.map((r) => Note.fromJson(r)).toList();
  }

  Future<List<Note>> getNotesByChapter(int chapterId) async {
    final rows = await db.rawQuery('''
      SELECT n.*, c.chapterNumber, c.title as chapterTitle
      FROM notes n
      LEFT JOIN chapters c ON n.chapterId = c.id
      WHERE n.chapterId = ?
      ORDER BY n.position ASC
    ''', [chapterId]);
    return rows.map((r) => Note.fromJson(r)).toList();
  }

  Future<Note> updateNote(Note note) async {
    if (note.id == null) throw ArgumentError('Note ID cannot be null for update');
    final map = note.toJson();
    map.remove('id');
    map.remove('chapterNumber');
    map.remove('chapterTitle');
    map['updatedAt'] = DateTime.now().toIso8601String();
    await db.update('notes', map, where: 'id = ?', whereArgs: [note.id]);
    return note;
  }

  Future<bool> deleteNote(int id) async {
    final count = await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }

  // ============================================================
  // 统计
  // ============================================================

  Future<LibraryStats> getStats() async {
    final totalBooks = (await db.rawQuery('SELECT COUNT(*) as c FROM books')).first['c'] as int;
    final totalChapters = (await db.rawQuery('SELECT COUNT(*) as c FROM chapters')).first['c'] as int;
    final totalWords = (await db.rawQuery('SELECT COALESCE(SUM(wordCount), 0) as s FROM books')).first['s'] as int;

    // 作者数（去重统计 author 字段）
    final authorResult = await db.rawQuery(
      "SELECT COUNT(DISTINCT author) as c FROM books WHERE author IS NOT NULL AND author != ''",
    );
    final totalAuthors = authorResult.first['c'] as int;

    final totalTags = (await db.rawQuery('SELECT COUNT(*) as c FROM tags')).first['c'] as int;

    // 状态分布
    final statusRows = await db.rawQuery('SELECT status, COUNT(*) as c FROM books GROUP BY status');
    final statusDistribution = <String, int>{};
    for (final row in statusRows) {
      statusDistribution[row['status'] as String] = row['c'] as int;
    }

    // 评分分布
    final ratingRows = await db.rawQuery('SELECT rating, COUNT(*) as c FROM books GROUP BY rating');
    final ratingDistribution = <int, int>{};
    for (final row in ratingRows) {
      ratingDistribution[row['rating'] as int] = row['c'] as int;
    }

    // Top 标签
    final tagRows = await db.rawQuery('''
      SELECT t.name, t.color, COUNT(bt.bookId) as c
      FROM tags t
      LEFT JOIN book_tags bt ON t.id = bt.tagId
      GROUP BY t.id
      ORDER BY c DESC
      LIMIT 10
    ''');
    final topTags = tagRows.map((r) => TagCount(
      name: r['name'] as String,
      color: r['color'] as String? ?? '#1976D2',
      count: r['c'] as int,
    )).toList();

    // Top 作者
    final authorRows = await db.rawQuery('''
      SELECT author, COUNT(*) as c
      FROM books
      WHERE author IS NOT NULL AND author != ''
      GROUP BY author
      ORDER BY c DESC
      LIMIT 10
    ''');
    final topAuthors = authorRows.map((r) => AuthorCount(
      name: r['author'] as String,
      count: r['c'] as int,
    )).toList();

    // 最近阅读
    final recentRows = await db.rawQuery('''
      SELECT b.* FROM books b
      WHERE b.lastReadAt IS NOT NULL
      ORDER BY b.lastReadAt DESC
      LIMIT 10
    ''');
    final recentlyRead = <Book>[];
    for (final row in recentRows) {
      final book = Book.fromJson(row);
      final tags = await _getTagsForBook(book.id!);
      recentlyRead.add(book.copyWith(tags: tags));
    }

    return LibraryStats(
      totalBooks: totalBooks,
      totalChapters: totalChapters,
      totalWords: totalWords,
      totalAuthors: totalAuthors,
      totalTags: totalTags,
      statusDistribution: statusDistribution,
      ratingDistribution: ratingDistribution,
      topTags: topTags,
      topAuthors: topAuthors,
      recentlyRead: recentlyRead,
    );
  }

  // ============================================================
  // 备份与恢复（委托给 BackupService）
  // ============================================================

  /// 关闭后重新打开数据库（供 BackupService 恢复时使用）
  Future<void> reopen() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
    await initialize();
  }

  // ============================================================
  // SQL dump 备份/恢复（全平台通用：桌面与 Web 均可用，
  // 也用于跨端迁移——Web IndexedDB ↔ 桌面文件库）
  // ============================================================

  /// dump 覆盖的全部业务表（插入顺序满足外键依赖）
  static const List<String> _dumpTables = [
    'books',
    'chapters',
    'tags',
    'book_tags',
    'reading_progress',
    'bookmarks',
    'notes',
  ];

  /// 导出全库为 SQL dump（CREATE/INSERT 语句文本）。
  ///
  /// 每行数据生成一条显式含 id 的 INSERT，恢复后自增序列自动跟上。
  Future<String> exportSqlDump() async {
    final sb = StringBuffer();
    sb.writeln('-- novelmgt_flutter database backup');
    sb.writeln('-- exported_at=${DateTime.now().toIso8601String()}');
    sb.writeln('-- db_version=$_dbVersion');
    sb.writeln('BEGIN TRANSACTION;');
    for (final table in _dumpTables) {
      final rows = await db.query(table);
      if (rows.isEmpty) continue;
      for (final row in rows) {
        final cols = row.keys.toList();
        final values = row.values.map(_sqlLiteral).join(', ');
        sb.writeln(
            'INSERT INTO $table (${cols.join(', ')}) VALUES ($values);');
      }
    }
    sb.writeln('COMMIT;');
    return sb.toString();
  }

  /// 从 SQL dump 恢复：清空现有全部业务表并重建 schema 后导入。
  ///
  /// 在当前连接上执行（不删库文件，Web 的 IndexedDB 库同样适用）。
  /// 导入完成后建议重启应用以刷新内存中的状态。
  Future<void> restoreFromSqlDump(String sql) async {
    // 1. 清空并重建 schema（含索引）
    for (final table in _dumpTables.reversed) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
    await _onCreate(db, _dbVersion);

    // 2. 在单事务中执行全部语句（与 dump 的 BEGIN/COMMIT 呼应，
    //    导入失败自动回滚，恢复到导入前状态）
    final statements = _splitSqlStatements(sql);
    await db.transaction((txn) async {
      for (final stmt in statements) {
        if (stmt.trim().isEmpty) continue;
        // 跳过 dump 自带的 BEGIN/COMMIT（已由外层事务管理）
        final head = stmt.trimLeft().toUpperCase();
        if (head.startsWith('BEGIN') || head.startsWith('COMMIT')) continue;
        await txn.execute(stmt);
      }
    });
  }

  /// SQL 值字面量（单引号转义为 ''，遵循 SQLite 语法）
  static String _sqlLiteral(Object? v) {
    if (v == null) return 'NULL';
    if (v is bool) return v ? '1' : '0';
    if (v is num) return v.toString();
    return "'${v.toString().replaceAll("'", "''")}'";
  }

  /// 把库中已有的书籍绝对路径批量转换为相对 [root] 的存储形式。
  ///
  /// 用于开启「书库根目录」后迁移历史数据；返回转换条数。
  /// [legacyRoots] 是其他系统的旧库根目录（如 macOS 上的 OneDrive 挂载路径），
  /// 以这些前缀开头的路径同样转为相对形式——跨系统共享库的存量迁移关键。
  /// 不在任何根目录下的路径保持不变；已是相对形式的跳过。
  Future<int> relativizeBookPaths(String root, {List<String> legacyRoots = const []}) async {
    if (root.isEmpty && legacyRoots.isEmpty) return 0;
    final rows = await db.query('books',
        columns: ['id', 'filePath'], where: 'filePath IS NOT NULL');
    int converted = 0;
    for (final row in rows) {
      final raw = row['filePath'] as String?;
      if (raw == null || raw.isEmpty) continue;
      var rel = raw;
      for (final r in [root, ...legacyRoots]) {
        if (r.isEmpty) continue;
        rel = BookPath.relativize(rel, r);
        if (!BookPath.isAbsolute(rel)) break; // 已转出
      }
      if (rel != raw) {
        await db.update('books', {'filePath': rel},
            where: 'id = ?', whereArgs: [row['id']]);
        converted++;
      }
    }
    return converted;
  }

  /// 分析库内书籍路径的存储形态，为迁移提供依据。
  ///
  /// 返回：绝对路径条数、相对/文件名条数，以及绝对路径的
  /// **公共父目录建议**（推断旧系统的库根，覆盖面优先，最多 4 个）。
  Future<({int absoluteCount, int relativeCount, List<String> suggestedRoots})>
      analyzeBookPaths() async {
    final rows = await db.query('books',
        columns: ['filePath'], where: "filePath IS NOT NULL AND filePath != ''");
    int absCount = 0;
    int relCount = 0;
    final dirs = <String>[];
    for (final row in rows) {
      final raw = row['filePath'] as String;
      if (raw.isEmpty) continue;
      if (!BookPath.isAbsolute(raw)) {
        relCount++;
        continue;
      }
      absCount++;
      final n = BookPath.normalize(raw);
      final slash = n.lastIndexOf('/');
      if (slash > 0) dirs.add(n.substring(0, slash));
    }

    final suggestions = <String>[];
    if (dirs.isNotEmpty) {
      // 逐组件最长公共前缀（大小写不敏感比较，Windows 盘符大小写不定）
      var lcp = dirs.first;
      for (final d in dirs) {
        while (!d.toLowerCase().startsWith('${lcp.toLowerCase()}/') &&
            d.toLowerCase() != lcp.toLowerCase()) {
          final slash = lcp.lastIndexOf('/');
          if (slash <= 0) {
            lcp = '';
            break;
          }
          lcp = lcp.substring(0, slash);
        }
        if (lcp.isEmpty) break;
      }
      // 公共前缀可能细到 books 的同名子目录，向上提一级更接近「库根」
      if (lcp.isNotEmpty) {
        final slash = lcp.lastIndexOf('/');
        final parent = slash > 0 ? lcp.substring(0, slash) : lcp;
        suggestions.add(lcp);
        if (parent != lcp && parent.length > 3) suggestions.add(parent);
      }
      // 出现频次最高的目录作为备选
      final freq = <String, int>{};
      for (final d in dirs) {
        freq[d] = (freq[d] ?? 0) + 1;
      }
      final top = freq.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      for (final e in top.take(2)) {
        if (!suggestions.contains(e.key)) suggestions.add(e.key);
      }
    }

    return (
      absoluteCount: absCount,
      relativeCount: relCount,
      suggestedRoots: suggestions.take(4).toList(),
    );
  }

  /// 按语句切分 SQL 文本：仅在不在单引号字符串内的 `;` 处切分。
  /// 跳过 `--` 注释行（dump 头部注释）。
  static List<String> _splitSqlStatements(String sql) {
    final out = <String>[];
    final current = StringBuffer();
    var inString = false;
    for (var i = 0; i < sql.length; i++) {
      final ch = sql[i];
      // 行注释（仅字符串外生效）
      if (!inString && ch == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
        final nl = sql.indexOf('\n', i);
        if (nl < 0) break;
        i = nl; // 跳到行尾（for 循环 i++ 后进入下一行）
        continue;
      }
      if (ch == "'") {
        inString = !inString;
        current.write(ch);
      } else if (ch == ';' && !inString) {
        out.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    if (current.toString().trim().isNotEmpty) out.add(current.toString());
    return out;
  }
}