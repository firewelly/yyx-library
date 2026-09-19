import 'package:go_router/go_router.dart';
import '../screens/home_screen.dart';
import '../screens/book_detail_screen.dart';
import '../screens/reader_screen.dart';
import '../screens/import_screen.dart';
import '../screens/crawler_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';
import '../screens/tags_screen.dart';
import '../screens/authors_screen.dart';
import '../widgets/app_shell.dart';

/// 应用路由配置
///
/// 书库/导入/爬虫/统计/标签/作者/设置 套在 [AppShell]（NavigationRail 外壳）内;
/// 书籍详情在外壳内(保留侧边导航),阅读器独立全屏。
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: '/book/:id',
          name: 'bookDetail',
          builder: (context, state) {
            final bookId = int.parse(state.pathParameters['id']!);
            return BookDetailScreen(bookId: bookId);
          },
        ),
        GoRoute(
          path: '/import',
          name: 'import',
          builder: (context, state) => const ImportScreen(),
        ),
        GoRoute(
          path: '/crawler',
          name: 'crawler',
          builder: (context, state) => const CrawlerScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/stats',
          name: 'stats',
          builder: (context, state) => const StatsScreen(),
        ),
        GoRoute(
          path: '/tags',
          name: 'tags',
          builder: (context, state) => const TagsScreen(),
        ),
        GoRoute(
          path: '/authors',
          name: 'authors',
          builder: (context, state) => const AuthorsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/reader/:bookId',
      name: 'reader',
      builder: (context, state) {
        final bookId = int.parse(state.pathParameters['bookId']!);
        final chapterId = state.uri.queryParameters['chapterId'] != null
            ? int.tryParse(state.uri.queryParameters['chapterId']!)
            : null;
        return ReaderScreen(bookId: bookId, initialChapterId: chapterId);
      },
    ),
  ],
);