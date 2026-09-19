import 'package:flutter/material.dart';

/// 格式化工具
class Formatters {
  Formatters._();

  /// 格式化字数：12345 → "1.2万", 1234 → "1.2k", 999 → "999"
  static String formatWordCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
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
    if (minutes < 60) return '$minutes分钟';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours小时';
    return '$hours小时$mins分钟';
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