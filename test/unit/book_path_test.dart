import 'package:flutter_test/flutter_test.dart';
import 'package:novelmgt_flutter/utils/book_path.dart';

void main() {
  group('BookPath 跨系统相对路径', () {
    test('isAbsolute：盘符 / 斜杠开头 / 相对', () {
      expect(BookPath.isAbsolute(r'D:\novels\a.txt'), isTrue);
      expect(BookPath.isAbsolute('D:/novels/a.txt'), isTrue);
      expect(BookPath.isAbsolute('/Users/x/novels/a.txt'), isTrue);
      expect(BookPath.isAbsolute(r'\nas\a.txt'), isTrue);
      expect(BookPath.isAbsolute('novels/a.txt'), isFalse);
      expect(BookPath.isAbsolute('a.txt'), isFalse);
      expect(BookPath.isAbsolute(''), isFalse);
    });

    test('relativize：Windows 路径（反斜杠 + 大小写不敏感盘符）', () {
      expect(BookPath.relativize(r'D:\library\novels\a.txt', r'd:\library'),
          'novels/a.txt');
      expect(BookPath.relativize('D:/library/novels/a.txt', r'D:\library\'),
          'novels/a.txt');
    });

    test('relativize：macOS/Linux 路径', () {
      expect(BookPath.relativize('/Users/x/library/novels/a.txt', '/Users/x/library'),
          'novels/a.txt');
    });

    test('relativize：不在根目录下原样返回', () {
      expect(BookPath.relativize(r'E:\other\a.txt', r'D:\library'),
          r'E:\other\a.txt');
      expect(BookPath.relativize('/etc/hosts', '/Users/x/library'), '/etc/hosts');
    });

    test('relativize：根目录为空 / 已是相对路径 / 等于根目录', () {
      expect(BookPath.relativize(r'D:\a.txt', ''), r'D:\a.txt');
      expect(BookPath.relativize('novels/a.txt', r'D:\library'), 'novels/a.txt');
      expect(BookPath.relativize(r'D:\library', r'D:\library'), '.');
    });

    test('resolve：相对路径拼根目录；绝对路径原样；未配置原样', () {
      expect(BookPath.resolve('novels/a.txt', r'D:\library'),
          'D:/library/novels/a.txt');
      expect(BookPath.resolve('novels/a.txt', '/Users/x/library'),
          '/Users/x/library/novels/a.txt');
      expect(BookPath.resolve(r'E:\other\a.txt', r'D:\library'), r'E:\other\a.txt');
      expect(BookPath.resolve('novels/a.txt', ''), 'novels/a.txt');
    });

    test('normalize 折叠连续斜杠（修 /// 形态）', () {
      expect(BookPath.normalize('D://a///b//c/'), 'D:/a/b/c');
      final win = <String>[r'D:', r'a', r'b'].join(String.fromCharCode(92) + String.fromCharCode(92));
      expect(BookPath.normalize(win), 'D:/a/b');
      expect(BookPath.normalize('/a//b'), '/a/b');
    });

    test('往返：不同系统存取一致（Win 存 → mac 取）', () {
      // Windows 导入机：D:\library\novels\a.txt → novels/a.txt
      final rel = BookPath.relativize(r'D:\library\novels\a.txt', r'D:\library');
      expect(rel, 'novels/a.txt');
      // macOS 使用机：根目录 /Users/x/library → 解析回本机绝对路径
      final resolved = BookPath.resolve(rel, '/Users/x/library');
      expect(resolved, '/Users/x/library/novels/a.txt');
    });
  });
}
