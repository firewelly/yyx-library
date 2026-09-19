import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/models/book_source.dart';
import 'package:novelmgt_flutter/theme/reader_themes.dart';

void main() {
  group('BookSource', () {
    test('toJson/fromJson round trip preserves fields', () {
      const source = BookSource(
        name: '测试书源',
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
          cleanPatterns: [r'^https?://[^\s]+$'],
        ),
      );

      final restored = BookSource.fromJson(source.toJson());
      expect(restored.name, '测试书源');
      expect(restored.baseUrl, 'https://example.com');
      expect(restored.search!.url, contains('{{key}}'));
      expect(restored.search!.listSelector, 'table.result-item');
      expect(restored.toc.listSelector, 'div#list dl dd a');
      expect(restored.content.selector, 'div#content');
      expect(restored.content.cleanPatterns, hasLength(1));
    });

    test('fromJson handles missing optional fields', () {
      final source = BookSource.fromJson({
        'name': '简单书源',
        'baseUrl': 'https://example.com',
        'toc': {'listSelector': 'div#list a'},
        'content': {'selector': 'div#content'},
      });
      expect(source.name, '简单书源');
      expect(source.search, isNull);
      expect(source.toc.url, '{{bookUrl}}');
      expect(source.toc.title, 'text');
      expect(source.enabled, isTrue);
    });

    test('default sources are present', () {
      expect(kDefaultBookSources, isNotEmpty);
      for (final s in kDefaultBookSources) {
        expect(s.name, isNotEmpty);
        expect(s.baseUrl, startsWith('http'));
        expect(s.toc.listSelector, isNotEmpty);
        expect(s.content.selector, isNotEmpty);
      }
    });
  });

  group('ReaderTheme', () {
    test('readerThemeById returns sepia by default', () {
      expect(readerThemeById(null).id, 'sepia');
      expect(readerThemeById('unknown').id, 'sepia');
    });

    test('all themes have distinct ids and valid colors', () {
      final ids = kReaderThemes.map((t) => t.id).toSet();
      expect(ids.length, kReaderThemes.length);
      for (final t in kReaderThemes) {
        expect(t.background, isNotNull);
        expect(t.text, isNotNull);
        expect(t.isDark, t.id == 'dark');
      }
    });
  });
}
