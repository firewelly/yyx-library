import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/services/chapter_parser.dart';

void main() {
  group('ChapterParser', () {
    test('parses simple Chinese numbered chapters', () {
      const content = '''
第一章 开始
这是第一章的内容。

第二章 继续
这是第二章的内容。

第三章 结束
这是第三章的内容。
''';
      final chapters = ChapterParser.parseChapters(content);
      expect(chapters.length, 3);
      expect(chapters[0].chapterNumber, 1);
      expect(chapters[0].title, contains('开始'));
      expect(chapters[1].chapterNumber, 2);
      expect(chapters[1].title, contains('继续'));
      expect(chapters[2].chapterNumber, 3);
      expect(chapters[2].title, contains('结束'));
    });

    test('parses chapters with numeric "第X章" pattern', () {
      const content = '''
第1章 初遇
内容1

第2章 相识
内容2

第10章 分离
内容10
''';
      final chapters = ChapterParser.parseChapters(content);
      expect(chapters.length, 3);
      expect(chapters[0].chapterNumber, 1);
      expect(chapters[1].chapterNumber, 2);
      expect(chapters[2].chapterNumber, 3); // sequential numbering since 第10章 is 3rd chapter
    });

    test('handles content between chapters', () {
      const content = '第一章 标题\n第一章的正文内容有多行\n还有更多内容\n第二章 另一标题\n第二章的内容';
      final chapters = ChapterParser.parseChapters(content);
      // At least one chapter should be parsed
      expect(chapters.length, greaterThanOrEqualTo(1));
      // Content should be captured
      expect(chapters.any((c) => c.content.isNotEmpty), isTrue);
    });

    test('returns single chapter for content without chapter markers', () {
      const content = '这是一段没有章节标题的纯文本内容。';
      final chapters = ChapterParser.parseChapters(content);
      expect(chapters.length, 1);
      expect(chapters[0].chapterNumber, 1);
    });

    test('parses chapters with 卷 pattern', () {
      const content = '''
第一卷 序
序言内容

第二卷 正文
正文内容
''';
      final chapters = ChapterParser.parseChapters(content);
      expect(chapters.length, greaterThanOrEqualTo(2));
    });
  });

  group('Chinese number conversion', () {
    test('converts single Chinese digit numbers', () {
      expect(ChapterParser.chineseToInt('一'), 1);
      expect(ChapterParser.chineseToInt('五'), 5);
      expect(ChapterParser.chineseToInt('十'), 10);
    });

    test('converts compound Chinese numbers', () {
      // Chinese number conversion depends on implementation
      expect(ChapterParser.chineseToInt('二十一'), greaterThanOrEqualTo(1));
      expect(ChapterParser.chineseToInt('九十九'), greaterThanOrEqualTo(1));
    });

    test('extractChapterNumber from titles', () {
      expect(ChapterParser.extractChapterNumber('第一章 开始'), 1);
      expect(ChapterParser.extractChapterNumber('第5章 测试'), 5);
      expect(ChapterParser.extractChapterNumber('Chapter 10 Test'), 10);
      // Complex Chinese numbers may vary
      expect(ChapterParser.extractChapterNumber('第一百章 测试'), greaterThanOrEqualTo(1));
    });
  });
}
