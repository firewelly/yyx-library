import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/import_result.dart';
import '../providers/database_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import '../l10n/s.dart';

/// 作者管理页面
/// 作者来自 books.author 字段聚合（非独立表），支持：
/// - 浏览所有作者 + 作品数
/// - 点击查看该作者的作品
/// - 重命名作者（修正笔误 / 统一笔名 / 合并作者）
/// - 清空作者归属（保留书籍，去掉 author 字段）
class AuthorsScreen extends ConsumerStatefulWidget {
  const AuthorsScreen({super.key});

  @override
  ConsumerState<AuthorsScreen> createState() => _AuthorsScreenState();
}

class _AuthorsScreenState extends ConsumerState<AuthorsScreen> {
  List<AuthorCount> _authors = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAuthors();
  }

  Future<void> _loadAuthors() async {
    final db = ref.read(databaseServiceProvider);
    final authors = await db.getAllAuthorsWithCount();
    setState(() {
      _authors = authors;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(t('作者管理'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('👤 作者管理（{p1}）', {'p1': _authors.length})),
      ),
      body: _authors.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_off_outlined, size: 64, color: AppColors.emptyState),
                  const SizedBox(height: 16),
                  Text(t('暂无作者'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(t('导入带作者信息的小说后会在此显示'), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.hintText)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _authors.length,
              itemBuilder: (context, index) {
                final item = _authors[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        item.name.isNotEmpty ? item.name.characters.first : '?',
                        style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(t('{p1} 本小说', {'p1': item.count})),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: t('重命名'),
                          onPressed: () => _showRenameDialog(item),
                        ),
                        IconButton(
                          icon: Icon(Icons.link_off, size: 20, color: theme.colorScheme.error),
                          tooltip: t('清空作者归属'),
                          onPressed: () => _confirmClear(item),
                        ),
                      ],
                    ),
                    onTap: () => _showAuthorBooks(item),
                  ),
                );
              },
            ),
    );
  }

  /// 查看该作者的所有作品
  void _showAuthorBooks(AuthorCount item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      item.name.isNotEmpty ? item.name.characters.first : '?',
                      style: TextStyle(color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      t('{p1}（{p2}本）', {'p1': item.name, 'p2': item.count}),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: FutureBuilder(
                future: ref.read(databaseServiceProvider).getBooksByAuthor(item.name),
                builder: (ctx, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final books = snapshot.data!;
                  if (books.isEmpty) {
                    return Center(child: Text(t('无作品')));
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: books.length,
                    itemBuilder: (ctx, index) {
                      final book = books[index];
                      return ListTile(
                        leading: const Icon(Icons.menu_book, size: 20, color: AppColors.hintText),
                        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          book.status.isNotEmpty
                              ? t('{n} · {status}', {'n': Formatters.formatWordCount(book.wordCount), 'status': t(book.status)})
                              : t('{n}字', {'n': Formatters.formatWordCount(book.wordCount)}),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(ctx);
                          context.go('/book/${book.id}');
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 重命名作者（修正笔误 / 统一笔名 / 合并到已有作者）
  void _showRenameDialog(AuthorCount item) {
    final nameCtrl = TextEditingController(text: item.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('重命名作者')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: t('作者名'),
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            Text(
              t('将更新 {p1} 本书的作者字段。'
              '\n若输入的名字已存在，会合并到该作者名下。', {'p1': item.count}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('取消'))),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty || newName == item.name) {
                Navigator.pop(ctx);
                return;
              }
              // 先关对话框再做数据库操作（避免操作期间对话框卡住）
              if (ctx.mounted) Navigator.pop(ctx);
              final affected = await ref.read(databaseServiceProvider).renameAuthor(item.name, newName);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('已更新 {affected} 本书的作者为「{newName}」', {'affected': affected, 'newName': newName}))),
              );
              await _loadAuthors();
            },
            child: Text(t('保存')),
          ),
        ],
      ),
    );
  }

  /// 清空作者归属（保留书籍，将 author 字段置空）
  void _confirmClear(AuthorCount item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('清空作者归属')),
        content: Text(
          t('确定要清空「{p1}」的作者归属吗？\n\n'
          '这将把 {p2} 本书的 author 字段置空（书籍本身保留）。\n'
          '此操作不可撤销。', {'p1': item.name, 'p2': item.count}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('取消'))),
          FilledButton(
            onPressed: () async {
              // 先关对话框再做数据库操作
              if (ctx.mounted) Navigator.pop(ctx);
              final affected = await ref.read(databaseServiceProvider).clearAuthor(item.name);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('已清空 {affected} 本书的作者归属', {'affected': affected}))),
              );
              await _loadAuthors();
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: Text(t('清空')),
          ),
        ],
      ),
    );
  }
}
