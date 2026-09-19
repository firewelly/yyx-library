import 'package:flutter/services.dart' show rootBundle;

/// 繁简中文转换器 —— 内置 OpenCC 词典（assets/zh_dict/*.txt）
///
/// - 词典来源：OpenCC 官方 STCharacters/STPhrases（简→繁）与
///   TSCharacters/TSPhrases（繁→简），多候选取第一候选
/// - 算法：最大正向匹配（词组优先、单字兜底），未收录字符原样保留
/// - 纯 Dart 实现 + rootBundle 资产加载，桌面端与 Web 端行为一致
///
/// 用前先 `await ZhConverter.instance.ensureLoaded()`（应用启动时预加载，
/// 之后 toSimplified/toTraditional 为同步调用）。
class ZhConverter {
  ZhConverter._();

  static final ZhConverter instance = ZhConverter._();

  Map<String, String> _s2tPhrases = const {};
  Map<String, String> _s2tChars = const {};
  Map<String, String> _t2sPhrases = const {};
  Map<String, String> _t2sChars = const {};
  int _maxPhraseLen = 1;

  /// 转换结果缓存（章节内容重复渲染时避免重复转换）
  final Map<String, String> _cache = <String, String>{};
  static const int _cacheCapacity = 32;

  Future<void>? _loading;

  bool get isLoaded => _s2tChars.isNotEmpty;

  /// 加载词典（幂等；失败/超时时允许下次重试）。
  ///
  /// 超时保护：无 Flutter 绑定的环境（纯 dart 单测等）rootBundle 会永久挂起，
  /// 这里限时完成，超时抛错由调用方回退（如搜索退化为原始查询词）。
  Future<void> ensureLoaded() {
    return (_loading ??= _load().timeout(const Duration(seconds: 3)))
        .catchError((Object e) {
      _loading = null; // 允许重试
      throw e;
    });
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _loadDict('assets/zh_dict/STPhrases.txt'),
      _loadDict('assets/zh_dict/STCharacters.txt'),
      _loadDict('assets/zh_dict/TSPhrases.txt'),
      _loadDict('assets/zh_dict/TSCharacters.txt'),
    ]);
    _s2tPhrases = results[0];
    _s2tChars = results[1];
    _t2sPhrases = results[2];
    _t2sChars = results[3];

    var maxLen = 1;
    for (final key in _s2tPhrases.keys) {
      if (key.length > maxLen) maxLen = key.length;
    }
    for (final key in _t2sPhrases.keys) {
      if (key.length > maxLen) maxLen = key.length;
    }
    _maxPhraseLen = maxLen;
  }

  /// 解析 OpenCC 文本词典（"键\t候选1 候选2"，取第一候选；# 注释行已剥离）
  Future<Map<String, String>> _loadDict(String assetPath) async {
    final text = await rootBundle.loadString(assetPath);
    final map = <String, String>{};
    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      final key = line.substring(0, tab);
      var value = line.substring(tab + 1);
      final space = value.indexOf(' ');
      if (space > 0) value = value.substring(0, space);
      if (value.isNotEmpty) map[key] = value;
    }
    return map;
  }

  /// 简体 → 繁体
  String toTraditional(String text) => _convertCached(text, 't', _s2tPhrases, _s2tChars);

  /// 繁体 → 简体
  String toSimplified(String text) => _convertCached(text, 's', _t2sPhrases, _t2sChars);

  String _convertCached(String text, String dir, Map<String, String> phrases, Map<String, String> chars) {
    if (!isLoaded || text.isEmpty) return text;
    // 缓存键必须带方向前缀：同一文本（简繁同形字）两个方向结果不同，
    // 否则 toSimplified 的缓存会被 toTraditional 误命中
    final cacheKey = '$dir|$text';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final result = _convert(text, phrases, chars);
    if (_cache.length >= _cacheCapacity) _cache.clear();
    _cache[cacheKey] = result;
    return result;
  }

  /// 最大正向匹配：先试词组（长→短），再单字兜底
  String _convert(String text, Map<String, String> phrases, Map<String, String> chars) {
    final sb = StringBuffer();
    int i = 0;
    final n = text.length;
    while (i < n) {
      var matched = false;
      var maxLen = _maxPhraseLen;
      if (maxLen > n - i) maxLen = n - i;
      for (int len = maxLen; len >= 2; len--) {
        final sub = text.substring(i, i + len);
        final v = phrases[sub];
        if (v != null) {
          sb.write(v);
          i += len;
          matched = true;
          break;
        }
      }
      if (matched) continue;
      final ch = text[i];
      sb.write(chars[ch] ?? ch);
      i++;
    }
    return sb.toString();
  }

  /// 搜索用：把查询词展开为简/繁变体集合（含原文，去重）。
  /// 未加载词典时仅返回原文，保证搜索不因此失效。
  List<String> searchVariants(String query) {
    final q = query.trim();
    if (q.isEmpty) return const [];
    if (!isLoaded) return [q];
    final s = toSimplified(q);
    final t = toTraditional(q);
    return {
      q,
      if (s != q) s,
      if (t != q && t != s) t,
    }.toList();
  }
}
