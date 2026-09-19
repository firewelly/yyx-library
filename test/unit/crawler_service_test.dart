import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/models/book_source.dart';
import 'package:novelmgt_flutter/services/crawler_service.dart';

/// 内存 HTTP adapter —— 按 URL 返回预置 HTML,不发真实网络请求
class MemoryHttpAdapter implements HttpClientAdapter {
  final Map<String, String> pages;
  MemoryHttpAdapter(this.pages);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    final body = pages[url];
    if (body == null) {
      return ResponseBody.fromString('404', 404);
    }
    final bytes = utf8.encode(body);
    return ResponseBody.fromBytes(bytes, 200,
        headers: {
          Headers.contentTypeHeader: ['text/html; charset=utf-8'],
        });
  }

  @override
  void close({bool force = false}) {}
}

/// 构造一个注入内存 adapter 的引擎
DartCrawlerEngine _engineWith(Map<String, String> pages) {
  final dio = Dio();
  dio.httpClientAdapter = MemoryHttpAdapter(pages);
  return DartCrawlerEngine(dio: dio, minInterval: Duration.zero);
}

void main() {
  // 模拟一个静态小说站
  const searchHtml = '''
<html><body>
<table class="result-item">
  <tr>
    <td class="author">测试作者</td>
    <td><a href="/book/123/" title="测试小说">测试小说</a></td>
  </tr>
</table>
</body></html>
''';

  const tocHtml = '''
<html><body>
<div id="list"><dl>
  <dd><a href="/chapter/1.html">第一章 开始</a></dd>
  <dd><a href="/chapter/2.html">第二章 继续</a></dd>
  <dd><a href="/chapter/3.html">第三章 结束</a></dd>
</dl></div>
</body></html>
''';

  const contentHtml = '''
<html><body>
<div id="content">
  <p>这是正文第一段。</p>
  <p>这是正文第二段。</p>
  <p>https://example.com/广告链接</p>
  <p>请收藏本站最新章节无弹窗</p>
</div>
</body></html>
''';

  const source = BookSource(
    name: 'test',
    baseUrl: 'https://example.com',
    search: SearchRule(
      url: 'https://example.com/search?key={{key}}',
      listSelector: 'table.result-item',
      title: 'a@title',
      urlRule: 'a@href',
      author: 'td.author',
    ),
    toc: TocRule(
      url: '{{bookUrl}}',
      listSelector: 'div#list dl dd a',
    ),
    content: ContentRule(
      selector: 'div#content',
      cleanPatterns: [
        r'^https?://[^\s]+$',
        r'^(请收藏|手机阅读|最新章节|无弹窗)[^\n]*',
      ],
    ),
  );

  group('DartCrawlerEngine', () {
    test('searchBooks parses results', () async {
      final engine = _engineWith({
        'https://example.com/search?key=%E6%B5%8B%E8%AF%95': searchHtml,
      });
      final results = await engine.searchBooks(source, '测试');
      expect(results, hasLength(1));
      expect(results.first.title, '测试小说');
      expect(results.first.author, '测试作者');
      expect(results.first.url, 'https://example.com/book/123/');
    });

    test('fetchToc parses chapter list with absolute URLs', () async {
      final engine = _engineWith({
        'https://example.com/book/123/': tocHtml,
      });
      final chapters = await engine.fetchToc(source, 'https://example.com/book/123/');
      expect(chapters, hasLength(3));
      expect(chapters.first.title, '第一章 开始');
      expect(chapters.first.url, 'https://example.com/chapter/1.html');
      expect(chapters.first.chapterNumber, 1);
      expect(chapters.last.chapterNumber, 3);
    });

    test('fetchChapterContent extracts and cleans text', () async {
      final engine = _engineWith({
        'https://example.com/chapter/1.html': contentHtml,
      });
      final text = await engine.fetchChapterContent(
          source, 'https://example.com/chapter/1.html');
      // 保留段落正文
      expect(text, contains('这是正文第一段。'));
      expect(text, contains('这是正文第二段。'));
      // 广告链接与收藏提示被清洗
      expect(text, isNot(contains('https://example.com/广告链接')));
      expect(text, isNot(contains('请收藏')));
      expect(text, isNot(contains('无弹窗')));
    });

    test('search on source without search rule throws', () async {
      const noSearchSource = BookSource(
        name: 'no-search',
        baseUrl: 'https://example.com',
        toc: TocRule(url: '{{bookUrl}}', listSelector: 'a'),
        content: ContentRule(selector: 'div'),
      );
      final engine = _engineWith({});
      expect(
        () => engine.searchBooks(noSearchSource, 'x'),
        throwsA(isA<CrawlerException>()),
      );
    });
  });
}
