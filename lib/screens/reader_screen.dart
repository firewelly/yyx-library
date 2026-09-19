import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/models.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/database_provider.dart';
import '../theme/app_colors.dart';
import '../theme/reader_themes.dart';
import '../utils/constants.dart';
import '../utils/zh_converter.dart';

/// 阅读器页面
class ReaderScreen extends ConsumerStatefulWidget {
  final int bookId;
  final int? initialChapterId;

  const ReaderScreen({super.key, required this.bookId, this.initialChapterId});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 监听滚动位置变化，更新 Provider
    _scrollController.addListener(_onScroll);
    Future.microtask(() {
      ref.read(readerProvider.notifier)
          .openBook(widget.bookId, initialChapterId: widget.initialChapterId);
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      ref.read(readerProvider.notifier).updateScrollPosition(_scrollController.offset.toInt());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    // 保存阅读进度后再关闭
    ref.read(readerProvider.notifier).saveProgress();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(readerProvider);
    final settings = ref.watch(settingsProvider);

    if (state.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (state.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错误')),
        body: Center(child: Text(state.error!)),
      );
    }

    if (state.currentChapter == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('无章节')),
        body: const Center(child: Text('该小说暂无章节内容')),
      );
    }

    final chapter = state.currentChapter!;
    final rTheme = readerThemeById(settings.settings.readerTheme);

    // 繁简显示转换（词典未就绪时先按原文渲染，加载完成后自动刷新）
    final zhVariant = settings.settings.readerZhVariant;
    if (zhVariant != 'original' && !ZhConverter.instance.isLoaded) {
      ZhConverter.instance.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
    final displayTitle = _convertZh(chapter.title, zhVariant);
    final displayContent = _convertZh(chapter.content, zhVariant);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // 左右方向键翻页
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (state.hasPrevious) {
            ref.read(readerProvider.notifier).previousChapter();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (state.hasNext) {
            ref.read(readerProvider.notifier).nextChapter();
          }
        },
        // Ctrl+加/减 调整字号
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
          final newSize = (settings.settings.fontSize + AppConstants.fontSizeStep)
              .clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
          ref.read(settingsProvider.notifier).setFontSize(newSize);
        },
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
          final newSize = (settings.settings.fontSize - AppConstants.fontSizeStep)
              .clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
          ref.read(settingsProvider.notifier).setFontSize(newSize);
        },
      },
      child: Scaffold(
        backgroundColor: rTheme.background,
        appBar: AppBar(
          backgroundColor: rTheme.surface,
          foregroundColor: rTheme.text,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回目录',
            onPressed: () => context.go('/book/${widget.bookId}'),
          ),
          title: Text(displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: rTheme.text)),
          actions: [
            // 目录
            IconButton(
              icon: Icon(Icons.format_list_numbered, color: rTheme.accent),
              tooltip: '目录',
              onPressed: () => _showToc(context),
            ),
            // 繁简显示切换
            PopupMenuButton<String>(
              icon: Icon(Icons.translate, color: rTheme.accent),
              tooltip: '繁简切换',
              onSelected: (v) =>
                  ref.read(settingsProvider.notifier).setReaderZhVariant(v),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'original', child: Text('显示原文')),
                const PopupMenuItem(value: 'simplified', child: Text('转换为简体')),
                const PopupMenuItem(value: 'traditional', child: Text('转换为繁体')),
              ],
            ),
            // 章节搜索
            IconButton(
              icon: Icon(Icons.search, color: rTheme.accent),
              tooltip: '章节搜索',
              onPressed: () => _showChapterSearch(context),
            ),
            // 添加书签
            IconButton(
              icon: Icon(Icons.bookmark_border, color: rTheme.accent),
              tooltip: '添加书签',
              onPressed: () => _addBookmark(context),
            ),
            // 添加笔记
            IconButton(
              icon: Icon(Icons.note_add_outlined, color: rTheme.accent),
              tooltip: '添加笔记',
              onPressed: () => _addNote(context),
            ),
            // 阅读主题切换
            PopupMenuButton<String>(
              icon: Icon(Icons.palette_outlined, color: rTheme.accent),
              tooltip: '阅读主题',
              onSelected: (id) =>
                  ref.read(settingsProvider.notifier).setReaderTheme(id),
              itemBuilder: (ctx) => [
                for (final t in kReaderThemes)
                  PopupMenuItem(
                    value: t.id,
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: t.background,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: t.text, width: t.id == rTheme.id ? 3 : 1),
                          ),
                          child: t.id == rTheme.id
                              ? Icon(Icons.check,
                                  size: 12, color: t.text)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Text(t.name),
                      ],
                    ),
                  ),
              ],
            ),
            // 更多(字号/书签列表/笔记列表/返回书库)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: rTheme.text),
              tooltip: '更多',
              onSelected: (value) {
                switch (value) {
                  case 'home':
                    context.go('/');
                    break;
                  case 'bookmarks':
                    _showBookmarks(context);
                    break;
                  case 'notes':
                    _showNotes(context);
                    break;
                  case 'font_up':
                    final newSize = (settings.settings.fontSize +
                            AppConstants.fontSizeStep)
                        .clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
                    ref.read(settingsProvider.notifier).setFontSize(newSize);
                    break;
                  case 'font_down':
                    final newSize = (settings.settings.fontSize -
                            AppConstants.fontSizeStep)
                        .clamp(AppConstants.minFontSize, AppConstants.maxFontSize);
                    ref.read(settingsProvider.notifier).setFontSize(newSize);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'font_up', child: Text('放大字体')),
                const PopupMenuItem(value: 'font_down', child: Text('缩小字体')),
                const PopupMenuItem(value: 'bookmarks', child: Text('查看书签')),
                const PopupMenuItem(value: 'notes', child: Text('查看笔记')),
                const PopupMenuItem(value: 'home', child: Text('返回书库')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            // 导航栏（进度 + 上一章/下一章）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: rTheme.surface.withValues(alpha: 0.6),
                border: Border(bottom: BorderSide(color: rTheme.border)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '${state.currentIndex + 1}/${state.chapters.length}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: rTheme.secondaryText),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: state.hasPrevious
                            ? () => ref.read(readerProvider.notifier).previousChapter()
                            : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: const Text('上一章'),
                        style: TextButton.styleFrom(
                          foregroundColor: rTheme.accent,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: state.hasNext
                            ? () => ref.read(readerProvider.notifier).nextChapter()
                            : null,
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: const Text('下一章'),
                        iconAlignment: IconAlignment.end,
                        style: TextButton.styleFrom(
                          foregroundColor: rTheme.accent,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                  // 阅读进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: state.chapters.isEmpty
                          ? 0
                          : (state.currentIndex + 1) / state.chapters.length,
                      minHeight: 2,
                      backgroundColor: rTheme.border,
                      valueColor: AlwaysStoppedAnimation(rTheme.accent),
                    ),
                  ),
                ],
              ),
            ),
            // 内容区
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: settings.settings.marginSize,
                  vertical: 24,
                ),
                // 桌面端限制正文宽度 800 居中,提升长文本可读性
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 章节标题
                        Text(
                          displayTitle,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: rTheme.titleColor,
                              ),
                        ),
                        Divider(height: 24, color: rTheme.border),
                        // 章节内容
                        Text(
                          displayContent,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                fontSize: settings.settings.fontSize,
                                height: settings.settings.lineHeight,
                                color: rTheme.text,
                              ),
                        ),
                        const SizedBox(height: 48),
                        // 章尾导航
                        Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (state.hasPrevious)
                                OutlinedButton.icon(
                                  onPressed: () => ref.read(readerProvider.notifier).previousChapter(),
                                  icon: const Icon(Icons.chevron_left, size: 18),
                                  label: const Text('上一章'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: rTheme.accent,
                                    side: BorderSide(color: rTheme.accent.withValues(alpha: 0.5)),
                                  ),
                                ),
                              const SizedBox(width: 16),
                              if (state.hasNext)
                                FilledButton.icon(
                                  onPressed: () => ref.read(readerProvider.notifier).nextChapter(),
                                  icon: const Icon(Icons.chevron_right, size: 18),
                                  label: const Text('下一章'),
                                  iconAlignment: IconAlignment.end,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: rTheme.accent,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 添加书签
  void _addBookmark(BuildContext context) {
    final state = ref.read(readerProvider);
    if (state.currentChapter == null) return;

    final titleController = TextEditingController(
      text: '第${state.currentChapter!.chapterNumber}章 ${state.currentChapter!.title}',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加书签'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: '书签标题',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              final now = DateTime.now().toIso8601String();
              await db.createBookmark(Bookmark(
                bookId: widget.bookId,
                chapterId: state.currentChapter!.id!,
                title: titleController.text.trim().isNotEmpty
                    ? titleController.text.trim()
                    : null,
                createdAt: now,
              ));
              // 刷新阅读器数据
              unawaited(ref.read(readerProvider.notifier).openBook(widget.bookId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('书签已添加')),
                );
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 添加笔记
  void _addNote(BuildContext context) {
    final state = ref.read(readerProvider);
    if (state.currentChapter == null) return;

    final contentController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加笔记'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: contentController,
            decoration: const InputDecoration(
              labelText: '笔记内容',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            maxLines: 8,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final content = contentController.text.trim();
              if (content.isEmpty) return;
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              final now = DateTime.now().toIso8601String();
              await db.createNote(Note(
                bookId: widget.bookId,
                chapterId: state.currentChapter!.id!,
                content: content,
                createdAt: now,
                updatedAt: now,
              ));
              unawaited(ref.read(readerProvider.notifier).openBook(widget.bookId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('笔记已添加')),
                );
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  /// 显示章节目录
  /// 按设置的繁简变体转换显示文本（词典未就绪或「原文」时原样返回）
  String _convertZh(String text, String variant) {
    if (variant == 'original' || text.isEmpty) return text;
    final converter = ZhConverter.instance;
    if (!converter.isLoaded) return text;
    return variant == 'simplified'
        ? converter.toSimplified(text)
        : converter.toTraditional(text);
  }

  void _showToc(BuildContext context) {
    final state = ref.read(readerProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('目录（共 ${state.chapters.length} 章）', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: state.chapters.length,
                itemBuilder: (_, index) {
                  final ch = state.chapters[index];
                  final isCurrent = ch.id == state.currentChapter?.id;
                  final cs = Theme.of(context).colorScheme;
                  return ListTile(
                    dense: true,
                    selected: isCurrent,
                    selectedTileColor: cs.primaryContainer.withValues(alpha: 0.4),
                    leading: Text(
                      '${ch.chapterNumber}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    title: Text(
                      ch.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                        color: isCurrent ? cs.primary : null,
                      ),
                    ),
                    trailing: isCurrent
                        ? Icon(Icons.menu_book, size: 16, color: cs.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      ref.read(readerProvider.notifier).goToChapter(ch.id!);
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

  /// 章节内搜索（在本书所有章节的标题与正文中检索关键词）
  void _showChapterSearch(BuildContext context) {
    final queryController = TextEditingController();
    // 用 StatefulBuilder 让弹窗内部可以局部刷新搜索结果
    List<Map<String, dynamic>> results = [];
    bool searching = false;

    Future<void> doSearch(StateSetter setState, String q) async {
      if (q.trim().isEmpty) {
        setState(() => results = []);
        return;
      }
      setState(() => searching = true);
      try {
        final db = ref.read(databaseServiceProvider);
        final hits = await db.searchChapters(widget.bookId, q.trim());
        setState(() => results = hits);
      } catch (_) {
        // 忽略，保留上次结果
      } finally {
        setState(() => searching = false);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('章节搜索'),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: queryController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '搜索本书章节标题与正文...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: queryController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                queryController.clear();
                                setState(() => results = []);
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (v) => doSearch(setState, v),
                    onChanged: (v) => setState(() {}), // 刷新清除按钮
                  ),
                  const SizedBox(height: 8),
                  if (searching)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (results.isEmpty && queryController.text.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('未找到匹配的章节', style: Theme.of(context).textTheme.bodySmall),
                    )
                  else if (results.isNotEmpty)
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final r = results[i];
                          final cs = Theme.of(context).colorScheme;
                          return ListTile(
                            dense: true,
                            leading: Text(
                              '${r['chapterNumber']}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            title: Text(
                              r['title']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: r['context'] != null && (r['context'] as String).isNotEmpty
                                ? Text(
                                    r['context'].toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                  )
                                : null,
                            onTap: () {
                              final id = r['id'];
                              if (id == null) return;
                              Navigator.pop(ctx);
                              ref.read(readerProvider.notifier).goToChapter(id as int);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () => doSearch(setState, queryController.text),
                child: const Text('搜索'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 显示书签列表
  void _showBookmarks(BuildContext context) {
    final state = ref.read(readerProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('书签列表', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: state.bookmarks.isEmpty
                  ? const Center(child: Text('暂无书签'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: state.bookmarks.length,
                      itemBuilder: (_, index) {
                        final bm = state.bookmarks[index];
                        return ListTile(
                          leading: const Icon(Icons.bookmark, color: AppColors.ratingStar),
                          title: Text(bm.title ?? '未命名书签'),
                          subtitle: Text(
                            bm.chapterTitle != null
                                ? '第${bm.chapterNumber ?? "?"}章 ${bm.chapterTitle}'
                                : '',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final db = ref.read(databaseServiceProvider);
                              await db.deleteBookmark(bm.id!);
                              unawaited(ref.read(readerProvider.notifier).openBook(widget.bookId));
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            ref.read(readerProvider.notifier).goToChapter(bm.chapterId);
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

  /// 显示笔记列表
  void _showNotes(BuildContext context) {
    final state = ref.read(readerProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.8,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text('笔记列表', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: state.notes.isEmpty
                  ? const Center(child: Text('暂无笔记'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: state.notes.length,
                      itemBuilder: (_, index) {
                        final note = state.notes[index];
                        return ListTile(
                          leading: const Icon(Icons.sticky_note_2, color: AppColors.info),
                          title: Text(
                            note.content.length > 60
                                ? '${note.content.substring(0, 60)}...'
                                : note.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            note.chapterTitle != null
                                ? '第${note.chapterNumber ?? "?"}章 ${note.chapterTitle}'
                                : '',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final db = ref.read(databaseServiceProvider);
                              await db.deleteNote(note.id!);
                              unawaited(ref.read(readerProvider.notifier).openBook(widget.bookId));
                            },
                          ),
                          onTap: () => _showEditNote(context, note),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑笔记
  void _showEditNote(BuildContext context, Note note) {
    final controller = TextEditingController(text: note.content);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑笔记'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            maxLines: 8,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.updateNote(note.copyWith(content: controller.text.trim()));
              unawaited(ref.read(readerProvider.notifier).openBook(widget.bookId));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
