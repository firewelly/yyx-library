import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:typed_data';

/// NAS 只读库的 SQL 执行通道。
///
/// 底层是 vendored 的 sql.js-httpvfs（web/sqlite_http/）：浏览器 worker 内跑
/// SQLite WASM，经 HTTP Range 请求按需读取 NAS 上的单文件 .db，不整库下载、
/// 不写任何后端。
///
/// 调用链：Dart → __nasBridge (nas_bridge.js) → createDbWorker (Comlink)
/// → sqlite.worker.js。结果在 JS 侧 JSON.stringify 成纯字符串、Dart 侧
/// jsonDecode——双方只见纯数据，绕开 Comlink Proxy 与 dart2js 互操作
/// 的隐式转换冲突。
///
/// 仅 Web 端可用（依赖 dart:html 与 JS 全局）。

/// window.__nasBridge 的显式绑定（避免 callMethod 动态派发的补丁差异）
@JS()
@anonymous
extension type _NasBridge(JSObject _) implements JSObject {
  external JSPromise<JSBoolean> init(
    JSAny? configs,
    JSString workerUrl,
    JSString wasmUrl,
    JSNumber maxBytes,
  );
  external JSPromise<JSString> exec(JSString sql, JSAny? args);
}

@JS('__nasBridge')
external _NasBridge get _nasBridge;

class NasSqlWorker {
  bool _ready = false;

  static const String _sqlhttpSrc = 'sqlite_http/sqlhttp.js';
  static const String _bridgeSrc = 'sqlite_http/nas_bridge.js';
  static const String _workerSrc = 'sqlite_http/sqlite.worker.js';
  static const String _wasmSrc = 'sqlite_http/sql-wasm.wasm';

  bool get isOpen => _ready;

  Future<void> _loadScript(String src) {
    final completer = Completer<void>();
    final script = html.ScriptElement()
      ..src = src
      ..async = false;
    unawaited(script.onLoad.first.then((_) {
      if (!completer.isCompleted) completer.complete();
    }));
    unawaited(script.onError.first.then((_) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('无法加载 $src'));
      }
    }));
    html.document.head!.append(script);
    return completer.future;
  }

  bool _scriptsLoaded = false;

  Future<void> _ensureScriptsLoaded() async {
    if (_scriptsLoaded) return;
    await _loadScript(_sqlhttpSrc);
    await _loadScript(_bridgeSrc);
    _scriptsLoaded = true;
  }

  /// 打开远程只读库。HTTP 读取总量上限 [maxBytesToRead] 用于异常查询兜底。
  Future<void> open({
    required String dbUrl,
    int requestChunkSize = 4096,
    int maxBytesToRead = 1024 * 1024 * 1024,
  }) async {
    if (_ready) return;
    await _ensureScriptsLoaded();

    final config = {
      'from': 'inline',
      'config': {
        'serverMode': 'full',
        'requestChunkSize': requestChunkSize,
        'url': dbUrl,
      },
    };

    // worker 内部解析相对 URL 的基准是 worker 脚本自身位置，
    // 必须先在页面侧解析为绝对 URL 再传入。
    await _nasBridge
        .init(
          ([config].jsify()) as JSArray<JSAny?>,
          Uri.base.resolve(_workerSrc).toString().toJS,
          Uri.base.resolve(_wasmSrc).toString().toJS,
          maxBytesToRead.toDouble().toJS,
        )
        .toDart;
    _ready = true;
  }

  /// 执行只读 SELECT，返回按列名取的行列表（对应 sqflite 的 query 行格式）。
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?> args = const [],
  ]) async {
    if (!_ready) throw StateError('NasSqlWorker 尚未 open()');
    final String json;
    try {
      json = (await _nasBridge.exec(sql.toJS, args.jsify()).toDart).toDart;
    } catch (e) {
      // 把失败 SQL 带进错误信息，便于在 UI 错误提示里直接定位
      throw StateError('NAS query 失败 [$sql | args=$args]: $e');
    }
    return _rowsFromJson(json);
  }

  /// 单行单列取值（COUNT/SUM 等标量查询）
  Future<Object?> scalar(String sql, [List<Object?> args = const []]) async {
    final rows = await query(sql, args);
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row.isEmpty) return null;
    return row.values.first;
  }

  /// 桥返回的 JSON → 行列表。
  ///
  /// JSON 值类型：TEXT→String、INTEGER→int（jsonDecode 整数即 int）、
  /// BLOB→sql.js 给的是 Uint8Array，桥的 JSON.stringify 会把它序列化成
  /// {"0":31,...} 形式的对象——这里还原回 Uint8List 交给 ContentCodec。
  static List<Map<String, Object?>> _rowsFromJson(String json) {
    final decoded = jsonDecode(json) as List<dynamic>;
    final rows = <Map<String, Object?>>[];
    for (final resultSet in decoded) {
      final columns = (resultSet['columns'] as List).cast<String>();
      final values = resultSet['values'] as List;
      for (final vrow in values) {
        final cells = vrow as List;
        final m = <String, Object?>{};
        for (var i = 0; i < columns.length && i < cells.length; i++) {
          m[columns[i]] = _jsonCellToDart(cells[i]);
        }
        rows.add(m);
      }
    }
    return rows;
  }

  static Object? _jsonCellToDart(Object? v) {
    if (v == null) return null;
    if (v is int || v is double || v is String || v is bool) return v;
    if (v is List) {
      // JSON.stringify 对 Uint8Array 不产生数组，但兜底处理普通数组
      return Uint8List.fromList(v.map((e) => (e as num).toInt()).toList());
    }
    if (v is Map) {
      // BLOB 被 JSON.stringify 成 {"0":..,"1":..} 的稀疏对象 → 还原字节
      final n = v.length;
      final bytes = Uint8List(n);
      var isByteMap = true;
      for (var i = 0; i < n; i++) {
        final e = v['$i'];
        if (e is int && e >= 0 && e <= 255) {
          bytes[i] = e;
        } else {
          isByteMap = false;
          break;
        }
      }
      if (isByteMap) return bytes;
      return v.toString();
    }
    return v.toString();
  }
}
