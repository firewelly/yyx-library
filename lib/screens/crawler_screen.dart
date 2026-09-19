import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/book_source.dart';
import '../providers/database_provider.dart';
import '../services/book_source_store.dart';
import '../services/crawler_service.dart';
import '../theme/app_colors.dart';
import '../utils/platform_utils.dart';

/// 爬虫抓取页 —— 书源搜索 + 目录抓取 + 入库
class CrawlerScreen extends ConsumerStatefulWidget {
  const CrawlerScreen({super.key});

  @override
  ConsumerState<CrawlerScreen> createState() => _CrawlerScreenState();
}

class _CrawlerScreenState extends ConsumerState<CrawlerScreen> {
  final _searchCtrl = TextEditingController();
  final _engine = DartCrawlerEngine();
  List<BookSource> _sources = [];
  BookSource? _selectedSource;

  // 状态
  bool _searching = false;
  String? _error;
  List<CrawledBook> _results = [];

  // 爬取状态
  bool _crawling = false;
  double _progress = 0;
  String _status = '';
  bool _cancelRequested = false;

  /// 请求取消当前爬取（在下一章开始前生效）
  void _cancelCrawl() {
    setState(() => _cancelRequested = true);
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final store = BookSourceStore();
    await store.initialize();
    final sources = store.getEnabled();
    if (mounted) {
      setState(() {
        _sources = sources;
        if (sources.isNotEmpty) _selectedSource = sources.first;
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _searchCtrl.text.trim();
    final source = _selectedSource;
    if (keyword.isEmpty) {
      setState(() => _error = '请输入书名关键词');
      return;
    }
    if (source == null) {
      setState(() => _error = '没有可用书源，请先在设置中添加');
      return;
    }
    setState(() {
      _searching = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await _engine.searchBooks(source, keyword);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        if (results.isEmpty) _error = '未找到「$keyword」相关书籍';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = '搜索失败: $e';
      });
    }
  }

  /// 点击搜索结果:弹导入选项(新建/更新)
  Future<void> _onBookTap(CrawledBook book) async {
    final db = ref.read(databaseServiceProvider);
    // 查重:已有同名书?
    final existing = await db.findBookByTitleAndAuthor(book.title,
        author: book.author.isEmpty ? null : book.author);

    if (!mounted) return;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('《${book.title}》'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (book.author.isNotEmpty)
              Text('作者: ${book.author}', style: const TextStyle(fontSize: 13)),
            Text('来源: ${book.sourceName}', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            if (existing != null)
              Text(
                '⚠️ 书库已有《${existing.title}》，可选择更新章节',
                style: const TextStyle(color: AppColors.warning, fontSize: 13),
              )
            else
              const Text('将作为新书导入', style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          if (existing != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'update'),
              child: const Text('更新到已有书'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'new'),
            child: Text(existing != null ? '另建新书' : '导入'),
          ),
        ],
      ),
    );
    if (action == null || action == 'cancel' || !mounted) return;
    await _crawlBook(book, mode: action == 'update' ? 'update' : 'new');
  }

  /// 抓取目录 + 逐章正文 + 入库。
  ///
  /// - 更新模式（mode=update）：只抓取书库中尚不存在的章节（按章号判断），
  ///   已有 N 章的书追更时无需重抓全书
  /// - 单章抓取失败自动重试 1 次，仍失败则跳过并记录，最后汇总
  /// - 抓取过程中可随时取消；已抓取的章节仍会入库
  Future<void> _crawlBook(CrawledBook book, {required String mode}) async {
    final source = _selectedSource;
    if (source == null) return;

    setState(() {
      _crawling = true;
      _cancelRequested = false;
      _progress = 0;
      _status = '正在抓取目录...';
      _error = null;
    });

    try {
      final db = ref.read(databaseServiceProvider);

      // 1. 抓目录
      final toc = await _engine.fetchToc(source, book.url);
      if (toc.isEmpty) throw CrawlerException('目录为空');
      if (!mounted) return;

      // 2. 更新模式：过滤出库中没有的章节（增量抓取）
      var toFetch = toc;
      var existingCount = 0;
      if (mode == 'update') {
        final existing = await db.findBookByTitleAndAuthor(book.title,
            author: book.author.isEmpty ? null : book.author);
        if (existing != null) {
          final existingChapters = await db.getChapterList(existing.id!);
          existingCount = existingChapters.length;
          final existingNumbers = existingChapters.map((c) => c.chapterNumber).toSet();
          toFetch = toc.where((c) => !existingNumbers.contains(c.chapterNumber)).toList();
          setState(() {
            _status = '书库已有 $existingCount 章，本次抓取 ${toFetch.length} 个新章节';
          });
        }
      }
      if (toFetch.isEmpty) {
        setState(() {
          _crawling = false;
          _progress = 1.0;
          _status = '《${book.title}»目录无新增章节';
        });
        return;
      }

      // 3. 逐章抓正文（失败重试 1 次，仍失败跳过）
      final chapters = <CrawledChapterWithContent>[];
      final failed = <String>[];
      Object? lastError;
      for (int i = 0; i < toFetch.length; i++) {
        if (!mounted) return;
        if (_cancelRequested) break;
        setState(() {
          _progress = (i / toFetch.length).clamp(0.0, 0.9);
          _status = '抓取章节 ${i + 1}/${toFetch.length}: ${toFetch[i].title}';
        });
        String? content;
        for (int attempt = 0; attempt < 2 && content == null; attempt++) {
          try {
            content = await _engine.fetchChapterContent(source, toFetch[i].url);
          } catch (e) {
            lastError = e;
            // 失败后稍等再重试，避免连续打请求
            if (attempt == 0) await Future.delayed(const Duration(seconds: 2));
          }
        }
        if (content == null) {
          failed.add(toFetch[i].title);
          continue;
        }
        chapters.add(CrawledChapterWithContent(
          title: toFetch[i].title,
          url: toFetch[i].url,
          chapterNumber: toFetch[i].chapterNumber,
          content: content,
        ));
      }
      if (!mounted) return;

      // 全部失败或一开始就取消 → 不入库
      if (chapters.isEmpty) {
        setState(() {
          _crawling = false;
          _status = '';
          _error = _cancelRequested ? '已取消（未抓取到任何章节）' : '抓取失败: $lastError';
        });
        return;
      }

      // 4. 入库（取消时把已抓到的部分入库）
      setState(() {
        _progress = 0.95;
        _status = '正在写入书库...';
      });
      final importer = CrawlImporter(ref.read(databaseServiceProvider));
      final result = await importer.importChapters(
        title: book.title,
        author: book.author.isEmpty ? null : book.author,
        bookUrl: book.url,
        sourceName: source.name,
        chapters: chapters,
      );
      if (!mounted) return;

      final skippedNote = failed.isEmpty
          ? ''
          : '（${failed.length} 章抓取失败已跳过: ${failed.take(3).join('、')}${failed.length > 3 ? ' 等' : ''}）';
      setState(() {
        _crawling = false;
        _progress = 1.0;
        _status = '${_cancelRequested ? '已取消，' : ''}${result.message}$skippedNote';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.message}$skippedNote')),
      );
      // 跳转书籍详情
      context.go('/book/${result.bookId}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _crawling = false;
        _error = '爬取失败: $e';
        _status = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('🕷️ 爬虫抓取')),
      body: Column(
        children: [
          // 搜索区
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 书源选择
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<BookSource>(
                        initialValue: _selectedSource,
                        decoration: const InputDecoration(
                          labelText: '书源',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _sources.map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (v) => setState(() => _selectedSource = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 关键词
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: '输入书名或关键词...',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _searching
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.search),
                                  onPressed: _search,
                                ),
                        ),
                        onSubmitted: (_) => _search(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _searching ? null : _search,
                      child: const Text('搜索'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),

          // Web 端 CORS 提示
          if (PlatformUtils.isWeb)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: AppColors.warning),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Web 端受浏览器跨域(CORS)限制，多数小说站无法直接抓取；抓取功能建议使用桌面端。',
                      style: TextStyle(fontSize: 12, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),

          // 爬取进度区
          if (_crawling)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(_status,
                            style: const TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      TextButton.icon(
                        onPressed: _cancelRequested ? null : _cancelCrawl,
                        icon: const Icon(Icons.stop_circle_outlined, size: 16),
                        label: Text(_cancelRequested ? '正在取消...' : '取消'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // 搜索结果
          Expanded(
            child: _results.isEmpty
                ? _buildEmpty(theme)
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (ctx, i) {
                      final book = _results[i];
                      return ListTile(
                        leading: const Icon(Icons.menu_book, color: AppColors.seedColor),
                        title: Text(book.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          book.author.isEmpty
                              ? book.sourceName
                              : '${book.author} · ${book.sourceName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _crawling
                            ? null
                            : const Icon(Icons.download, size: 20),
                        onTap: _crawling ? null : () => _onBookTap(book),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.travel_explore,
              size: 64, color: theme.colorScheme.outlineVariant),
          const SizedBox(height: 12),
          const Text('输入书名搜索，点击结果即可抓取入库',
              style: TextStyle(color: AppColors.hintText)),
          const SizedBox(height: 8),
          const Text('支持: 书源规则驱动的静态小说站',
              style: TextStyle(color: AppColors.hintText, fontSize: 12)),
        ],
      ),
    );
  }
}
