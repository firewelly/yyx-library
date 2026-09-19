import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/constants.dart';

/// 应用外壳 - NavigationRail 常驻侧边导航
///
/// 书库/导入/爬虫/统计/标签/作者/设置 走 ShellRoute 复用此布局;
/// 阅读器(/reader)独立全屏,不套外壳。
class AppShell extends ConsumerWidget {
  final Widget child;
  final String location;

  const AppShell({super.key, required this.child, required this.location});

  static const _allDestinations = [
    (path: '/', icon: Icons.local_library_outlined, selectedIcon: Icons.local_library, label: '书库'),
    (path: '/import', icon: Icons.file_download_outlined, selectedIcon: Icons.file_download, label: '导入'),
    (path: '/crawler', icon: Icons.travel_explore, selectedIcon: Icons.travel_explore, label: '爬虫'),
    (path: '/stats', icon: Icons.bar_chart, selectedIcon: Icons.bar_chart, label: '统计'),
    (path: '/tags', icon: Icons.label_outline, selectedIcon: Icons.label, label: '标签'),
    (path: '/authors', icon: Icons.person_outline, selectedIcon: Icons.person, label: '作者'),
  ];

  /// 分发版本(ENABLE_CRAWLER=false)隐藏网络抓取入口
  static List<({String path, IconData icon, IconData selectedIcon, String label})> get _destinations =>
      _allDestinations.where((d) => AppConstants.enableCrawler || d.path != '/crawler').toList();

  int get _selectedIndex {
    final destinations = _destinations;
    for (var i = destinations.length - 1; i >= 0; i--) {
      final d = destinations[i].path;
      if (location == d || (d != '/' && location.startsWith(d))) return i;
      if (d == '/' && (location == '/' || location.startsWith('/book/'))) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final extended = width >= 1280;

    return Scaffold(
      body: Row(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (i) => context.go(_destinations[i].path),
                    extended: extended,
                    labelType: extended ? null : NavigationRailLabelType.all,
                    leading: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: extended
                          ? const Padding(
                              padding: EdgeInsets.only(left: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text('📚 YYX书库', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              ),
                            )
                          : const Icon(Icons.menu_book),
                    ),
                    trailing: const Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 16),
                          child: _SettingsDestination(),
                        ),
                      ),
                    ),
                    destinations: [
                      for (final d in _destinations)
                        NavigationRailDestination(
                          icon: Icon(d.icon),
                          selectedIcon: Icon(d.selectedIcon),
                          label: Text(d.label),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 设置入口放在 rail 底部(避免与内容导航混排)
class _SettingsDestination extends ConsumerWidget {
  const _SettingsDestination();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final selected = location.startsWith('/settings');
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go('/settings'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? colors.primaryContainer : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? Icons.settings : Icons.settings_outlined,
                color: selected ? colors.onPrimaryContainer : colors.onSurfaceVariant),
            const SizedBox(height: 4),
            Text('设置', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
