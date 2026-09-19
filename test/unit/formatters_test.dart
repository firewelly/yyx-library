import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/utils/formatters.dart';

void main() {
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
}
