import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/book_source.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../utils/html_text.dart';
import '../utils/text_decode.dart';
import 'database_service.dart';

/// 爬取进度回调
typedef CrawlProgressCallback = void Function(
  int current, int total, String chapterTitle);

/// 通用书源爬虫引擎(Dart 实现)
///
/// 由 JSON 书源规则驱动,负责:
/// - 搜索书籍([searchBooks])
/// - 抓取目录([fetchToc])
/// - 抓取章节正文([fetchChapterContent])
///
/// 仅支持静态 HTML 网站。SPA 动态站(Playwright)预留
/// [CrawlerEngine] 抽象接口,未来通过本地服务扩展。
abstract class CrawlerEngine {
  /// 按关键词搜索书籍
  Future<List<CrawledBook>> searchBooks(BookSource source, String keyword);

  /// 抓取目录页,返回章节列表
  Future<List<CrawledChapter>> fetchToc(BookSource source, String bookUrl);

  /// 抓取单章正文(纯文本,已清洗)
  Future<String> fetchChapterContent(BookSource source, String chapterUrl);
}

/// Dart 书源爬虫实现(静态 HTML 站)
class DartCrawlerEngine implements CrawlerEngine {
  final Dio _dio;
  final Duration _minInterval;
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  static const _userAgents = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
  ];
  int _uaIndex = 0;

  DartCrawlerEngine({
    Dio? dio,
    Duration minInterval = const Duration(milliseconds: 600),
  })  : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: true,
              maxRedirects: 5,
            )),
        _minInterval = minInterval;

  /// 限速 + UA 轮换
  Future<Response<List<int>>> _fetchBytes(String url) async {
    // 限速
    final wait = _minInterval - (DateTime.now().difference(_lastRequest));
    if (wait > Duration.zero) {
      await Future.delayed(wait);
    }
    _lastRequest = DateTime.now();

    final ua = _userAgents[_uaIndex++ % _userAgents.length];
    final resp = await _dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {
          'User-Agent': ua,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': 'https://www.zzxx.org/',
        },
      ),
    );
    if (resp.statusCode != 200) {
      throw CrawlerException('请求失败 HTTP ${resp.statusCode}: $url');
    }
    return resp;
  }

  /// 抓取并解码网页(自动探测编码)
  Future<String> _fetchText(String url) async {
    final resp = await _fetchBytes(url);
    return TextDecode.decode(Uint8List.fromList(resp.data ?? const []));
  }

  /// 解析 DOM 文档
  Future<dom.Document> _fetchDom(String url) async {
    final html = await _fetchText(url);
    return html_parser.parse(html);
  }

  /// 解析选择器规则:`css选择器@属性` 或裸属性名(如 `href`、`title`)。
  ///
  /// - `text`(或缺省):取元素文本
  /// - `a@href`:取 a 元素的 href 属性
  /// - `href`(裸属性名):直接取元素 href 属性
  /// - `a`(裸 CSS 选择器):取匹配元素的文本
  static const _commonAttrs = {'href', 'title', 'src', 'alt', 'data-src'};

  String _extractByRule(dom.Element element, String rule) {
    var css = rule.trim();
    String attr = 'text';
    final at = css.lastIndexOf('@');
    if (at > 0 && at == css.length - 1) {
      // 尾部 @ 无属性名 → 视为 text
      css = css.substring(0, at).trim();
    } else if (at > 0) {
      attr = css.substring(at + 1).trim();
      css = css.substring(0, at).trim();
    }

    // 规则为空 → 取元素文本
    if (css.isEmpty) return element.text.trim();

    // 裸属性名 → 取元素该属性
    if (_commonAttrs.contains(css.toLowerCase())) {
      return element.attributes[css]?.trim() ?? '';
    }

    // 显式 text → 元素文本
    if (css.toLowerCase() == 'text') {
      return element.text.trim();
    }

    // 否则作为 CSS 选择器定位目标
    final target = element.querySelector(css);
    if (target == null) return '';
    if (attr == 'text') {
      return target.text.trim();
    }
    return target.attributes[attr]?.trim() ?? '';
  }

  /// 拼接相对 URL 为绝对 URL
  String _absolutize(String base, String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) {
      final uri = Uri.parse(base);
      return '${uri.scheme}://${uri.host}$u';
    }
    // 相对路径:取 base 的目录
    final uri = Uri.parse(base);
    final dir = uri.path.substring(0, uri.path.lastIndexOf('/') + 1);
    return '${uri.scheme}://${uri.host}$dir$u';
  }

  /// 替换 URL 模板占位符
  String _fillTemplate(String template, Map<String, String> vars) {
    var out = template;
    vars.forEach((k, v) => out = out.replaceAll('{{$k}}', v));
    return out;
  }

  @override
  Future<List<CrawledBook>> searchBooks(BookSource source, String keyword) async {
    final search = source.search;
    if (search == null) {
      throw CrawlerException('书源「${source.name}」不支持搜索');
    }
    final url = _fillTemplate(search.url, {
      'key': Uri.encodeComponent(keyword),
      'baseUrl': source.baseUrl,
    });
    final doc = await _fetchDom(url);

    final results = <CrawledBook>[];
    final rows = doc.querySelectorAll(search.listSelector);
    for (final row in rows) {
      final title = _extractByRule(row, search.title);
      final bookUrl = _extractByRule(row, search.urlRule);
      final author = search.author.isEmpty ? '' : _extractByRule(row, search.author);
      if (title.isEmpty || bookUrl.isEmpty) continue;
      results.add(CrawledBook(
        title: title,
        author: author,
        url: _absolutize(source.baseUrl, bookUrl),
        sourceName: source.name,
      ));
    }
    return results;
  }

  @override
  Future<List<CrawledChapter>> fetchToc(BookSource source, String bookUrl) async {
    final toc = source.toc;
    final url = _fillTemplate(toc.url, {
      'bookUrl': bookUrl,
      'baseUrl': source.baseUrl,
    });
    final doc = await _fetchDom(url);

    final chapters = <CrawledChapter>[];
    final links = doc.querySelectorAll(toc.listSelector);
    int number = 1;
    for (final link in links) {
      final title = _extractByRule(link, toc.title);
      final chapterUrl = _extractByRule(link, toc.urlRule);
      if (title.isEmpty || chapterUrl.isEmpty) continue;
      chapters.add(CrawledChapter(
        title: title,
        url: _absolutize(url, chapterUrl),
        chapterNumber: number++,
      ));
    }
    return chapters;
  }

  @override
  Future<String> fetchChapterContent(BookSource source, String chapterUrl) async {
    final html = await _fetchText(chapterUrl);
    final doc = html_parser.parse(html);

    // 取正文容器
    final selector = source.content.selector.trim();
    final contentNode = selector.isEmpty
        ? doc.body
        : doc.querySelector(selector);
    if (contentNode == null) {
      throw CrawlerException('正文提取失败(选择器: $selector)');
    }

    // HTML → 纯文本(保留段落)
    var text = HtmlText.stripHtml(contentNode.innerHtml,
        preserveParagraphs: true);

    // 应用清洗规则(广告行/URL/水印行)
    for (final pattern in source.content.cleanPatterns) {
      text = text.replaceAll(RegExp(pattern, multiLine: true), '');
    }

    // 折叠多余空行
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return text;
  }
}

/// 爬虫异常
class CrawlerException implements Exception {
  final String message;
  CrawlerException(this.message);

  @override
  String toString() => message;
}

/// 爬取入库结果
class CrawlImportResult {
  final bool isNewBook;
  final int bookId;
  final String bookTitle;
  final int chapterCount;
  final int addedCount;
  final int updatedCount;

  const CrawlImportResult({
    required this.isNewBook,
    required this.bookId,
    required this.bookTitle,
    required this.chapterCount,
    this.addedCount = 0,
    this.updatedCount = 0,
  });

  String get message {
    if (isNewBook) return '成功导入《$bookTitle》，共 $chapterCount 章';
    if (addedCount + updatedCount == 0) return '《$bookTitle》无变化，跳过';
    return '《$bookTitle》已更新：新增 $addedCount 章，更新 $updatedCount 章';
  }
}

/// 爬取内容入库 —— 复用数据库的建书/追更模式
///
/// 与 [ImportService] 的事务建书、按章号追更逻辑一致:
/// - 新书:单事务创建 Book + 逐章 createChapter,失败整体回滚
/// - 已有书:按 chapterNumber 匹配,内容变化更新、新章节追加
/// - 去重:按标题+作者查重
class CrawlImporter {
  final DatabaseService _db;

  CrawlImporter(this._db);

  /// 入库爬取的章节。
  ///
  /// [chapters] 为已抓取正文的章节(标题+内容+URL)。
  /// [onProgress] 可选进度回调(current, total)。
  Future<CrawlImportResult> importChapters({
    required String title,
    required String? author,
    required String bookUrl,
    required String sourceName,
    required List<CrawledChapterWithContent> chapters,
    CrawlProgressCallback? onProgress,
  }) async {
    if (chapters.isEmpty) {
      throw CrawlerException('没有可导入的章节');
    }

    // 去重:查已有书籍
    final existing =
        await _db.findBookByTitleAndAuthor(title, author: author);
    final now = DateTime.now().toIso8601String();

    if (existing != null) {
      // ===== 追更路径 =====
      final existingChapters = await _db.getChapterList(existing.id!);
      final existingByNumber = {
        for (var ch in existingChapters) ch.chapterNumber: ch
      };

      int added = 0;
      int updated = 0;
      for (int i = 0; i < chapters.length; i++) {
        final newCh = chapters[i];
        final old = existingByNumber[newCh.chapterNumber];
        if (old != null) {
          // 返回值：-1 不存在 / 0 无变化 / >0 已更新（旧内容长度）
          final oldLength =
              await _db.updateChapterContent(old.id!, newCh.content);
          if (oldLength > 0) updated++;
        } else {
          await _db.createChapter(Chapter(
            bookId: existing.id!,
            chapterNumber: newCh.chapterNumber,
            originalOrder: newCh.chapterNumber,
            title: newCh.title,
            content: newCh.content,
            sourceUrl: newCh.url,
            sourceFormat: 'web',
            createdAt: now,
            updatedAt: now,
          ));
          added++;
        }
        onProgress?.call(i + 1, chapters.length, newCh.title);
      }

      if (added > 0 || updated > 0) {
        await _db.touchBook(existing.id!);
        final allChapters = await _db.getAllChapters(existing.id!);
        final totalWords =
            allChapters.fold(0, (sum, ch) => sum + ch.content.length);
        await _db.updateBook(
            existing.copyWith(wordCount: totalWords, updatedAt: now));
      }

      return CrawlImportResult(
        isNewBook: false,
        bookId: existing.id!,
        bookTitle: existing.title,
        chapterCount: existingChapters.length + added,
        addedCount: added,
        updatedCount: updated,
      );
    }

    // ===== 新建书路径(事务) =====
    final book = await _db.db.transaction((txn) async {
      // 事务内必须用事务对象执行（executor: txn），否则外层连接等锁
      final b = await _db.createBook(Book(
        title: title,
        author: author,
        status: '连载中',
        wordCount: 0,
        sourceUrl: bookUrl,
        sourceFormat: 'web',
        createdAt: now,
        updatedAt: now,
      ), executor: txn);
      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        await _db.createChapter(Chapter(
          bookId: b.id!,
          chapterNumber: ch.chapterNumber,
          originalOrder: ch.chapterNumber,
          title: ch.title,
          content: ch.content,
          sourceUrl: ch.url,
          sourceFormat: 'web',
          createdAt: now,
          updatedAt: now,
        ), executor: txn);
        onProgress?.call(i + 1, chapters.length, ch.title);
      }
      return b;
    });

    // 计算字数（事务外，普通连接）
    final all = await _db.getAllChapters(book.id!);
    final words = all.fold(0, (sum, c) => sum + c.content.length);
    final saved = await _db.updateBook(book.copyWith(wordCount: words));

    return CrawlImportResult(
      isNewBook: true,
      bookId: saved.id!,
      bookTitle: saved.title,
      chapterCount: chapters.length,
    );
  }
}

/// 已抓取正文的章节(目录项 + 正文内容)
class CrawledChapterWithContent {
  final String title;
  final String url;
  final int chapterNumber;
  final String content;

  const CrawledChapterWithContent({
    required this.title,
    required this.url,
    required this.chapterNumber,
    required this.content,
  });
}
