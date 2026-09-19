import 'package:flutter/material.dart';

/// 应用色彩系统 —— 方案 B「靛蓝墨海」
///
/// 深靛蓝主色 + 珊瑚橙强调色,纯白净底,现代专业。
/// 所有页面/组件应通过 [AppColors] 或 [Theme.of(context).colorScheme] 取色,
/// 禁止直接使用 Colors.grey / Colors.red 等硬编码色。
/// 配色方案（对应 docs/color_themes.html 的 4 套设计稿）
class AppPalette {
  final String id;
  final String name;
  final Color seed;
  final Color accent;

  const AppPalette({
    required this.id,
    required this.name,
    required this.seed,
    required this.accent,
  });

  /// 全部可选配色方案
  static const List<AppPalette> all = [paletteA, paletteB, paletteC, paletteD];

  /// A 墨韵书阁（墨绿+暖金，东方书卷气）
  static const paletteA = AppPalette(
    id: 'a', name: '墨韵书阁', seed: Color(0xFF2F5D50), accent: Color(0xFFC9A227),
  );

  /// B 靛蓝墨海（深靛蓝+珊瑚橙，现代专业，默认）
  static const paletteB = AppPalette(
    id: 'b', name: '靛蓝墨海', seed: Color(0xFF3949AB), accent: Color(0xFFFF6E40),
  );

  /// C 暮色书房（暖棕+赤陶，温暖复古）
  static const paletteC = AppPalette(
    id: 'c', name: '暮色书房', seed: Color(0xFF5D4037), accent: Color(0xFFD2691E),
  );

  /// D 墨夜星河（深色优先，青柠+天蓝，科技护眼）
  static const paletteD = AppPalette(
    id: 'd', name: '墨夜星河', seed: Color(0xFFA3E635), accent: Color(0xFF38BDF8),
  );

  static AppPalette byId(String id) => all.firstWhere(
    (p) => p.id == id,
    orElse: () => paletteB,
  );
}

class AppColors {
  AppColors._();

  // ===== 品牌主色 =====
  /// 主色调种子色 - 靛蓝 Indigo 600（默认方案 B）
  static const Color seedColor = Color(0xFF3949AB);

  /// 强调色 - 珊瑚橙 Deep Orange 400
  static const Color accent = Color(0xFFFF6E40);

  // ===== 语义色 =====
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF0EA5E9);

  // ===== 书籍状态色 =====
  static const Color ongoingStatus = Color(0xFF0EA5E9); // 连载中 - 天蓝
  static const Color completedStatus = Color(0xFF16A34A); // 已完结 - 绿

  // ===== 评分星色 =====
  static const Color ratingStar = Color(0xFFF59E0B);

  // ===== 中性语义 token(替换散落的 Colors.grey) =====
  /// 提示文字 / 次要文字
  static const Color hintText = Color(0xFF94A3B8);

  /// 空状态图标色(更浅)
  static const Color emptyState = Color(0xFFCBD5E1);

  /// 描边 / 分割线
  static const Color outline = Color(0xFFE2E8F0);

  // ===== 阅读器背景色 =====
  static const Color readerBgLight = Color(0xFFFAFAFA);
  static const Color readerBgDark = Color(0xFF0F1419);
  static const Color readerBgSepia = Color(0xFFF5E6C8);

  // ===== 标签色板(靛蓝系协调 8 色) =====
  static const List<Color> tagColors = [
    Color(0xFF3949AB), // 靛蓝(主色)
    Color(0xFFFF6E40), // 珊瑚橙(强调)
    Color(0xFF0EA5E9), // 天蓝
    Color(0xFF16A34A), // 翠绿
    Color(0xFF8B5CF6), // 紫罗兰
    Color(0xFFEC4899), // 玫红
    Color(0xFFF59E0B), // 琥珀
    Color(0xFF14B8A6), // 青绿
  ];

  /// 浅色色彩方案（可指定配色方案）
  static ColorScheme lightColorScheme([AppPalette palette = AppPalette.paletteB]) {
    return ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: Brightness.light,
    );
  }

  /// 深色色彩方案（可指定配色方案）
  static ColorScheme darkColorScheme([AppPalette palette = AppPalette.paletteB]) {
    return ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: Brightness.dark,
    );
  }
}
