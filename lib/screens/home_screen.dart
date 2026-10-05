import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/library_provider.dart';
import '../providers/database_provider.dart';
import '../providers/scan_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../utils/constants.dart';
import '../utils/platform_utils.dart';
import '../widgets/book_grid_view.dart';
import '../widgets/book_list_view.dart';

/// 主页 - 书籍列表
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isGridView = false;  // 默认使用列表视图
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _pageJumpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 加载数据
    Future.microtask(() {
      unawaited(ref.read(libraryProvider.notifier).refresh());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageJumpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryProvider);
    final scan = ref.watch(scanProvider);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // Ctrl+F: 聚焦搜索框
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
          _searchFocusNode.requestFocus();
        },
        // Ctrl+I: 跳转导入页
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () {
          context.go('/import');
        },
        // Ctrl+S: 跳转设置页
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          context.go('/settings');
        },
        // Esc: 清除搜索/返回
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_searchController.text.isNotEmpty) {
            _searchController.clear();
            ref.read(libraryProvider.notifier).search('');
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        },
      },
      child: Scaffold(
      appBar: AppBar(
        title: library.isSelectionMode
            ? Text('已选择 ${library.selectedBookIds.length} 本')
            : const Text('📚 书库'),
        actions: library.isSelectionMode
            ? [
                // 全选
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: '全选',
                  onPressed: () => ref.read(libraryProvider.notifier).selectAll(),
                ),
                // 批量导出
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: '批量导出',
                  onPressed: library.selectedBookIds.isEmpty
                      ? null
                      : () => _showBatchExportDialog(context, ref),
                ),
                // 取消选择
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '取消',
                  onPressed: () => ref.read(libraryProvider.notifier).toggleSelectionMode(),
                ),
              ]
            : [
                // 搜索
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: '搜索小说...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      ref.read(libraryProvider.notifier).search(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // 视图切换
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list : Icons.grid_view),
                  tooltip: _isGridView ? '列表视图' : '网格视图',
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
                // 选择模式
                IconButton(
                  icon: const Icon(Icons.checklist),
                  tooltip: '批量选择',
                  onPressed: () => ref.read(libraryProvider.notifier).toggleSelectionMode(),
                ),
                // 扫描书库
                IconButton(
                  icon: scan.isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar),
                  tooltip: scan.isScanning ? '扫描中，点击取消' : '扫描书库（导入新书与更新）',
                  onPressed: () => _handleScan(context, ref),
                ),
              ],
      ),
      body: Column(
        children: [
          // 筛选栏
          _buildFilterBar(library),
          // 内容区（滚动到底自动加载下一页）
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.axis == Axis.vertical &&
                    n.metrics.maxScrollExtent > 0 &&
                    n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
                  ref.read(libraryProvider.notifier).loadNextPage();
                }
                return false;
              },
              child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _isGridView
                  ? Container(
                      key: const ValueKey('grid'),
                      child: const BookGridView(),
                    )
                  : Container(
                      key: const ValueKey('list'),
                      child: const BookListView(),
                    ),
            ),
          ),
          ),
          // 翻页控制条
          _buildPageBar(library),
          // 底部统计
          _buildStatusBar(library),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/import'),
        tooltip: '导入小说',
        child: const Icon(Icons.add),
      ),
    ),
    );
  }

  Widget _buildFilterBar(LibraryState library) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('共 ${library.totalCount} 部小说', style: theme.textTheme.bodySmall),
          // 状态筛选(Chip 化)
          ...['全部状态', ...AppConstants.bookStatuses].map((s) {
            final selected = (s == '全部状态' && library.selectedStatus == null) ||
                library.selectedStatus == s;
            return FilterChip(
              label: Text(s, style: const TextStyle(fontSize: 12)),
              selected: selected,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onSelected: (_) {
                ref.read(libraryProvider.notifier).filterByStatus(
                  s == '全部状态' ? null : s,
                );
              },
            );
          }),
          // 标签筛选(PopupMenuButton 收缩,标签可能很多)
          PopupMenuButton<int?>(
            icon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.label_outline, size: 18),
                const SizedBox(width: 4),
                Text(
                  _selectedTagName(library),
                  style: const TextStyle(fontSize: 12),
                ),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
            tooltip: '标签筛选',
            onSelected: (value) {
              ref.read(libraryProvider.notifier).filterByTag(value);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('全部标签', style: TextStyle(fontSize: 13))),
              ...library.tags.map((t) => PopupMenuItem(
                value: t.id,
                child: Text(t.name, style: const TextStyle(fontSize: 13)),
              )),
            ],
          ),
          // 排序
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, size: 20),
            tooltip: '排序',
            onSelected: (value) {
              final isAsc = library.sortOrder == 'asc';
              ref.read(libraryProvider.notifier).sort(value, isAsc ? 'desc' : 'asc');
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'title', child: Text('标题')),
              const PopupMenuItem(value: 'wordCount', child: Text('字数')),
              const PopupMenuItem(value: 'rating', child: Text('评分')),
              const PopupMenuItem(value: 'createdAt', child: Text('导入时间')),
            ],
          ),
        ],
      ),
    );
  }

  /// 当前选中标签的显示名
  String _selectedTagName(LibraryState library) {
    if (library.selectedTagId == null) return '全部标签';
    for (final t in library.tags) {
      if (t.id == library.selectedTagId) return t.name;
    }
    return '全部标签';
  }

  /// 翻页控制条：上一页 / 页码 / 下一页（搜索模式一次拉全量，隐藏）
  Widget _buildPageBar(LibraryState library) {
    if (library.searchQuery.isNotEmpty) return const SizedBox.shrink();
    final totalPages = (library.totalCount / LibraryState.pageSize).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();
    final page = library.page.clamp(1, totalPages);
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: '上一页',
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 1
                ? () => ref.read(libraryProvider.notifier).goToPage(page - 1)
                : null,
          ),
          Text('第 $page / $totalPages 页 · 共 ${library.totalCount} 本',
              style: theme.textTheme.bodySmall),
          IconButton(
            tooltip: '下一页',
            icon: const Icon(Icons.chevron_right),
            onPressed: page < totalPages
                ? () => ref.read(libraryProvider.notifier).goToPage(page + 1)
                : null,
          ),
          const SizedBox(width: 12),
          // 快速跳页：输入页码后回车直达
          SizedBox(
            width: 64,
            height: 30,
            child: TextField(
              controller: _pageJumpController,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: '页码',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: (v) {
                final p = int.tryParse(v.trim());
                if (p != null && p >= 1 && p <= totalPages && p != page) {
                  ref.read(libraryProvider.notifier).goToPage(p);
                  _pageJumpController.clear();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(LibraryState library) {
    final theme = Theme.of(context);
    final scan = ref.watch(scanProvider);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scan.isScanning) ...[
            LinearProgressIndicator(value: scan.progress, minHeight: 2),
            const SizedBox(height: 4),
          ],
          Text(
            scan.isScanning
                ? '扫描中 ${(scan.progress * 100).round()}% | ${scan.statusMessage}'
                : '小说: ${library.totalCount} 部 | 标签: ${library.tags.length} 个',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// 扫描书库：后台遍历所有配置的书库文件夹，导入新书并更新章节
  Future<void> _handleScan(BuildContext context, WidgetRef ref) async {
    final scan = ref.read(scanProvider);
    // 扫描中再次点击 = 取消
    if (scan.isScanning) {
      unawaited(ref.read(scanProvider.notifier).startScan(const []));
      return;
    }

    final folders = ref.read(settingsProvider).settings.libraryFolders;
    if (folders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('尚未配置书库文件夹（支持相对路径，如 novels、H）'),
          action: SnackBarAction(
            label: '去设置',
            onPressed: () => context.go('/settings'),
          ),
        ),
      );
      return;
    }

    await ref.read(scanProvider.notifier).startScan(folders);

    if (!context.mounted) return;
    final state = ref.read(scanProvider);
    if (state.error != null && state.error!.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描出错: ${state.error}')),
      );
      return;
    }
    final result = state.result;
    if (result != null) {
      // 有变动才刷新书库
      if (result.imported > 0 || result.updated > 0 || result.failed > 0) {
        unawaited(ref.read(libraryProvider.notifier).refresh());
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '扫描完成: 新增 ${result.imported}，更新 ${result.updated}，'
            '无变化 ${result.noChange}，失败 ${result.failed}，跳过占位 ${result.placeholderSkipped}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  /// 批量导出对话框
  void _showBatchExportDialog(BuildContext context, WidgetRef ref) {
    final selectedBooks = ref.read(libraryProvider.notifier).getSelectedBooks();
    String format = 'txt';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('批量导出'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将导出 ${selectedBooks.length} 本小说'),
              const SizedBox(height: 16),
              const Text('选择格式:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _exportChoice(ctx, 'TXT', 'txt', format, () => setDialogState(() => format = 'txt')),
                  _exportChoice(ctx, 'EPUB', 'epub', format, () => setDialogState(() => format = 'epub')),
                  _exportChoice(ctx, 'PDF', 'pdf', format, () => setDialogState(() => format = 'pdf')),
                  _exportChoice(ctx, 'Kindle', 'mobi', format, () => setDialogState(() => format = 'mobi')),
                ],
              ),
              if (format == 'mobi')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Kindle 导出为 EPUB 格式(Kindle 设备可直接读取)',
                    style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _doBatchExport(context, ref, selectedBooks, format);
              },
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );
  }

  /// 导出格式选择按钮
  Widget _exportChoice(BuildContext ctx, String label, String value, String current, VoidCallback onTap) {
    final selected = value == current;
    final cs = Theme.of(ctx).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 执行批量导出
  Future<void> _doBatchExport(BuildContext context, WidgetRef ref, List<dynamic> books, String format) async {
    try {
      final db = ref.read(databaseServiceProvider);
      final exportService = ExportService(db);
      int successCount = 0;
      final List<String> errors = [];

      if (PlatformUtils.isWeb) {
        // Web 端：无目录概念，逐本触发浏览器下载
        for (final book in books) {
          try {
            await exportService.exportDownload(book.id!, format);
            successCount++;
          } catch (e) {
            errors.add('${book.title}: $e');
          }
        }
      } else {
        final outputDir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择导出目录',
        );
        if (outputDir == null) return;

        for (final book in books) {
          try {
            await exportService.export(book.id!, outputDir, format);
            successCount++;
          } catch (e) {
            errors.add('${book.title}: $e');
          }
        }
      }

      ref.read(libraryProvider.notifier).toggleSelectionMode();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出完成: $successCount/${books.length} 本成功'),
            action: errors.isNotEmpty
                ? SnackBarAction(
                    label: '查看错误',
                    onPressed: () => _showExportErrors(context, errors),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 显示导出错误列表
  void _showExportErrors(BuildContext context, List<String> errors) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出错误'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: errors.length,
            itemBuilder: (_, i) => ListTile(
              dense: true,
              leading: Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
              title: Text(errors[i], style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }
}