/// 桌面/移动端（dart:io）数据库工厂初始化。
///
/// 在 Windows/Linux 上必须使用 sqflite_ffi（macOS 桌面端 sqflite 默认可用原生，
/// 但统一初始化 ffi 不会产生副作用）。此实现保持原有 main.dart 的行为不变。
library;
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 初始化当前平台的数据库工厂（原生端）。
///
/// 返回是否执行了 ffi 初始化（仅用于日志，调用方可忽略）。
Future<void> initPlatformDatabaseFactory() async {
  // Windows/Linux 桌面端必须使用 sqflite_ffi
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // macOS 桌面与移动端使用 sqflite 默认工厂（平台通道），无需在此处理。
}
