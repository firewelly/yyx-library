/// Web 端数据库工厂初始化。
///
/// 使用 [sqflite_common_ffi_web]（基于 SQLite WASM）作为 Web 平台的数据库实现。
/// 数据通过 IndexedDB 持久化，浏览器刷新后数据保留（清除站点数据才会丢失）。
///
/// 这里刻意选用 [databaseFactoryFfiWebNoWebWorker]（主线程实现，非 SharedWorker）：
/// 部分 WebView / 受限浏览器环境（如应用内浏览器）不支持 SharedWorker，会导致
/// 数据库初始化卡死、App 空白。主线程实现兼容性更好，代价是无法跨标签共享连接
/// （对本应用无影响）。
library;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_common/sqflite.dart' show databaseFactory;

/// 初始化当前平台的数据库工厂（Web 端）。
Future<void> initPlatformDatabaseFactory() async {
  // 不使用 SharedWorker 的变体，兼容性更好（见上方文档注释）。
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}


