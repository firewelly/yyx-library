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
  });
}
