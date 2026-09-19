import 'package:sqflite/sqflite.dart';

import '../../models/models.dart';
import '../../utils/content_codec.dart';
import '../../utils/zh_converter.dart';
import '../database_service.dart';
import 'nas_state_api.dart';
import 'nas_sql_worker.dart';

/// NAS 只读直连模式的本地小库。
///
/// v2 起进度/书签/笔记已改走服务端状态 API（NasStateApi → novelmgt_state.db，
/// 跟部署走、跨浏览器共享），本地库仅作为未覆盖写路径的空壳兜底保留。
const String kNasLocalDbName = 'novelmgt_local.db';

  /// 条件导出的统一入口：打开 NAS 只读库。
  ///
  /// [dbUrl] 支持相对应用根的路径（db/novelmgt.db）或完整 URL；
  /// 这里统一解析为绝对 URL，因为 worker 内的相对基准与页面不同。
  Future<DatabaseService> openNasDatabase({required String dbUrl}) {
    final resolved =
        Uri.parse(dbUrl).hasScheme ? dbUrl : Uri.base.resolve(dbUrl).toString();
    return NasReadonlyDatabase.open(dbUrl: resolved);
  }

/// NAS 单文件直连数据库（Web 专用）。
///
/// 架构（与 docs/REQUIREMENTS.md 附录 D 对应）：
/// - books/chapters/tags 走 [NasSqlWorker]（浏览器内 SQLite WASM + HTTP Range
///   按需读 NAS 上的单文件 .db，只读，不整库下载）；
/// - reading_progress/bookmarks/notes 走 [NasStateApi]（服务端独立状态库
///   novelmgt_state.db，跟部署走、跨浏览器共享，不按浏览器隔离）；
/// - 进度/书签/笔记展示所需的章节元数据由本类把两边查询手工拼合。
///
/// 只覆盖读路径与状态写路径；创建/导入/标签编辑等库写操作在 NAS 模式不生效
/// （NAS 端库更新走重新快照上传流程）。
class NasReadonlyDatabase extends DatabaseService {
  final NasSqlWorker _remote;
  final NasStateApi _state;

  NasReadonlyDatabase._(this._remote, this._state, Database localDb)
      : super(injectedDb: localDb);

  /// 打开 NAS 只读库。[dbUrl] 为库文件 URL（相对应用根或绝对）。
  /// 状态 API 与页面同源（同一 webserver 托管），无需额外配置。
  static Future<NasReadonlyDatabase> open({required String dbUrl}) async {
    final remote = NasSqlWorker();
    await remote.open(dbUrl: dbUrl);
    final local = DatabaseService(dbName: kNasLocalDbName);
    await local.initialize();
    return NasReadonlyDatabase._(remote, NasStateApi(), local.db);
  }

  // ============================================================
  // 远程查询辅助
  // ============================================================

  Future<List<Map<String, Object?>>> _rq(
    String sql, [
    List<Object?> args = const [],
  ]) =>
      _remote.query(sql, args);

  /// 章节元数据（本地进度/书签/笔记展示用）
  Future<Map<int, List<Object?>>> _chapterMetaById(List<int> ids) async {
    final meta = <int, List<Object?>>{};
    if (ids.isEmpty) return meta;
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await _rq(
      'SELECT id, chapterNumber, title FROM chapters WHERE id IN ($ph)',
      ids,
    );
    for (final r in rows) {
      meta[r['id'] as int] = [r['chapterNumber'], r['title']];
    }
    return meta;
  }

  Future<List<Tag>> _remoteTagsForBook(int bookId) async {
    final rows = await _rq('''
      SELECT t.* FROM tags t
      INNER JOIN book_tags bt ON t.id = bt.tagId
      WHERE bt.bookId = ?
      ORDER BY t.name ASC
    ''', [bookId]);
    return rows.map((r) => Tag.fromJson(r)).toList();
  }

  // ============================================================
  // 书籍（远程只读）
  // ============================================================

  @override
  Future<Book?> getBook(int id) async {
    final rows = await _rq('SELECT * FROM books WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final book = Book.fromJson(rows.first);
    final tags = await _remoteTagsForBook(id);
    return book.copyWith(tags: tags);
  }

  @override
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
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'id IN (SELECT bookId FROM book_tags WHERE tagId = ?)';
      whereArgs.add(tagId);
    }

    final orderBy = '$sortBy ${order == 'desc' ? 'DESC' : 'ASC'}';
    final offset = (page - 1) * perPage;

    final rows = await _rq(
      'SELECT * FROM books'
      '${whereClause.isEmpty ? '' : ' WHERE $whereClause'} '
      'ORDER BY $orderBy LIMIT ? OFFSET ?',
      [...whereArgs, perPage, offset],
    );

    final books = <Book>[];
    for (final row in rows) {
      final book = Book.fromJson(row);
      final tags = await _remoteTagsForBook(book.id!);
      final chapterCount = await getChapterCount(book.id!);
      books.add(book.copyWith(tags: tags, chapterCount: chapterCount));
    }
    return books;
  }

  @override
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

    final count = await _remote.scalar(
      'SELECT COUNT(*) FROM books${where != null ? ' WHERE $where' : ''}',
      whereArgs,
    );
    return (count as int?) ?? 0;
  }

  @override
  Future<List<Book>> searchBooks(String query, {bool searchContent = false}) async {
    if (query.trim().isEmpty) return [];

    var variants = <String>[query.trim()];
    try {
      await ZhConverter.instance.ensureLoaded();
      variants = ZhConverter.instance.searchVariants(query);
    } catch (_) {}
    if (variants.isEmpty) return [];

    final bookConds = <String>[];
    final bookArgs = <Object?>[];
    for (final v in variants) {
      bookConds.add('title LIKE ? OR author LIKE ? OR summary LIKE ?');
      bookArgs..add('%$v%')..add('%$v%')..add('%$v%');
    }
    final bookRows = await _rq(
      'SELECT * FROM books WHERE ${bookConds.join(' OR ')}',
      bookArgs,
    );

    final bookIds = bookRows.map((r) => r['id'] as int).toSet();

    if (searchContent) {
      final titleConds = List.filled(variants.length, 'title LIKE ?').join(' OR ');
      final titleRows = await _rq(
        'SELECT DISTINCT bookId FROM chapters WHERE $titleConds',
        [for (final v in variants) '%$v%'],
      );
      for (final row in titleRows) {
        bookIds.add(row['bookId'] as int);
      }
    }

    final books = <Book>[];
    for (final id in bookIds) {
      final book = await getBook(id);
      if (book != null) books.add(book);
    }
    return books;
  }

  // ============================================================
  // 章节（远程只读）
  // ============================================================

  @override
  Future<List<Chapter>> getChapterList(int bookId) async {
    final rows = await _rq(
      'SELECT id, bookId, chapterNumber, originalOrder, title, \'\' as content, '
      'sourceUrl, sourceFormat, createdAt, updatedAt FROM chapters '
      'WHERE bookId = ? ORDER BY chapterNumber ASC',
      [bookId],
    );
    return rows.map((r) => Chapter.fromJson(r)).toList();
  }

  @override
  Future<String?> getChapterContent(int chapterId) async {
    final rows = await _rq(
      'SELECT content FROM chapters WHERE id = ?',
      [chapterId],
    );
    if (rows.isEmpty) return null;
    return ContentCodec.decode(rows.first['content']);
  }

  @override
  Future<List<Chapter>> getAllChapters(int bookId) async {
    final rows = await _rq(
      'SELECT * FROM chapters WHERE bookId = ? ORDER BY chapterNumber ASC',
      [bookId],
    );
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['content'] = ContentCodec.decode(m['content']);
      return Chapter.fromJson(m);
    }).toList();
  }

  @override
  Future<int> getChapterCount(int bookId) async {
    final count = await _remote.scalar(
      'SELECT COUNT(*) FROM chapters WHERE bookId = ?',
      [bookId],
    );
    return (count as int?) ?? 0;
  }

  @override
  Future<List<Map<String, dynamic>>> searchChapters(int bookId, String query) async {
    if (query.trim().isEmpty) return [];

    var variants = <String>[query.trim()];
    try {
      await ZhConverter.instance.ensureLoaded();
      variants = ZhConverter.instance.searchVariants(query);
    } catch (_) {}
    if (variants.isEmpty) return [];

    final titleConds = List.filled(variants.length, 'title LIKE ?').join(' OR ');
    final rows = await _rq(
      'SELECT id, chapterNumber, title FROM chapters '
      'WHERE bookId = ? AND ($titleConds) ORDER BY chapterNumber ASC',
      [bookId, ...variants.map((v) => '%$v%')],
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

  // ============================================================
  // 标签（远程只读；标签编辑写本地空库，v1 不作用于远程）
  // ============================================================

  @override
  Future<List<Tag>> getAllTags() async {
    final rows = await _rq('SELECT * FROM tags ORDER BY name ASC');
    return rows.map((r) => Tag.fromJson(r)).toList();
  }

  // ============================================================
  // 阅读进度（服务端状态库 + 远程章节元数据拼合）
  // ============================================================

  Future<ReadingProgress?> _composeProgress(ReadingProgress? progress) async {
    if (progress == null) return null;
    final meta = await _chapterMetaById([progress.chapterId]);
    final m = meta[progress.chapterId];
    if (m == null) return progress;
    return progress.copyWith(
      chapterNumber: m[0] as int?,
      chapterTitle: m[1] as String?,
    );
  }

  @override
  Future<ReadingProgress?> getProgress(int bookId) async {
    final row = await _state.getProgress(bookId);
    if (row == null) return null;
    return _composeProgress(ReadingProgress.fromJson(row));
  }

  @override
  Future<ReadingProgress> updateProgress(
    int bookId,
    int chapterId, {
    int scrollPosition = 0,
  }) async {
    final row = await _state.upsertProgress(
      bookId: bookId,
      chapterId: chapterId,
      scrollPosition: scrollPosition,
    );
    final p = ReadingProgress.fromJson(row);
    return await _composeProgress(p) ?? p;
  }

  // ============================================================
  // 书签/笔记（服务端状态库 + 远程章节元数据拼合）
  // ============================================================

  @override
  Future<Bookmark> createBookmark(Bookmark bookmark) async {
    final row = await _state.addBookmark(
      bookId: bookmark.bookId,
      chapterId: bookmark.chapterId,
      position: bookmark.position,
      title: bookmark.title,
      note: bookmark.note,
    );
    return bookmark.copyWith(id: row['id'] as int?);
  }

  @override
  Future<List<Bookmark>> getBookmarks(int bookId) async {
    final rows = await _state.getBookmarks(bookId);
    final ids = rows.map((r) => r['chapterId']).whereType<int>().toSet().toList();
    final meta = await _chapterMetaById(ids);
    return rows.map((r) {
      final m = meta[r['chapterId'] as int?];
      return Bookmark.fromJson({
        ...r,
        if (m != null) 'chapterNumber': m[0],
        if (m != null) 'chapterTitle': m[1],
      });
    }).toList();
  }

  @override
  Future<bool> deleteBookmark(int id) => _state.deleteBookmark(id);

  @override
  Future<Note> createNote(Note note) async {
    final row = await _state.addNote(
      bookId: note.bookId,
      chapterId: note.chapterId,
      position: note.position,
      content: note.content,
    );
    return note.copyWith(id: row['id'] as int?, updatedAt: row['updatedAt'] as String?);
  }

  @override
  Future<List<Note>> getNotesByBook(int bookId) async {
    final rows = await _state.getNotesByBook(bookId);
    return _composeNotes(rows);
  }

  @override
  Future<List<Note>> getNotesByChapter(int chapterId) async {
    final rows = await _state.getNotesByChapter(chapterId);
    return _composeNotes(rows);
  }

  @override
  Future<Note> updateNote(Note note) async {
    if (note.id == null) throw ArgumentError('Note ID cannot be null for update');
    final row = await _state.updateNote(
      note.id!,
      position: note.position,
      content: note.content,
    );
    return note.copyWith(updatedAt: row['updatedAt'] as String?);
  }

  @override
  Future<bool> deleteNote(int id) => _state.deleteNote(id);

  Future<List<Note>> _composeNotes(List<Map<String, Object?>> rows) async {
    if (rows.isEmpty) return [];
    final ids = rows.map((r) => r['chapterId']).whereType<int>().toSet().toList();
    final meta = await _chapterMetaById(ids);
    return rows.map((r) {
      final m = meta[r['chapterId'] as int?];
      return Note.fromJson({
        ...r,
        if (m != null) 'chapterNumber': m[0],
        if (m != null) 'chapterTitle': m[1],
      });
    }).toList();
  }

  // ============================================================
  // 统计（计数走远程；最近阅读从本地进度表拼合）
  // ============================================================

  @override
  Future<LibraryStats> getStats() async {
    final totalBooks = (await _remote.scalar('SELECT COUNT(*) FROM books')) as int? ?? 0;
    final totalChapters = (await _remote.scalar('SELECT COUNT(*) FROM chapters')) as int? ?? 0;
    final totalWords = (await _remote.scalar(
      'SELECT COALESCE(SUM(wordCount), 0) FROM books',
    )) as int? ?? 0;
    final totalAuthors = (await _remote.scalar(
      "SELECT COUNT(DISTINCT author) FROM books WHERE author IS NOT NULL AND author != ''",
    )) as int? ?? 0;
    final totalTags = (await _remote.scalar('SELECT COUNT(*) FROM tags')) as int? ?? 0;

    final statusDistribution = <String, int>{};
    for (final r in await _rq('SELECT status, COUNT(*) as c FROM books GROUP BY status')) {
      statusDistribution[r['status'] as String? ?? '未知'] = r['c'] as int;
    }

    final ratingDistribution = <int, int>{};
    for (final r in await _rq('SELECT rating, COUNT(*) as c FROM books GROUP BY rating')) {
      ratingDistribution[r['rating'] as int] = r['c'] as int;
    }

    final topTags = (await _rq('''
      SELECT t.name, t.color, COUNT(bt.bookId) as c
      FROM tags t
      LEFT JOIN book_tags bt ON t.id = bt.tagId
      GROUP BY t.id
      ORDER BY c DESC
      LIMIT 10
    '''))
        .map((r) => TagCount(
              name: r['name'] as String,
              color: r['color'] as String? ?? '#1976D2',
              count: r['c'] as int,
            ))
        .toList();

    final topAuthors = (await _rq('''
      SELECT author, COUNT(*) as c
      FROM books
      WHERE author IS NOT NULL AND author != ''
      GROUP BY author
      ORDER BY c DESC
      LIMIT 10
    '''))
        .map((r) => AuthorCount(name: r['author'] as String, count: r['c'] as int))
        .toList();

    // 最近阅读：books.lastReadAt 在远程库中恒为空，改由服务端状态库推导
    final progressRows = await _state.getAllProgress();
    final recentlyRead = <Book>[];
    for (final row in progressRows.take(10)) {
      final book = await getBook(row['bookId'] as int);
      if (book != null) recentlyRead.add(book);
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
}
