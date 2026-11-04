import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/l10n/s.dart';
import 'package:novelmgt_flutter/utils/formatters.dart';

void main() {
  setUpAll(() {
    S.configure('zh'); // 默认断言中文格式
  });
  group('Formatters', () {
    test('formatWordCount formats large numbers', () {
      expect(Formatters.formatWordCount(0), '0');
      expect(Formatters.formatWordCount(999), '999');
      expect(Formatters.formatWordCount(1000), '1.0k');
      expect(Formatters.formatWordCount(10000), '1.0万');
      expect(Formatters.formatWordCount(100000), '10.0万');
      expect(Formatters.formatWordCount(1500), '1.5k');
      expect(Formatters.formatWordCount(12345), '1.2万');
    });

    test('formatDate formats DateTime', () {
      final date = DateTime(2024, 1, 15);
      expect(Formatters.formatDate(date), '2024-01-15');
      final date2 = DateTime(2024, 12, 5);
      expect(Formatters.formatDate(date2), '2024-12-05');
    });

    test('formatProgress calculates percentage', () {
      expect(Formatters.formatProgress(0), '0.0%');
      expect(Formatters.formatProgress(50), '50.0%');
      expect(Formatters.formatProgress(100), '100.0%');
      expect(Formatters.formatProgress(33.33), '33.3%');
    });

    test('formatDuration formats minutes', () {
      expect(Formatters.formatDuration(30), '30分钟');
      expect(Formatters.formatDuration(60), '1小时');
      expect(Formatters.formatDuration(90), '1小时30分钟');
      expect(Formatters.formatDuration(125), '2小时5分钟');
    });

    test('truncate text', () {
      expect(Formatters.truncate('hello', 10), 'hello');
      expect(Formatters.truncate('hello world', 5), 'hello...');
    });
  });

  group('Formatters.chapterTitle 去重编号', () {
    test('标题已带「第X章」不再重复拼序号', () {
      expect(Formatters.chapterTitle(2, '第2章 武魂觉醒'), '第2章 武魂觉醒');
      expect(Formatters.chapterTitle(31, '第1章 武魂觉醒'), '第1章 武魂觉醒');
      expect(Formatters.chapterTitle(9, '第两百章 大战'), '第两百章 大战');
      expect(Formatters.chapterTitle(4, '第十二回 宴桃园'), '第十二回 宴桃园');
      expect(Formatters.chapterTitle(6, '第三节 出发'), '第三节 出发');
      expect(Formatters.chapterTitle(8, '第一卷 风起'), '第一卷 风起');
    });
    test('英文/数字编号同样识别', () {
      expect(Formatters.chapterTitle(5, 'Chapter 5: Awaken'), 'Chapter 5: Awaken');
      expect(Formatters.chapterTitle(7, '7. 起始'), '7. 起始');
      expect(Formatters.chapterTitle(12, '12、异变'), '12、异变');
    });
    test('标题无编号时补「第N章」', () {
      expect(Formatters.chapterTitle(3, '武动乾坤'), '第3章 武动乾坤');
      expect(Formatters.chapterTitle(10, '  未命名  '), '第10章 未命名');
    });
    test('空标题兜底', () {
      expect(Formatters.chapterTitle(1, ''), '第1章');
      expect(Formatters.chapterTitle(1, null), '第1章');
      expect(Formatters.chapterTitle(null, ''), '');
      expect(Formatters.chapterTitle(null, '第5章 独立标题'), '第5章 独立标题');
    });
    test('英文界面输出 Chapter 前缀', () {
      S.configure('en');
      expect(Formatters.chapterTitle(3, '武动乾坤'), 'Chapter 3 武动乾坤');
      expect(Formatters.chapterTitle(2, '第2章 武魂觉醒'), '第2章 武魂觉醒');
      S.configure('zh');
    });
  });
}
