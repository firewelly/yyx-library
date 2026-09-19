import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/utils/zh_converter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ZhConverter.instance.ensureLoaded();
  });

  group('ZhConverter 繁简转换', () {
    test('词典已加载', () {
      expect(ZhConverter.instance.isLoaded, isTrue);
    });

    test('繁体 → 简体（单字）', () {
      expect(ZhConverter.instance.toSimplified('繁體中文'), '繁体中文');
    });

    test('简体 → 繁体（单字）', () {
      expect(ZhConverter.instance.toTraditional('简体中文'), '簡體中文');
    });

    test('简体 → 繁体（词组优先：头发→頭髮 而非 頭發）', () {
      // STPhrases 收录「头发→頭髮」；单字映射 头→頭 发→發 是错译，
      // 词组优先保证正确
      expect(ZhConverter.instance.toTraditional('头发'), '頭髮');
    });

    test('未收录字符原样保留（英文/数字/换行）', () {
      expect(ZhConverter.instance.toSimplified('ABC123\n英文.!?'), 'ABC123\n英文.!?');
    });

    test('空字符串与空文本安全', () {
      expect(ZhConverter.instance.toSimplified(''), '');
      expect(ZhConverter.instance.toTraditional(''), '');
    });

    test('长文本转换（章节级）', () {
      final chapter = '第一回 宴桃园豪杰三结义\n${'话说天下大势，分久必合，合久必分。' * 200}';
      final converted = ZhConverter.instance.toTraditional(chapter);
      expect(converted, contains('話說天下大勢'));
      expect(converted.length, chapter.length);
    });

    test('searchVariants 展开简繁变体', () {
      final variants = ZhConverter.instance.searchVariants('小说');
      expect(variants, contains('小说'));
      expect(variants, contains('小說'));
    });

    test('searchVariants 空查询返回空列表', () {
      expect(ZhConverter.instance.searchVariants('  '), isEmpty);
    });

    test('转换结果缓存一致', () {
      final a = ZhConverter.instance.toSimplified('機器學習');
      final b = ZhConverter.instance.toSimplified('機器學習');
      expect(identical(a, b), isTrue); // 第二次命中缓存
      expect(a, '机器学习');
    });
  });
}
