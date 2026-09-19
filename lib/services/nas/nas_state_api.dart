import 'dart:convert';
import 'dart:html' as html;

/// 用户状态（进度/书签/笔记）NAS 端 JSON API 客户端。
///
/// 服务端为 novel_webserver.py 的 /api/state/*（独立状态库 novelmgt_state.db）。
/// 与本地 IndexedDB 方案的区别：状态跟部署走，同一 NAS 部署下所有浏览器共享，
/// 不再按浏览器隔离。行字段与 app 库表列名一致，可直接喂给各 Model.fromJson。
class NasStateApi {
  final String basePath;

  NasStateApi({this.basePath = '/api/state'});

  Future<dynamic> _getJson(String path) async {
    final r = await html.HttpRequest.request(path, method: 'GET');
    return jsonDecode(r.responseText ?? '{}');
  }

  Future<dynamic> _postJson(String path, Map<String, Object?> body) async {
    final r = await html.HttpRequest.request(
      path,
      method: 'POST',
      sendData: jsonEncode(body),
      requestHeaders: {'Content-Type': 'application/json'},
    );
    return jsonDecode(r.responseText ?? '{}');
  }

  Future<List<Map<String, Object?>>> _rows(dynamic decoded) async {
    final rows = (decoded is Map ? decoded['rows'] : null) as List? ?? const [];
    return rows.cast<Map<String, dynamic>>();
  }

  Future<Map<String, Object?>?> _row(dynamic decoded) async {
    if (decoded is! Map) return null;
    return decoded['row'] as Map<String, dynamic>?;
  }

  // ---- 阅读进度 ----

  Future<Map<String, Object?>?> getProgress(int bookId) async {
    final d = await _getJson('$basePath/progress?bookId=$bookId');
    return _row(d);
  }

  Future<List<Map<String, Object?>>> getAllProgress() async {
    final d = await _getJson('$basePath/progress');
    return _rows(d);
  }

  Future<Map<String, Object?>> upsertProgress({
    required int bookId,
    required int chapterId,
    int scrollPosition = 0,
  }) async {
    final d = await _postJson('$basePath/progress', {
      'bookId': bookId,
      'chapterId': chapterId,
      'scrollPosition': scrollPosition,
    });
    return (await _row(d)) ?? <String, Object?>{};
  }

  // ---- 书签 ----

  Future<List<Map<String, Object?>>> getBookmarks(int bookId) async {
    final d = await _getJson('$basePath/bookmarks?bookId=$bookId');
    return _rows(d);
  }

  Future<Map<String, Object?>> addBookmark({
    required int bookId,
    required int chapterId,
    int position = 0,
    String? title,
    String? note,
  }) async {
    final d = await _postJson('$basePath/bookmarks', {
      'bookId': bookId,
      'chapterId': chapterId,
      'position': position,
      'title': title,
      'note': note,
    });
    return (await _row(d)) ?? <String, Object?>{};
  }

  Future<bool> deleteBookmark(int id) async {
    final d = await _postJson('$basePath/bookmarks/delete', {'id': id});
    return d is Map && d['ok'] == true;
  }

  // ---- 笔记 ----

  Future<List<Map<String, Object?>>> getNotesByBook(int bookId) async {
    final d = await _getJson('$basePath/notes?bookId=$bookId');
    return _rows(d);
  }

  Future<List<Map<String, Object?>>> getNotesByChapter(int chapterId) async {
    final d = await _getJson('$basePath/notes?chapterId=$chapterId');
    return _rows(d);
  }

  Future<Map<String, Object?>> addNote({
    required int bookId,
    required int chapterId,
    int position = 0,
    required String content,
  }) async {
    final d = await _postJson('$basePath/notes', {
      'bookId': bookId,
      'chapterId': chapterId,
      'position': position,
      'content': content,
    });
    return (await _row(d)) ?? <String, Object?>{};
  }

  Future<Map<String, Object?>> updateNote(
    int id, {
    int position = 0,
    required String content,
  }) async {
    final d = await _postJson('$basePath/notes/update', {
      'id': id,
      'position': position,
      'content': content,
    });
    return (await _row(d)) ?? <String, Object?>{};
  }

  Future<bool> deleteNote(int id) async {
    final d = await _postJson('$basePath/notes/delete', {'id': id});
    return d is Map && d['ok'] == true;
  }
}
