/// 平台相关的数据库工厂初始化（条件导入入口）。
///
/// 调用 [initDatabaseFactory] 后，会将全局 [databaseFactory] 设置为当前平台
/// 合适的实现：
/// - 桌面端（Windows/Linux/macOS 桌面 sqflite_ffi）：见 io 实现
/// - Web 端（sqflite_common_ffi_web，SQLite WASM + IndexedDB）：见 web 实现
///
/// 设计目的：让同一份代码在桌面与 Web 都能初始化数据库。Web 端无需 Xcode
/// 即可在浏览器中预览 App；桌面端行为完全不变。
library;

export 'database_factory_init_io.dart'
    if (dart.library.html) 'database_factory_init_web.dart';
