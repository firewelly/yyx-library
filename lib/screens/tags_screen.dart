import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/book.dart';
import '../providers/database_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// 标签管理页面
class TagsScreen extends ConsumerStatefulWidget {
  const TagsScreen({super.key});

  @override
  ConsumerState<TagsScreen> createState() => _TagsScreenState();
}

class _TagsScreenState extends ConsumerState<TagsScreen> {
  List<TagWithCount> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final db = ref.read(databaseServiceProvider);
    final tags = await db.getAllTags();
    
    final tagsWithCount = <TagWithCount>[];
    for (final tag in tags) {
      final count = await db.getBookCountByTag(tag.id!);
      tagsWithCount.add(TagWithCount(tag: tag, bookCount: count));
    }
    
    // 按书籍数量降序排序
    tagsWithCount.sort((a, b) => b.bookCount.compareTo(a.bookCount));
    
    setState(() {
      _tags = tagsWithCount;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('标签管理')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('🏷️ 标签管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建标签',
            onPressed: () => _showCreateDialog(),
          ),
        ],
      ),
      body: _tags.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.label_off, size: 64, color: AppColors.emptyState),
                  const SizedBox(height: 16),
                  Text('暂无标签', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text('点击右上角 + 创建新标签', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.hintText)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _tags.length,
              itemBuilder: (context, index) {
                final item = _tags[index];
                return Card(
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _parseColor(item.tag.color),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${item.bookCount}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    title: Text(item.tag.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('关联 ${item.bookCount} 本小说'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: '编辑',
                          onPressed: () => _showEditDialog(item),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 20, color: theme.colorScheme.error),
                          tooltip: '删除',
                          onPressed: () => _confirmDelete(item),
                        ),
                      ],
                    ),
                    onTap: () => _showTagBooks(item),
                  ),
                );
              },
            ),
    );
  }

  Color _parseColor(String colorHex) {
    try {
      if (colorHex.startsWith('#')) {
        final hex = colorHex.substring(1);
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    return AppColors.tagColors[0];
  }

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    int selectedColorIndex = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('选择颜色:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: AppColors.tagColors.asMap().entries.map((e) {
                  final isSelected = e.key == selectedColorIndex;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColorIndex = e.key),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: e.value,
                        shape: BoxShape.circle,
                        border: isSelected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : null,
                      ),
                      child: isSelected
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final db = ref.read(databaseServiceProvider);
                final colorHex = Formatters.colorToHex(AppColors.tagColors[selectedColorIndex]);
                await db.createTag(name, color: colorHex);
                await _loadTags();
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(TagWithCount item) {
    final nameCtrl = TextEditingController(text: item.tag.name);
    int selectedColorIndex = AppColors.tagColors.indexWhere(
      (c) => Formatters.colorToHex(c) == Formatters.colorToHex(_parseColor(item.tag.color))
    );
    if (selectedColorIndex < 0) selectedColorIndex = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('编辑标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '标签名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text('选择颜色:'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: AppColors.tagColors.asMap().entries.map((e) {
                  final isSelected = e.key == selectedColorIndex;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColorIndex = e.key),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: e.value,
                        shape: BoxShape.circle,
                        border: isSelected
                          ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                          : null,
                      ),
                      child: isSelected
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(ctx);
                final db = ref.read(databaseServiceProvider);
                final colorHex = Formatters.colorToHex(AppColors.tagColors[selectedColorIndex]);
                await db.updateTag(item.tag.id!, name: name, color: colorHex);
                await _loadTags();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(TagWithCount item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除标签"${item.tag.name}"吗？\n这将移除它与 ${item.bookCount} 本小说的关联。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.deleteTag(item.tag.id!);
              await _loadTags();
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showTagBooks(TagWithCount item) {
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
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _parseColor(item.tag.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('${item.tag.name} (${item.bookCount}本)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: FutureBuilder<List<Book>>(
                future: ref.read(databaseServiceProvider).getBooksByTag(item.tag.id!),
                builder: (ctx, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final books = snapshot.data!;
                  if (books.isEmpty) {
                    return const Center(child: Text('无关联小说'));
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: books.length,
                    itemBuilder: (ctx, index) {
                      final book = books[index];
                      return ListTile(
                        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: book.author != null ? Text(book.author!) : null,
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
}

/// 标签及其关联书籍数
class TagWithCount {
  final Tag tag;
  final int bookCount;

  const TagWithCount({required this.tag, required this.bookCount});
}