import 'package:flutter/material.dart';
import '../l10n/s.dart';

/// 格式化工具
class Formatters {
  Formatters._();

  /// 格式化字数：12345 → "1.2万", 1234 → "1.2k", 999 → "999"
  static String formatWordCount(int count) {
    if (count >= 10000) {
      return t('{p1}万', {'p1': (count / 10000).toStringAsFixed(1)});
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }


  /// 章节标题是否已自带编号（第X章/回/节/卷、Chapter N、N. 等）
  static final RegExp chapterNumberPrefix = RegExp(
    r'^\s*(?:第\s*[0-9一二三四五六七八九十百千万亿零〇两廿卅壹贰叁肆伍陆柒捌玖拾佰仟萬億]+\s*[章回节卷话集部篇]'
    r'|chapter\s+[0-9ivxlcdm]+|\d+\s*[.、:：])',
    caseSensitive: false,
  );

  /// 章节显示标题：标题已带编号则原样显示，否则拼「第N章」前缀
  static String chapterTitle(int? number, String? title) {
    final name = (title ?? '').trim();
    if (name.isEmpty) {
      return number == null ? '' : t('第{num}章', {'num': number});
    }
    if (number == null || chapterNumberPrefix.hasMatch(name)) return name;
    return t('第{num}章 {title}', {'num': number, 'title': name});
  }

  /// 格式化日期 → "2026-04-08"
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 格式化日期时间 → "2026-04-08 14:30"
  static String formatDateTime(DateTime date) {
    return '${formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// 格式化阅读进度百分比
  static String formatProgress(double percent) {
    return '${percent.toStringAsFixed(1)}%';
  }

  /// 格式化持续时间（分钟 → "X小时Y分钟"）
  static String formatDuration(int minutes) {
    if (minutes < 60) return t('{minutes}分钟', {'minutes': minutes});
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return t('{hours}小时', {'hours': hours});
    return t('{hours}小时{mins}分钟', {'hours': hours, 'mins': mins});
  }

  /// 截断文本
  static String truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// 将 Color 转为 hex 字符串 (例如 "#1976D2")，避免使用已废弃的 .value
  static String colorToHex(Color color) {
    final r = (color.r * 255).toInt();
    final g = (color.g * 255).toInt();
    final b = (color.b * 255).toInt();
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }
}