import 'package:hive/hive.dart';
import '../models/book_source.dart';

/// 书源存储 —— 基于 Hive 的 JSON 列表读写
///
/// 首次使用时自动写入内置默认书源([kDefaultBookSources])。
/// 用户可增删改书源(设置页「书源管理」),自定义书源同样持久化。
class BookSourceStore {
  Box<dynamic>? _box;
  static const String _boxName = 'book_sources';
  static const String _listKey = 'sources';

  /// 初始化(打开 Hive box,首次自动写入默认书源)
  Future<void> initialize() async {
    _box = await Hive.openBox<dynamic>(_boxName);
    if (!_box!.containsKey(_listKey)) {
      await _box!.put(
        _listKey,
        kDefaultBookSources.map((s) => s.toJson()).toList(),
      );
    }
  }

  Box<dynamic> get _b {
    if (_box == null) {
      throw StateError('BookSourceStore not initialized. Call initialize() first.');
    }
    return _box!;
  }

  /// 获取全部书源(按 sortOrder 排序)
  List<BookSource> getAll() {
    final raw = _b.get(_listKey, defaultValue: <dynamic>[]) as List;
    return raw
        .map((e) => BookSource.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// 获取启用的书源
  List<BookSource> getEnabled() =>
      getAll().where((s) => s.enabled).toList();

  /// 保存全部书源
  Future<void> saveAll(List<BookSource> sources) async {
    await _b.put(
      _listKey,
      sources.map((s) => s.toJson()).toList(),
    );
  }

  /// 添加或更新一个书源
  Future<void> upsert(BookSource source) async {
    final all = getAll();
    final idx = all.indexWhere((s) => s.name == source.name);
    if (idx >= 0) {
      all[idx] = source;
    } else {
      all.add(source);
    }
    // 重新编号 sortOrder
    for (int i = 0; i < all.length; i++) {
      all[i] = _withOrder(all[i], i);
    }
    await saveAll(all);
  }

  /// 删除书源
  Future<void> remove(String name) async {
    final all = getAll().where((s) => s.name != name).toList();
    for (int i = 0; i < all.length; i++) {
      all[i] = _withOrder(all[i], i);
    }
    await saveAll(all);
  }

  /// 恢复默认书源
  Future<void> resetToDefaults() async {
    await _b.put(
      _listKey,
      kDefaultBookSources.map((s) => s.toJson()).toList(),
    );
  }

  BookSource _withOrder(BookSource s, int order) => BookSource(
        name: s.name,
        baseUrl: s.baseUrl,
        search: s.search,
        toc: s.toc,
        content: s.content,
        enabled: s.enabled,
        sortOrder: order,
      );
}
