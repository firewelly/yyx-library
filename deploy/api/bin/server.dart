// ignore_for_file: avoid_print
/// YYX书库 - 远程书库 API（服务端模式）
///
/// 架构：
/// - /data/novelmgt.db  共享书库（只读打开，避免多端写入冲突；由导入侧整库更新）
/// - /data/userdata.db  用户数据（阅读进度/书签/笔记，可写，按浏览器独立账号语义从简）
/// - /srv/web           Flutter Web 静态资源（同源部署，无 CORS 问题）
///
/// 端点（JSON 字段与 sqlite 列名/客户端模型 fromJson 完全对齐）：
/// GET  /api/health
/// GET  /api/books?page&perPage&sortBy&order&tagId&status&minRating&search&variants=a,b,c
/// GET  /api/books/{id}                 （含 tags + chapterCount）
/// GET  /api/books/{id}/chapters        （章节索引，不含正文）
/// GET  /api/chapters/{id}              （含正文，gzip blob 服务端解码）
/// GET  /api/tags
/// GET  /api/stats
/// GET  /api/user/progress?bookId=      POST /api/user/progress
/// GET  /api/user/bookmarks?bookId=     POST /api/user/bookmarks  DELETE /api/user/bookmarks/{id}
/// GET  /api/user/notes?bookId=         POST /api/user/notes  PUT/DELETE /api/user/notes/{id}
import 'dart:convert';
import 'dart:async' show unawaited;
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final String booksDbPath =
    Platform.environment['BOOKS_DB'] ?? '/data/novelmgt.db';
final String userDbPath =
    Platform.environment['USER_DB'] ?? '/data/userdata.db';
final String webDir = Platform.environment['WEB_DIR'] ?? '/srv/web';
final String port = Platform.environment['PORT'] ?? '8080';

late Database booksDb;
late Database userDb;

/// 章节标题索引（userdata.db 内）：chapters 表带 34GB 压缩正文，
/// 直接 LIKE 全表扫会把 blob 页全部读一遍（分钟级）。
/// 启动时把 (bookId, title) 抽到这张小表，搜索毫秒级返回。
bool titleIndexReady = false;
int _titleIndexProgress = 0;

Future<void> _buildTitleIndex() async {
  final sw = Stopwatch()..start();
  await userDb.execute('''
    CREATE TABLE IF NOT EXISTS chapter_title_index (
      bookId INTEGER NOT NULL, title TEXT NOT NULL
    )''');
  final existing = (await userDb.rawQuery('SELECT COUNT(*) as c FROM chapter_title_index')).first['c'] as int;
  final bookCount = (await booksDb.rawQuery('SELECT COUNT(*) as c FROM books')).first['c'] as int;
  if (existing > 0 && existing >= bookCount) {
    titleIndexReady = true;
    print('章节标题索引已就绪（$existing 条，跳过重建）');
    return;
  }
  await userDb.execute('DELETE FROM chapter_title_index');
  // 按 rowid 分页扫描，只取 bookId/title 两列，避免读取正文 blob 的溢出页
  const pageSize = 2000;
  var lastRowId = 0;
  var total = 0;
  final batch = userDb.batch();
  while (true) {
    final page = await booksDb.rawQuery(
      'SELECT rowid AS rid, bookId, title FROM chapters WHERE rowid > ? ORDER BY rowid LIMIT ?',
      [lastRowId, pageSize],
    );
    if (page.isEmpty) break;
    for (final row in page) {
      lastRowId = row['rid'] as int;
      batch.insert('chapter_title_index', {
        'bookId': row['bookId'],
        'title': row['title'],
      });
      total++;
    }
    if (page.length < pageSize) break;
    if (total - _titleIndexProgress >= 100000) {
      _titleIndexProgress = total;
      print('标题索引构建中: $total 行 (${sw.elapsedMilliseconds / 1000}s)');
    }
  }
  await batch.commit(noResult: true);
  await userDb.execute('CREATE INDEX IF NOT EXISTS idx_cti_title ON chapter_title_index(title)');
  await userDb.execute('CREATE INDEX IF NOT EXISTS idx_cti_book ON chapter_title_index(bookId)');
  titleIndexReady = true;
  print('章节标题索引构建完成: $total 条，耗时 ${sw.elapsedMilliseconds / 1000}s');
}

void main() async {
  sqfliteFfiInit();
  booksDb = await databaseFactoryFfi.openDatabase(
    booksDbPath,
    options: OpenDatabaseOptions(readOnly: true),
  );
  userDb = await databaseFactoryFfi.openDatabase(
    userDbPath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS reading_progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL UNIQUE,
            chapterId INTEGER NOT NULL,
            scrollPosition INTEGER DEFAULT 0,
            lastReadAt TEXT,
            createdAt TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL, chapterId INTEGER NOT NULL,
            position INTEGER DEFAULT 0, title TEXT, note TEXT, createdAt TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bookId INTEGER NOT NULL, chapterId INTEGER NOT NULL,
            position INTEGER DEFAULT 0, content TEXT NOT NULL,
            createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL
          )''');
      },
    ),
  );

  final api = Router()
    ..get('/api/health', _health)
    ..get('/api/books', _books)
    ..get('/api/books/<id|[0-9]+>', _book)
    ..get('/api/books/<id|[0-9]+>/chapters', _bookChapters)
    ..get('/api/chapters/<id|[0-9]+>', _chapter)
    ..get('/api/tags', _tags)
    ..get('/api/stats', _stats)
    ..get('/api/user/progress', _getProgress)
    ..post('/api/user/progress', _updateProgress)
    ..get('/api/user/bookmarks', _getBookmarks)
    ..post('/api/user/bookmarks', _createBookmark)
    ..delete('/api/user/bookmarks/<id|[0-9]+>', _deleteBookmark)
    ..get('/api/user/notes', _getNotes)
    ..post('/api/user/notes', _createNote)
    ..put('/api/user/notes/<id|[0-9]+>', _updateNote)
    ..delete('/api/user/notes/<id|[0-9]+>', _deleteNote);

  final staticHandler = createStaticHandler(webDir, defaultDocument: 'index.html');

  /// SPA 路由回退：非 /api 路径未命中时回落 index.html
  Handler spaFallback(Handler inner) => (req) async {
        final res = await inner(req);
        if (res.statusCode == 404 && !req.url.path.startsWith('api/')) {
          final index = File('$webDir/index.html');
          if (await index.exists()) {
            return Response.ok(
              await index.readAsBytes(),
              headers: {'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-cache'},
            );
          }
        }
        return res;
      };

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(spaFallback)
      .addHandler(Cascade().add(api.call).add(staticHandler).handler);

  final server = await io.serve(handler, InternetAddress.anyIPv4, int.parse(port));
  print('novelmgt API 已启动: http://0.0.0.0:${server.port}');
  // 异步构建章节标题索引（构建期间搜索暂不含章节标题命中）
  unawaited(_buildTitleIndex());
}

Response _json(Object? data, {int status = 200}) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Future<Map<String, Object?>> _body(Request req) async =>
    jsonDecode(await req.readAsString()) as Map<String, Object?>;

Future<Response> _health(Request req) async {
  final c = (await booksDb.rawQuery('SELECT COUNT(*) as c FROM books')).first['c'] as int;
  return _json({'ok': true, 'books': c});
}

/// 解码章节内容（gzip blob 或明文字符串，与客户端 ContentCodec 对齐）
Object? _decodeContent(Object? v) {
  if (v == null) return '';
  if (v is String) return v;
  if (v is Uint8List || v is List<int>) {
    final bytes = Uint8List.fromList(v as List<int>);
    if (bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B) {
      return utf8.decode(ZLibCodec().decoder.convert(bytes), allowMalformed: true);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
  return v.toString();
}

Map<String, Object?> _bookRow(Map<String, Object?> row) {
  final m = Map<String, Object?>.from(row);
  m.remove('coverImage');
  return m;
}

Future<List<Map<String, Object?>>> _tagsFor(int bookId) async {
  final rows = await booksDb.rawQuery('''
    SELECT t.id, t.name, t.color FROM tags t
    INNER JOIN book_tags bt ON t.id = bt.tagId
    WHERE bt.bookId = ? ORDER BY t.name ASC
  ''', [bookId]);
  return rows;
}

/// GET /api/books —— 与客户端 listBooks(searchBooks) 对齐
Future<Response> _books(Request req) async {
  final q = req.url.queryParameters;
  final page = int.tryParse(q['page'] ?? '') ?? 1;
  final perPage = (int.tryParse(q['perPage'] ?? '') ?? 50).clamp(1, 200);
  final sortBy = q['sortBy'] ?? 'createdAt';
  final order = (q['order'] ?? 'desc').toLowerCase() == 'asc' ? 'ASC' : 'DESC';
  final status = q['status'];
  final tagId = int.tryParse(q['tagId'] ?? '');
  final minRating = int.tryParse(q['minRating'] ?? '');
  final search = q['search'];
  final variants = (q['variants'] ?? '')
      .split(',')
      .where((e) => e.trim().isNotEmpty)
      .toList();

  final where = <String>[];
  final args = <Object?>[];
  if (status != null && status.isNotEmpty && status != '全部状态') {
    where.add('b.status = ?');
    args.add(status);
  }
  if (tagId != null) {
    where.add('b.id IN (SELECT bookId FROM book_tags WHERE tagId = ?)');
    args.add(tagId);
  }
  if (minRating != null && minRating > 0) {
    where.add('b.rating >= ?');
    args.add(minRating);
  }
  final searchConds = <String>[];
  for (final v in [search, ...variants].whereType<String>()) {
    if (v.trim().isEmpty) continue;
    searchConds.add('b.title LIKE ?');
    args.add('%$v%');
    searchConds.add('b.author LIKE ?');
    args.add('%$v%');
    searchConds.add('b.summary LIKE ?');
    args.add('%$v%');
  }
  // 章节标题搜索：走启动时构建的标题索引小表（毫秒级），不碰 34GB 正文。
  // 索引表在 userdata.db，与 books.db 跨库不能子查询 → 先查 Id 列表再 IN。
  final chapterVariants =
      ([search, ...variants].whereType<String>().map((e) => e.trim()).toSet()).toList()
        ..remove('');
  if (chapterVariants.isNotEmpty && titleIndexReady) {
    final chapterConds = List.filled(chapterVariants.length, 'title LIKE ?').join(' OR ');
    final idRows = await userDb.rawQuery(
      'SELECT DISTINCT bookId FROM chapter_title_index WHERE $chapterConds LIMIT 500',
      chapterVariants.map((v) => '%$v%').toList(),
    );
    final ids = idRows.map((r) => r['bookId'] as int).toList();
    if (ids.isNotEmpty) {
      searchConds.add('b.id IN (${List.filled(ids.length, '?').join(',')})');
      args.addAll(ids);
    } else if (searchConds.isEmpty) {
      // 仅章节标题条件且无命中：直接返回空，避免无谓查询
      return _json({'books': <Object?>[], 'total': 0, 'page': page, 'perPage': perPage});
    }
  }
  if (searchConds.isNotEmpty) where.add('(${searchConds.join(' OR ')})');
  final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

  const sortWhitelist = {
    'title': 'b.title',
    'wordCount': 'b.wordCount',
    'rating': 'b.rating',
    'createdAt': 'b.createdAt',
    'updatedAt': 'b.updatedAt',
    'chapterCount': '(SELECT COUNT(*) FROM chapters c WHERE c.bookId = b.id)',
  };
  final orderBy = sortWhitelist[sortBy] ?? 'b.createdAt';

  final total = (await booksDb.rawQuery(
    'SELECT COUNT(*) as c FROM books b $whereSql',
    args,
  )).first['c'] as int;

  final rows = await booksDb.rawQuery('''
    SELECT b.* FROM books b $whereSql
    ORDER BY $orderBy $order
    LIMIT ? OFFSET ?
  ''', [...args, perPage, (page - 1) * perPage]);

  final books = <Object?>[];
  for (final row in rows) {
    final m = _bookRow(row);
    final id = m['id'] as int;
    m['tags'] = await _tagsFor(id);
    m['chapterCount'] = (await booksDb.rawQuery(
      'SELECT COUNT(*) as c FROM chapters WHERE bookId = ?',
      [id],
    )).first['c'] as int;
    books.add(m);
  }
  return _json({'books': books, 'total': total, 'page': page, 'perPage': perPage});
}

/// GET /api/books/{id}
Future<Response> _book(Request req, String id) async {
  final rows = await booksDb.query('books', where: 'id = ?', whereArgs: [int.parse(id)]);
  if (rows.isEmpty) return _json({'error': 'not found'}, status: 404);
  final m = _bookRow(rows.first);
  m['tags'] = await _tagsFor(int.parse(id));
  m['chapterCount'] = (await booksDb.rawQuery(
    'SELECT COUNT(*) as c FROM chapters WHERE bookId = ?',
    [int.parse(id)],
  )).first['c'] as int;
  return _json(m);
}

/// GET /api/books/{id}/chapters —— 章节索引（content 置空，减小体积）
Future<Response> _bookChapters(Request req, String id) async {
  final rows = await booksDb.query(
    'chapters',
    columns: ['id', 'bookId', 'chapterNumber', 'originalOrder', 'title', 'sourceFormat', 'createdAt', 'updatedAt'],
    where: 'bookId = ?',
    whereArgs: [int.parse(id)],
    orderBy: 'chapterNumber ASC',
  );
  return _json({'chapters': rows});
}

/// GET /api/chapters/{id} —— 含正文（服务端解码 gzip）
Future<Response> _chapter(Request req, String id) async {
  final rows = await booksDb.query(
    'chapters',
    where: 'id = ?',
    whereArgs: [int.parse(id)],
  );
  if (rows.isEmpty) return _json({'error': 'not found'}, status: 404);
  final m = Map<String, Object?>.from(rows.first);
  m['content'] = _decodeContent(m['content']);
  return _json(m);
}

/// GET /api/tags
Future<Response> _tags(Request req) async {
  final rows = await booksDb.rawQuery('''
    SELECT t.id, t.name, t.color, COUNT(bt.bookId) as bookCount
    FROM tags t LEFT JOIN book_tags bt ON t.id = bt.tagId
    GROUP BY t.id ORDER BY t.name ASC
  ''');
  return _json({'tags': rows});
}

/// GET /api/stats —— 与客户端 LibraryStats 构造字段对齐
Future<Response> _stats(Request req) async {
  Future<Object?> scalar(String sql, [String key = 'c']) async =>
      (await booksDb.rawQuery(sql)).first[key];
  final totalBooks = await scalar('SELECT COUNT(*) as c FROM books') as int;
  final totalChapters = await scalar('SELECT COUNT(*) as c FROM chapters') as int;
  final totalWords = await scalar('SELECT COALESCE(SUM(wordCount), 0) as s FROM books', 's') as int;
  final totalAuthors = await scalar(
      "SELECT COUNT(DISTINCT author) as c FROM books WHERE author IS NOT NULL AND author != ''") as int;
  final totalTags = await scalar('SELECT COUNT(*) as c FROM tags') as int;

  final statusDistribution = <String, int>{};
  for (final r in await booksDb.rawQuery('SELECT status, COUNT(*) as c FROM books GROUP BY status')) {
    statusDistribution[r['status'] as String? ?? '未知'] = r['c'] as int;
  }
  final ratingDistribution = <int, int>{};
  for (final r in await booksDb.rawQuery('SELECT rating, COUNT(*) as c FROM books GROUP BY rating')) {
    ratingDistribution[r['rating'] as int] = r['c'] as int;
  }
  final topTags = (await booksDb.rawQuery('''
    SELECT t.name, t.color, COUNT(bt.bookId) as c FROM tags t
    LEFT JOIN book_tags bt ON t.id = bt.tagId
    GROUP BY t.id ORDER BY c DESC LIMIT 10
  ''')).toList();
  final topAuthors = (await booksDb.rawQuery('''
    SELECT author as name, COUNT(*) as c FROM books
    WHERE author IS NOT NULL AND author != ''
    GROUP BY author ORDER BY c DESC LIMIT 10
  ''')).toList();

  final recentRows = await booksDb.rawQuery('''
    SELECT b.* FROM reading_progress rp
    INNER JOIN books b ON b.id = rp.bookId
    ORDER BY rp.lastReadAt DESC LIMIT 10
  ''');
  final recentlyRead = <Object?>[];
  for (final row in recentRows) {
    final m = _bookRow(row);
    m['tags'] = await _tagsFor(m['id'] as int);
    recentlyRead.add(m);
  }

  return _json({
    'totalBooks': totalBooks,
    'totalChapters': totalChapters,
    'totalWords': totalWords,
    'totalAuthors': totalAuthors,
    'totalTags': totalTags,
    'statusDistribution': statusDistribution,
    'ratingDistribution': ratingDistribution,
    'topTags': topTags,
    'topAuthors': topAuthors,
    'recentlyRead': recentlyRead,
  });
}

/// GET /api/user/progress?bookId=
Future<Response> _getProgress(Request req) async {
  final bookId = int.tryParse(req.url.queryParameters['bookId'] ?? '');
  if (bookId == null) return _json({'error': 'bookId required'}, status: 400);
  final rows = await userDb.query('reading_progress',
      where: 'bookId = ?', whereArgs: [bookId], limit: 1);
  return _json(rows.isEmpty ? null : rows.first);
}

/// POST /api/user/progress
Future<Response> _updateProgress(Request req) async {
  final b = await _body(req);
  final bookId = b['bookId'] as int;
  final chapterId = b['chapterId'] as int;
  final scrollPosition = (b['scrollPosition'] as int?) ?? 0;
  final now = DateTime.now().toIso8601String();
  await userDb.execute('''
    INSERT INTO reading_progress (bookId, chapterId, scrollPosition, lastReadAt, createdAt)
    VALUES (?, ?, ?, ?, ?)
    ON CONFLICT(bookId) DO UPDATE SET
      chapterId = excluded.chapterId,
      scrollPosition = excluded.scrollPosition,
      lastReadAt = excluded.lastReadAt
  ''', [bookId, chapterId, scrollPosition, now, now]);
  final rows = await userDb.query('reading_progress',
      where: 'bookId = ?', whereArgs: [bookId], limit: 1);
  return _json(rows.first);
}

/// GET /api/user/bookmarks?bookId=
Future<Response> _getBookmarks(Request req) async {
  final bookId = int.tryParse(req.url.queryParameters['bookId'] ?? '');
  if (bookId == null) return _json({'error': 'bookId required'}, status: 400);
  final rows = await userDb.query('bookmarks',
      where: 'bookId = ?', whereArgs: [bookId], orderBy: 'createdAt DESC');
  return _json({'bookmarks': rows});
}

/// POST /api/user/bookmarks
Future<Response> _createBookmark(Request req) async {
  final b = await _body(req);
  final now = DateTime.now().toIso8601String();
  final map = {
    'bookId': b['bookId'], 'chapterId': b['chapterId'],
    'position': (b['position'] as int?) ?? 0,
    'title': b['title'], 'note': b['note'], 'createdAt': now,
  };
  final id = await userDb.insert('bookmarks', map);
  return _json({...map, 'id': id});
}

/// DELETE /api/user/bookmarks/{id}
Future<Response> _deleteBookmark(Request req, String id) async {
  final n = await userDb.delete('bookmarks', where: 'id = ?', whereArgs: [int.parse(id)]);
  return _json({'deleted': n > 0});
}

/// GET /api/user/notes?bookId=
Future<Response> _getNotes(Request req) async {
  final bookId = int.tryParse(req.url.queryParameters['bookId'] ?? '');
  if (bookId == null) return _json({'error': 'bookId required'}, status: 400);
  final rows = await userDb.query('notes',
      where: 'bookId = ?', whereArgs: [bookId], orderBy: 'updatedAt DESC');
  return _json({'notes': rows});
}

/// POST /api/user/notes
Future<Response> _createNote(Request req) async {
  final b = await _body(req);
  final now = DateTime.now().toIso8601String();
  final map = {
    'bookId': b['bookId'], 'chapterId': b['chapterId'],
    'position': (b['position'] as int?) ?? 0,
    'content': b['content'], 'createdAt': now, 'updatedAt': now,
  };
  final id = await userDb.insert('notes', map);
  return _json({...map, 'id': id});
}

/// PUT /api/user/notes/{id}
Future<Response> _updateNote(Request req, String id) async {
  final b = await _body(req);
  final now = DateTime.now().toIso8601String();
  await userDb.update('notes', {'content': b['content'], 'updatedAt': now},
      where: 'id = ?', whereArgs: [int.parse(id)]);
  final rows = await userDb.query('notes', where: 'id = ?', whereArgs: [int.parse(id)]);
  return _json(rows.first);
}

/// DELETE /api/user/notes/{id}
Future<Response> _deleteNote(Request req, String id) async {
  final n = await userDb.delete('notes', where: 'id = ?', whereArgs: [int.parse(id)]);
  return _json({'deleted': n > 0});
}
