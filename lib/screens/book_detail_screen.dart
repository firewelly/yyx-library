import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../models/models.dart';
import '../providers/database_provider.dart';
import '../providers/library_provider.dart';
import '../providers/settings_provider.dart';
import '../services/export_service.dart';
import '../widgets/generated_cover.dart';
import '../services/platform_fs.dart';
import '../theme/app_colors.dart';
import '../utils/book_path.dart';
import '../utils/formatters.dart';
import '../utils/platform_utils.dart';
import '../utils/web_launcher.dart';

/// 书籍详情页
class BookDetailScreen extends ConsumerStatefulWidget {
  final int bookId;

  const BookDetailScreen({super.key, required this.bookId});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  Book? _book;
  List<Chapter>? _chapters;
  ReadingProgress? _progress;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  Future<void> _loadBook() async {
    final db = ref.read(databaseServiceProvider);
    final book = await db.getBook(widget.bookId);
    // 章节目录只需标题和序号，使用轻量加载
    final chapters = await db.getChapterList(widget.bookId);
    // 读取阅读进度(用于「继续阅读」恢复)
    final progress = await db.getProgress(widget.bookId);
    if (mounted) {
      setState(() {
        _book = book;
        _chapters = chapters;
        _progress = progress;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('错误')),
        body: const Center(child: Text('书籍不存在')),
      );
    }

    final book = _book!;
    final chapters = _chapters ?? [];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '返回书库',
          onPressed: () => context.go('/'),
        ),
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.edit), tooltip: '编辑', onPressed: () => _showEditDialog(context)),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: '删除',
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GeneratedCover(
                          title: book.title,
                          width: 84,
                          height: 116,
                          fontSize: 38,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(book.title,
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 12,
                                children: [
                                  if (book.author != null && book.author!.isNotEmpty)
                                    Text('👤 ${book.author}', style: theme.textTheme.bodyMedium),
                                  Text('📊 ${book.status}', style: theme.textTheme.bodyMedium),
                                  Text('📄 ${chapters.length} 章', style: theme.textTheme.bodyMedium),
                                  Text('📝 ${Formatters.formatWordCount(book.wordCount)}', style: theme.textTheme.bodyMedium),
                                  if (book.sourceFormat != null && book.sourceFormat!.isNotEmpty)
                                    Text('📦 ${book.sourceFormat}', style: theme.textTheme.bodyMedium),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 来源网址（爬虫入库时记录的书籍页面 URL）
                    if (book.sourceUrl != null && book.sourceUrl!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => _openUrl(book.sourceUrl!),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.link, size: 14, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                book.sourceUrl!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // 文件路径（本地导入时记录；相对存储时按本机书库根目录解析展示）
                    if (book.filePath != null && book.filePath!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.folder_open, size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              PlatformFs.nativeSeparators(BookPath.resolve(
                                  book.filePath!,
                                  PlatformFs.effectiveLibraryRoot(ref
                                      .watch(settingsProvider)
                                      .settings
                                      .libraryRootPath))),
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (book.summary != null && book.summary!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
                        child: Text(book.summary!, style: theme.textTheme.bodySmall),
                      ),
                    ],
                    const SizedBox(height: 12),
                    // 标签
                    Row(
                      children: [
                        Text('标签: ', style: theme.textTheme.bodyMedium),
                        const SizedBox(width: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            ...book.tags.map((tag) => Chip(
                              label: Text(tag.name, style: const TextStyle(fontSize: 11)),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onDeleted: () => _removeTag(tag.id!),
                            )),
                            ActionChip(
                              avatar: const Icon(Icons.add, size: 14),
                              label: const Text('添加', style: TextStyle(fontSize: 11)),
                              onPressed: () => _addTag(context),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 评分（可交互）
                    Row(
                      children: [
                        Text('评分: ', style: theme.textTheme.bodyMedium),
                        ...List.generate(5, (i) => IconButton(
                          icon: Icon(
                            i < book.rating ? Icons.star : Icons.star_border,
                            size: 22,
                            color: i < book.rating ? AppColors.ratingStar : AppColors.emptyState,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => _setRating(i + 1),
                        )),
                        if (book.rating > 0)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 14, color: AppColors.hintText),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            tooltip: '清除评分',
                            onPressed: () => _setRating(0),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 操作按钮
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // 有阅读进度时显示「继续阅读」并携带进度百分比
                        if (_progress != null && _chapters != null && _chapters!.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () => context.go(
                              '/reader/${book.id}?chapterId=${_progress!.chapterId}',
                            ),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text(
                              '继续阅读 ${_progressPercent(_progress!)}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => context.go('/reader/${book.id}'),
                            icon: const Icon(Icons.menu_book, size: 18),
                            label: const Text('开始阅读'),
                          ),
                        // 导出菜单(TXT/EPUB/PDF/Kindle)
                        PopupMenuButton<String>(
                          tooltip: '导出',
                          onSelected: (value) => _export(book, value),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'txt', child: Row(children: [
                              Icon(Icons.description, size: 18), SizedBox(width: 8), Text('导出 TXT'),
                            ])),
                            PopupMenuItem(value: 'epub', child: Row(children: [
                              Icon(Icons.menu_book, size: 18), SizedBox(width: 8), Text('导出 EPUB'),
                            ])),
                            PopupMenuItem(value: 'pdf', child: Row(children: [
                              Icon(Icons.picture_as_pdf, size: 18), SizedBox(width: 8), Text('导出 PDF'),
                            ])),
                            PopupMenuItem(value: 'mobi', child: Row(children: [
                              Icon(Icons.tablet_mac, size: 18), SizedBox(width: 8), Text('导出 Kindle'),
                            ])),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Theme.of(context).colorScheme.outline),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download, size: 18),
                                SizedBox(width: 6),
                                Text('导出', style: TextStyle(fontWeight: FontWeight.w600)),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
const SizedBox(height: 16),
            // 章节目录
            Row(
              children: [
                Expanded(
                  child: Text('📑 章节目录（共 ${chapters.length} 章）',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.search, size: 20),
                  tooltip: '章节搜索',
                  onPressed: () => _showChapterSearch(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 响应式网格：根据宽度动态调整列数
            LayoutBuilder(
              builder: (layoutContext, constraints) {
                // 根据宽度计算列数：每150px一列，最少2列，最多8列
                final crossAxisCount = (constraints.maxWidth / 150).floor().clamp(2, 8);
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 2.5,  // 更紧凑的高度
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 6,
                  ),
                  itemCount: chapters.length,
                  itemBuilder: (gridContext, index) {
                    final chapter = chapters[index];
                    return FilledButton.tonal(
                      onPressed: () => context.go('/reader/${book.id}?chapterId=${chapter.id}'),
                      onLongPress: () => _showChapterMenu(context, chapter),
                      child: Text(
                        '第${chapter.chapterNumber}章 ${chapter.title}',
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 计算阅读进度百分比(基于章节索引)
  String _progressPercent(ReadingProgress progress) {
    final chapters = _chapters ?? [];
    if (chapters.isEmpty) return '';
    final index = chapters.indexWhere((c) => c.id == progress.chapterId);
    if (index < 0) return '';
    final percent = ((index + 1) / chapters.length * 100).round();
    return '$percent%';
  }

  /// 用系统默认浏览器/新标签页打开 URL（桌面端 Process，Web 端 window.open）
  Future<void> _openUrl(String url) => WebLauncher.openUrl(url);

  /// 设置评分
  Future<void> _setRating(int rating) async {
    final db = ref.read(databaseServiceProvider);
    await db.updateBook(_book!.copyWith(rating: rating));
    await _loadBook();
  }

  /// 导出书籍
  Future<void> _export(Book book, String format) async {
    try {
      final db = ref.read(databaseServiceProvider);
      final exportService = ExportService(db);

      // Web 端：无目录概念，直接触发浏览器下载
      if (PlatformUtils.isWeb) {
        final fileName = await exportService.exportDownload(book.id!, format);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已开始下载: $fileName')),
          );
        }
        return;
      }

      final outputDir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择导出目录',
      );
      if (outputDir == null) return;

      String filePath;

      if (format == 'txt') {
        filePath = await exportService.exportToTxt(book.id!, outputDir);
      } else {
        filePath = await exportService.exportToEpub(book.id!, outputDir);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出成功: $filePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 显示编辑对话框
  void _showEditDialog(BuildContext context) {
    final titleCtrl = TextEditingController(text: _book!.title);
    final authorCtrl = TextEditingController(text: _book!.author ?? '');
    final summaryCtrl = TextEditingController(text: _book!.summary ?? '');
    String status = _book!.status;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑书籍'),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: '书名', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: authorCtrl,
                  decoration: const InputDecoration(labelText: '作者', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: '状态', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: '连载中', child: Text('连载中')),
                    DropdownMenuItem(value: '已完结', child: Text('已完结')),
                  ],
                  onChanged: (v) => status = v ?? status,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: summaryCtrl,
                  decoration: const InputDecoration(labelText: '简介', border: OutlineInputBorder()),
                  maxLines: 4,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.updateBook(_book!.copyWith(
                title: titleCtrl.text.trim(),
                author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
                status: status,
                summary: summaryCtrl.text.trim().isEmpty ? null : summaryCtrl.text.trim(),
              ));
              await _loadBook();
              // 刷新书库列表
              unawaited(ref.read(libraryProvider.notifier).refresh());
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 添加标签
  void _addTag(BuildContext context) {
    final db = ref.read(databaseServiceProvider);

    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<Tag>>(
        future: db.getAllTags(),
        builder: (ctx, snapshot) {
          final allTags = snapshot.data ?? [];
          final existingTagNames = _book!.tags.map((t) => t.name).toSet();
          final availableTags = allTags.where((t) => !existingTagNames.contains(t.name)).toList();

          return AlertDialog(
            title: const Text('添加标签'),
            content: SizedBox(
              width: 350,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 创建新标签
                  _CreateTagTile(
                    onCreated: (tagId) async {
                      await db.addTagToBook(widget.bookId, tagId);
                      await _loadBook();
                      if (context.mounted) Navigator.pop(context);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('已有标签:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  // 可选标签列表
                  ...availableTags.map((tag) => ListTile(
                    dense: true,
                    title: Text(tag.name),
                    trailing: const Icon(Icons.add, size: 16),
                    onTap: () async {
                      await db.addTagToBook(widget.bookId, tag.id!);
                      await _loadBook();
                      if (context.mounted) Navigator.pop(context);
                    },
                  )),
                  if (availableTags.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('没有更多标签可用', style: TextStyle(color: AppColors.hintText, fontSize: 12)),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 移除标签
  Future<void> _removeTag(int tagId) async {
    final db = ref.read(databaseServiceProvider);
    await db.removeTagFromBook(widget.bookId, tagId);
    await _loadBook();
  }

  /// 章节搜索（在本书所有章节的标题与正文中检索，点击结果跳转阅读器）
  /// 与阅读器内的章节搜索共用 searchChapters（自动匹配简繁）
  void _showChapterSearch(BuildContext context) {
    final queryController = TextEditingController();
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
                      hintText: '搜索本书章节标题与正文（简繁同搜）...',
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
                              Navigator.pop(ctx);
                              context.go('/reader/${widget.bookId}?chapterId=${r['id']}');
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
            ],
          ),
        );
      },
    );
  }

  /// 章节长按菜单（编辑/删除）
  void _showChapterMenu(BuildContext context, Chapter chapter) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '第${chapter.chapterNumber}章 ${chapter.title}',
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑章节标题'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditChapterDialog(context, chapter);
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('阅读此章'),
              onTap: () {
                Navigator.pop(ctx);
                context.go('/reader/${widget.bookId}?chapterId=${chapter.id}');
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
              title: Text('删除章节', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteChapter(context, chapter);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 编辑章节标题
  void _showEditChapterDialog(BuildContext context, Chapter chapter) {
    final titleCtrl = TextEditingController(text: chapter.title);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑章节标题'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(
            labelText: '章节标题',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final newTitle = titleCtrl.text.trim();
              if (newTitle.isEmpty) return;
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.updateChapter(chapter.copyWith(title: newTitle));
              await _loadBook();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 确认删除章节
  void _confirmDeleteChapter(BuildContext context, Chapter chapter) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除章节'),
        content: Text('确定要删除"第${chapter.chapterNumber}章 ${chapter.title}"吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.deleteChapter(chapter.id!);
              await _loadBook();
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除《${_book!.title}》吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.deleteBook(widget.bookId);
              unawaited(ref.read(libraryProvider.notifier).refresh());
              if (mounted && context.mounted) context.go('/');
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 创建新标签的 Widget
class _CreateTagTile extends ConsumerStatefulWidget {
  final Future<void> Function(int tagId) onCreated;
  const _CreateTagTile({required this.onCreated});

  @override
  ConsumerState<_CreateTagTile> createState() => _CreateTagTileState();
}

class _CreateTagTileState extends ConsumerState<_CreateTagTile> {
  final _controller = TextEditingController();
  bool _isCreating = false;
  int _selectedColorIndex = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedColor = AppColors.tagColors[_selectedColorIndex];
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: '输入新标签名...',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (_) => _create(),
          ),
        ),
        const SizedBox(width: 8),
        // 颜色选择器
        GestureDetector(
          onTap: _showColorPicker,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: selectedColor,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
            ),
            child: const Icon(Icons.palette, size: 16, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.tonal(
          onPressed: _isCreating ? null : _create,
          child: const Text('创建'),
        ),
      ],
    );
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择标签颜色'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: AppColors.tagColors.asMap().entries.map((e) {
            final isSelected = e.key == _selectedColorIndex;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedColorIndex = e.key);
                Navigator.pop(ctx);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: e.value,
                  shape: BoxShape.circle,
                  border: isSelected
                    ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                    : null,
                ),
                child: isSelected
                  ? const Icon(Icons.check, size: 20, color: Colors.white)
                  : null,
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    setState(() => _isCreating = true);
    try {
      final db = ref.read(databaseServiceProvider);
      final colorHex = Formatters.colorToHex(AppColors.tagColors[_selectedColorIndex]);
      final tag = await db.createTag(name, color: colorHex);
      await widget.onCreated(tag.id!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }
}
