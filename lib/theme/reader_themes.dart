import 'package:flutter/material.dart';

/// 阅读主题 —— 阅读器内的背景与文字配色
///
/// 独立于 App 全局主题(亮/暗),由用户在阅读器内一键切换,
/// 支持 4 套内置配色:纯白 / 米黄护眼 / 纯黑 OLED / 浅绿。
class ReaderTheme {
  final String id;
  final String name;
  final Color background;
  final Color text;
  final Color secondaryText; // 弱化文字(章节计数等)
  final Color titleColor; // 章节标题
  final Color accent; // 强调(按钮/图标)
  final Color surface; // 卡片/导航条底色
  final Color border; // 分隔线

  const ReaderTheme({
    required this.id,
    required this.name,
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.titleColor,
    required this.accent,
    required this.surface,
    required this.border,
  });

  /// 是否为深色阅读主题
  bool get isDark {
    final lum = background.computeLuminance();
    return lum < 0.3;
  }
}

/// 全部内置阅读主题
const List<ReaderTheme> kReaderThemes = [
  // 纯白
  ReaderTheme(
    id: 'paper',
    name: '纯白',
    background: Color(0xFFFFFFFF),
    text: Color(0xFF1F2937),
    secondaryText: Color(0xFF9CA3AF),
    titleColor: Color(0xFF1F2937),
    accent: Color(0xFF3949AB),
    surface: Color(0xFFF3F4F6),
    border: Color(0xFFE5E7EB),
  ),
  // 米黄护眼(默认)
  ReaderTheme(
    id: 'sepia',
    name: '米黄',
    background: Color(0xFFF5E6C8),
    text: Color(0xFF4A3728),
    secondaryText: Color(0xFFA08B6F),
    titleColor: Color(0xFF3E2F1E),
    accent: Color(0xFF8B6914),
    surface: Color(0xFFEAD9B8),
    border: Color(0xFFDFC9A4),
  ),
  // 纯黑 OLED
  ReaderTheme(
    id: 'dark',
    name: '深黑',
    background: Color(0xFF000000),
    text: Color(0xFFB8BFC9),
    secondaryText: Color(0xFF5A6472),
    titleColor: Color(0xFFD1D5DB),
    accent: Color(0xFF6B8AFD),
    surface: Color(0xFF111318),
    border: Color(0xFF1F242C),
  ),
  // 浅绿
  ReaderTheme(
    id: 'green',
    name: '浅绿',
    background: Color(0xFFDCE8D2),
    text: Color(0xFF2F3B2B),
    secondaryText: Color(0xFF8A9784),
    titleColor: Color(0xFF26301F),
    accent: Color(0xFF4C7A3D),
    surface: Color(0xFFCFDEC3),
    border: Color(0xFFBECCAC),
  ),
];

/// 按 id 查找阅读主题(找不到返回默认米黄)
ReaderTheme readerThemeById(String? id) {
  for (final t in kReaderThemes) {
    if (t.id == id) return t;
  }
  return kReaderThemes[1]; // sepia 默认
}
