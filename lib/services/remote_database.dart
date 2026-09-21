import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../utils/zh_converter.dart';
import 'database_service.dart';

/// 远程书库模式（路线 B）：所有数据经同源 /api 访问 NAS 上的共享数据库。
///
/// 继承 [DatabaseService] 以保持 Provider 类型兼容，
/// 仅覆写远程支持的方法；未覆写的方法在远程模式下不可用（抛出 [UnsupportedError]）。
class RemoteDatabaseService extends DatabaseService {
  final String baseUrl; // 例如 ''（同源）或 'http://nas:8765'
  final http.Client _http = http.Client();

  RemoteDatabaseService({this.baseUrl = ''}) : super();

  Uri _u(String path, [Map<String, String>? q]) {
    final query = q == null || q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
    return Uri.parse('$baseUrl/api$path$query');
  }

  Future<Object?> _getJson(String path, [Map<String, String>? q]) async {
    final res = await _http.get(_u(path, q)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('API $path 失败: HTTP ${res.statusCode}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Object?;
  }

  Future<Object?> _sendJson(String method, String path, Map<String, Object?> body) async {
    final req = http.Request(method, _u(path))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    final res = await _http.send(req).timeout(const Duration(seconds: 30));
    final text = await res.stream.bytesToString();
    if (res.statusCode != 200) {
      throw Exception('API $method $path 失败: HTTP ${res.statusCode}');
    }
    return text.isEmpty ? null : jsonDecode(text) as Object?;
  }

  @override
  Future<void> initialize() async {
    // 远程模式不打开本地数据库；健康检查在 main.dart 中完成
  }

  Book _bookFrom(Object? row) {
    final m = Map<String, Object?>.from(row as Map);
    final book = Book.fromJson(m);
    // chapterCount/tags 不在 fromJson 序列化范围，手动补
    return book.copyWith(
      chapterCount: (m['chapterCount'] as num?)?.toInt() ?? book.chapterCount,
    );
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
    final data = await _getJson('/books', {
      'page': '$page',
      'perPage': '$perPage',
      'sortBy': sortBy,
      'order': order,
      if (tagId != null) 'tagId': '$tagId',
      if (status != null && status.isNotEmpty) 'status': status,
      if (minRating != null && minRating > 0) 'minRating': '$minRating',
      if (searchQuery != null && searchQuery.isNotEmpty) 'search': searchQuery,
    }) as Map;
    return [
      for (final row in (data['books'] as List)) _bookFrom(row),
    ];
  }

  @override
  Future<List<Book>> searchBooks(String query, {bool searchContent = false}) async {
    if (query.trim().isEmpty) return [];
    var variants = <String>[query.trim()];
    try {
      await ZhConverter.instance.ensureLoaded();
      variants = ZhConverter.instance.searchVariants(query);
    } catch (_) {}
    final data = await _getJson('/books', {
      'perPage': '200',
      'search': query.trim(),
      'variants': variants.join(','),
    }) as Map;
    return [for (final row in (data['books'] as List)) _bookFrom(row)];
  }

  @override
  Future<Book?> getBook(int id) async {
    try {
      final row = await _getJson('/books/$id');
      return row == null ? null : _bookFrom(row);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> getBookCount({String? status, int? tagId}) async {
    final data = await _getJson('/books', {
      'perPage': '1',
      if (status != null && status.isNotEmpty) 'status': status,
      if (tagId != null) 'tagId': '$tagId',
    }) as Map;
    return data['total'] as int;
  }

  @override
  Future<List<Chapter>> getChapterList(int bookId) async {
    final data = await _getJson('/books/$bookId/chapters') as Map;
    return [
      for (final row in (data['chapters'] as List))
        Chapter.fromJson({...row as Map<String, Object?>, 'content': ''}),
    ];
  }

  @override
  Future<String?> getChapterContent(int chapterId) async {
    final row = await _getJson('/chapters/$chapterId') as Map?;
    return row == null ? null : row['content'] as String?;
  }

  @override
  Future<List<Tag>> getAllTags() async {
    final data = await _getJson('/tags') as Map;
    return [for (final row in (data['tags'] as List)) Tag.fromJson(row as Map<String, Object?>)];
  }

  @override
  Future<int> getBookCountByTag(int tagId) async {
    final data = await _getJson('/tags') as Map;
    for (final row in (data['tags'] as List)) {
      final m = row as Map;
      if (m['id'] == tagId) return (m['bookCount'] as num).toInt();
    }
    return 0;
  }

  @override
  Future<LibraryStats> getStats() async {
    final d = await _getJson('/stats') as Map;
    List<Book> booksOf(List rows) => [
          for (final row in rows) _bookFrom(row),
        ];
    return LibraryStats(
      totalBooks: (d['totalBooks'] as num).toInt(),
      totalChapters: (d['totalChapters'] as num).toInt(),
      totalWords: (d['totalWords'] as num).toInt(),
      totalAuthors: (d['totalAuthors'] as num).toInt(),
      totalTags: (d['totalTags'] as num).toInt(),
      statusDistribution: (d['statusDistribution'] as Map)
          .map((k, v) => MapEntry(k as String, (v as num).toInt())),
      ratingDistribution: (d['ratingDistribution'] as Map)
          .map((k, v) => MapEntry(int.parse(k as String), (v as num).toInt())),
      topTags: [
        for (final r in (d['topTags'] as List))
          TagCount(
            name: (r as Map)['name'] as String,
            color: (r['color'] as String?) ?? '#1976D2',
            count: (r['c'] as num).toInt(),
          ),
      ],
      topAuthors: [
        for (final r in (d['topAuthors'] as List))
          AuthorCount(name: (r as Map)['name'] as String, count: (r['c'] as num).toInt()),
      ],
      recentlyRead: booksOf(d['recentlyRead'] as List),
    );
  }

  // ==================== 用户数据（进度/书签/笔记） ====================

  @override
  Future<ReadingProgress?> getProgress(int bookId) async {
    final row = await _getJson('/user/progress', {'bookId': '$bookId'});
    if (row == null) return null;
    return ReadingProgress.fromJson((row as Map).cast<String, Object?>());
  }

  @override
  Future<ReadingProgress> updateProgress(int bookId, int chapterId, {int scrollPosition = 0}) async {
    final row = await _sendJson('POST', '/user/progress', {
      'bookId': bookId,
      'chapterId': chapterId,
      'scrollPosition': scrollPosition,
    }) as Map;
    return ReadingProgress.fromJson(row.cast<String, Object?>());
  }

  @override
  Future<List<Bookmark>> getBookmarks(int bookId) async {
    final data = await _getJson('/user/bookmarks', {'bookId': '$bookId'}) as Map;
    return [
      for (final row in (data['bookmarks'] as List))
        Bookmark.fromJson((row as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<Bookmark> createBookmark(Bookmark bookmark) async {
    final row = await _sendJson('POST', '/user/bookmarks', {
      'bookId': bookmark.bookId,
      'chapterId': bookmark.chapterId,
      'position': bookmark.position,
      'title': bookmark.title,
      'note': bookmark.note,
    }) as Map;
    return Bookmark.fromJson(row.cast<String, Object?>());
  }

  @override
  Future<bool> deleteBookmark(int id) async {
    await _sendJson('DELETE', '/user/bookmarks/$id', {});
    return true;
  }

  @override
  Future<List<Note>> getNotesByBook(int bookId) async {
    final data = await _getJson('/user/notes', {'bookId': '$bookId'}) as Map;
    return [
      for (final row in (data['notes'] as List))
        Note.fromJson((row as Map).cast<String, Object?>()),
    ];
  }

  @override
  Future<Note> createNote(Note note) async {
    final row = await _sendJson('POST', '/user/notes', {
      'bookId': note.bookId,
      'chapterId': note.chapterId,
      'position': note.position,
      'content': note.content,
    }) as Map;
    return Note.fromJson(row.cast<String, Object?>());
  }

  @override
  Future<Note> updateNote(Note note) async {
    final row = await _sendJson('PUT', '/user/notes/${note.id}', {
      'content': note.content,
    }) as Map;
    return Note.fromJson(row.cast<String, Object?>());
  }

  @override
  Future<bool> deleteNote(int id) async {
    await _sendJson('DELETE', '/user/notes/$id', {});
    return true;
  }
}
