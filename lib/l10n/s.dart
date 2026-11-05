import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show PlatformDispatcher;

import 'translations.dart';

export 'translations.dart';

/// 应用语言: 'system'（跟随系统）| 'zh'（简体中文）| 'en'（English）
///
/// 轻量 i18n：以中文原文为 key，英文查 [kEnTranslations] 表。
/// 需要参数的句子使用 `{name}` 具名占位符：
/// ```dart
/// t('共 {n} 章', {'n': chapters.length})
/// ```
class S {
  S._();

  static String _lang = 'system';

  /// 当前语言设置值
  static String get lang => _lang;

  /// 注入设置（设置页/启动时调用）
  static void configure(String lang) {
    _lang = (lang == 'zh' || lang == 'en') ? lang : 'system';
  }

  /// MaterialApp 使用的 locale；跟随系统时返回 null（由 supportedLocales 解析）
  static Locale? get resolvedLocale {
    switch (_lang) {
      case 'zh':
        return const Locale('zh');
      case 'en':
        return const Locale('en');
      default:
        return null;
    }
  }

  static bool get _systemIsEnglish {
    final locale = PlatformDispatcher.instance.locale;
    return locale.languageCode.toLowerCase() != 'zh';
  }

  /// 当前是否应显示英文
  static bool get isEnglish =>
      _lang == 'en' || (_lang == 'system' && _systemIsEnglish);

  /// 翻译：中文原文 → 当前语言文本
  static String t(String zh, [Map<String, Object?>? params]) {
    var s = isEnglish ? (kEnTranslations[zh] ?? zh) : zh;
    if (params != null) {
      params.forEach((key, value) {
        s = s.replaceAll(
            '{$key}', value == null ? '' : value.toString());
      });
    }
    return s;
  }
}

/// 全局快捷翻译函数
String t(String zh, [Map<String, Object?>? params]) => S.t(zh, params);
