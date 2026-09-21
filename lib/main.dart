import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'app.dart';
import 'services/database_service.dart';
import 'services/platform_fs.dart';
import 'services/settings_service.dart';
import 'providers/database_provider.dart';
import 'services/nas/nas_backend.dart';
import 'services/remote_database.dart';
import 'theme/app_colors.dart';
import 'utils/database_factory_init.dart';
import 'utils/zh_converter.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // 初始化数据库工厂（条件导入：桌面端用 sqflite_ffi，Web 端用 ffi_web）。
    // 桌面端行为与原 main.dart 完全一致；Web 端用 SQLite WASM 使 App 可在浏览器预览。
    await initPlatformDatabaseFactory();

    // 预加载繁简转换词典（OpenCC，约 1.1MB；不阻塞启动，阅读器/搜索用前会兜底等待）
    unawaited(ZhConverter.instance.ensureLoaded().catchError((Object e) {
      debugPrint('繁简词典加载失败（繁简切换/繁简搜索将退化为原文匹配）: $e');
    }));

    // 初始化 Hive：桌面端固定在应用支持目录（避开 OneDrive 重定向的文档目录，
    // 其 .lock 文件会被同步与多实例竞争搞坏）；Web 端走默认 IndexedDB。
    if (!kIsWeb) {
      Hive.init(await PlatformFs.hiveInitDir());
    } else {
      await Hive.initFlutter();
    }

    // 先读取设置以获取可能的自定义数据库路径
    final settingsService = SettingsService();
    await settingsService.initialize();
    var customDbPath = settingsService.customDbPath;
    // 旧版把库指到 .dart_tool（易被 flutter clean 清掉）→ 自动迁移到稳定目录
    if (customDbPath.isNotEmpty) {
      final normalized = await PlatformFs.normalizeLegacyCustomDbPath(customDbPath, dbName: 'novelmgt.db');
      if (normalized != null) {
        customDbPath = normalized;
        await settingsService.setCustomDbPath(normalized);
        debugPrint('customDbPath 已从 .dart_tool 迁移到: $normalized');
      }
    }

    // 服务端 API 模式（仅 Web）：同源存在 /api/health 时自动启用。
    // 由 deploy/api（Dart shelf）或 deploy/fnos（fnOS 应用）提供服务：
    // 查询在服务端完成（含章节标题索引），书架/搜索/阅读与进度书签笔记
    // 均由服务器共享，性能远优于浏览器直读大库。
    if (kIsWeb && Uri.base.queryParameters['nas'] != '1') {
      var hasApi = false;
      try {
        final res = await http
            .get(Uri.base.resolve('api/health'))
            .timeout(const Duration(seconds: 3));
        hasApi = res.statusCode == 200;
      } catch (_) {}
      if (hasApi) {
        debugPrint('检测到服务端 API，启用远程书库模式');
        final db = RemoteDatabaseService();
        await db.initialize();
        runApp(
          ProviderScope(
            overrides: [
              databaseServiceProvider.overrideWithValue(db),
            ],
            child: const NovelMgtApp(),
          ),
        );
        return;
      }
    }

    // NAS 单文件直连模式（仅 Web）：?nas=1 启用，?db=<库URL> 可选
    // （默认 db/novelmgt.db）。书库只读直连 NAS 上的库文件，进度/书签/笔记
    // 按浏览器本地（IndexedDB）隔离存储。普通模式行为完全不变。
    if (kIsWeb && Uri.base.queryParameters['nas'] == '1') {
      final db = await openNasDatabase(
        dbUrl: Uri.base.queryParameters['db'] ?? 'db/novelmgt.db',
      );
      runApp(
        ProviderScope(
          overrides: [
            databaseServiceProvider.overrideWithValue(db),
          ],
          child: const NovelMgtApp(),
        ),
      );
      return;
    }

    // 初始化数据库（支持自定义路径）
    final db = DatabaseService(customDbPath: customDbPath.isNotEmpty ? customDbPath : null);
    await db.initialize();

    runApp(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(db),
        ],
        child: const NovelMgtApp(),
      ),
    );
  } catch (e, stack) {
    // 如果初始化失败，显示错误界面而不是静默崩溃
    debugPrint('初始化失败: $e\n$stack');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: AppColors.error),
                  const SizedBox(height: 16),
                  const Text('应用初始化失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SelectableText(e.toString(), style: const TextStyle(fontSize: 14, color: AppColors.error)),
                  const SizedBox(height: 16),
                  SelectableText(stack.toString(), style: const TextStyle(fontSize: 11, color: AppColors.hintText)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
