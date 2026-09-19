import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/database_service.dart';

/// 数据库服务 Provider（全局依赖注入点）
///
/// 在 main.dart 中通过 ProviderScope.overrides 注入已初始化的实例
final databaseServiceProvider = Provider<DatabaseService>((ref) => DatabaseService());