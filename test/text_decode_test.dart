import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:charset/charset.dart' show gbk;
import 'package:dart3_big5/big5.dart' show Big5;
import 'package:novelmgt_flutter/utils/text_decode.dart';

void main() {
  group('TextDecode 多编码解码（纯 Dart，桌面/Web 一致）', () {
    test('UTF-8 自动检测（多数 TXT 的编码）', () async {
      final bytes = Uint8List.fromList(utf8.encode('中文测试 English'));
      expect(await TextDecode.decode(bytes), '中文测试 English');
    });

    test('GBK 自动检测', () async {
      final bytes = Uint8List.fromList(gbk.encode('中文测试'));
      // GBK 字节不是合法 UTF-8，应回退到 GBK 解码
      expect(await TextDecode.decode(bytes), '中文测试');
    });

    test('Big5 自动检测', () async {
      final bytes = Uint8List.fromList(Big5.encode('繁體中文'));
      expect(await TextDecode.decode(bytes), '繁體中文');
    });

    test('手动指定 GBK', () async {
      final bytes = Uint8List.fromList(gbk.encode('指定编码'));
      expect(await TextDecode.decode(bytes, encoding: 'gbk'), '指定编码');
    });

    test('手动指定 GB18030 / GB2312 别名', () async {
      final bytes = Uint8List.fromList(gbk.encode('国标编码'));
      expect(await TextDecode.decode(bytes, encoding: 'gb18030'), '国标编码');
      expect(await TextDecode.decode(bytes, encoding: 'gb2312'), '国标编码');
    });

    test('手动指定 Big5', () async {
      final bytes = Uint8List.fromList(Big5.encode('正體書'));
      expect(await TextDecode.decode(bytes, encoding: 'big5'), '正體書');
    });

    test('手动指定 UTF-8（非法字节不抛异常，替换容错）', () async {
      final bytes = Uint8List.fromList([0xe4, 0xb8, 0xad, 0xff, 0xfe]);
      final result = await TextDecode.decode(bytes, encoding: 'utf-8');
      expect(result, contains('中'));
    });

    test('未知编码名回退自动检测', () async {
      final bytes = Uint8List.fromList(utf8.encode('回退自动'));
      expect(await TextDecode.decode(bytes, encoding: 'nonexistent'), '回退自动');
    });

    test('GBK 文本含 GB18030 四字节序列时宽容解码（回归：紫川.txt 全文乱码）', () async {
      // charset 包的 gbk 对 GB18030 四字节序列（0x81-0xFE + 0x30-0x39 开头）
      // 抛 FormatException；旧行为：探测采样通过 → 全量解码抛错 → 兜底 UTF-8
      // → 全文乱码、章节无法切分。期望：坏序列替换为 U+FFFD，其余正确解码。
      final part1 = gbk.encode('第一章 胜利\r\n是谁说魔族军队很强的？罗杰副旗本得意的望着山脚下溃退的敌军。\r\n');
      final part2 = gbk.encode('第二节 遭遇\r\n白川副旗本白了他一眼，没有搭理他。\r\n');
      // GB18030 四字节序列（生僻字），插在字符边界
      final bytes = Uint8List.fromList([
        ...part1,
        0x81, 0x39, 0x81, 0x39,
        ...part2,
      ]);

      final auto = await TextDecode.decode(bytes);
      expect(auto.contains('第一章 胜利'), isTrue, reason: 'auto: 章节标题应正确解码');
      expect(auto.contains('第二节 遭遇'), isTrue, reason: 'auto: 后半段应正确解码');
      expect(auto.contains('\uFFFD'), isTrue, reason: 'auto: 坏序列应替换为 U+FFFD');

      final manual = await TextDecode.decode(bytes, encoding: 'gbk');
      expect(manual.contains('第一章 胜利'), isTrue, reason: 'gbk: 章节标题应正确解码');
      expect(manual.contains('第二节 遭遇'), isTrue, reason: 'gbk: 后半段应正确解码');
    });

    test('跨窗口边界的坏序列也能定位（256KB 分窗回归）', () async {
      // 构造 >256KB 的内容，坏序列放在窗口边界附近；插入点保持字符边界
      const unitText = '正文内容一笔一划写得清楚。\r\n';
      final head = gbk.encode('第一章 开局\r\n');
      final unit = gbk.encode(unitText);
      final tail = gbk.encode('第二章 终局\r\n尾声正文。');
      final n = ((256 * 1024 + 512) - head.length) ~/ unit.length;
      final bytes = Uint8List.fromList([
        ...head,
        ...[for (var i = 0; i < n; i++) ...unit],
        0x81, 0x39, 0x81, 0x39,
        ...[for (var i = 0; i < n; i++) ...unit],
        ...tail,
      ]);
      final result = await TextDecode.decode(bytes);
      expect(result.startsWith('第一章 开局'), isTrue);
      expect(result.contains('第二章 终局'), isTrue, reason: '跨窗坏序列后的内容应完整解码');
      expect(result.contains('\uFFFD'), isTrue);
    });
  });
}
