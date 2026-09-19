import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:novelmgt_flutter/services/settings_service.dart';

/// T-005: 设置持久化 —— 修改后重启（重新打开 Hive box）仍保持
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('novelmgt_settings_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('T-005: 阅读器设置（字体/边距/行距/主题/繁简/编码）持久化', () async {
    final s1 = SettingsService();
    await s1.initialize();
    await s1.setFontSize(22);
    await s1.setMarginSize(100);
    await s1.setLineHeight(2.2);
    await s1.setReaderTheme('dark');
    await s1.setReaderZhVariant('traditional');
    await s1.setDefaultEncoding('gbk');

    // 关闭全部 box（等价于重启应用），新实例从磁盘重新加载
    await Hive.close();

    final s2 = SettingsService();
    await s2.initialize();
    expect(s2.settings.fontSize, 22, reason: '字体大小应保持 22');
    expect(s2.settings.marginSize, 100, reason: '左右边距应保持 100');
    expect(s2.settings.lineHeight, 2.2, reason: '行间距应保持 2.2');
    expect(s2.settings.readerTheme, 'dark', reason: '阅读主题应保持 dark');
    expect(s2.settings.readerZhVariant, 'traditional', reason: '繁简显示应保持繁体');
    expect(s2.settings.defaultEncoding, 'gbk', reason: '默认编码应保持 GBK');
  });

  test('默认值为原文显示 + 自动编码（新用户）', () async {
    final s = SettingsService();
    await s.initialize();
    expect(s.settings.readerZhVariant, 'original');
    expect(s.settings.defaultEncoding, 'auto');
  });
}
