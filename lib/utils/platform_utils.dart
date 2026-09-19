import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

/// 平台工具类
///
/// 使用 [defaultTargetPlatform] 而非 dart:io 的 Platform，
/// 保证同一份代码可在 Web 构建中编译（dart:io 在 Web 不可用）。
class PlatformUtils {
  PlatformUtils._();

  /// 是否桌面平台
  static bool get isDesktop {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  /// 是否 Web 平台
  static bool get isWeb => kIsWeb;

  /// 是否移动平台
  static bool get isMobile {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  /// 获取当前平台名称
  static String get platformName {
    if (kIsWeb) return 'Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => 'Windows',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iOS',
      _ => 'Unknown',
    };
  }

  /// 默认应用文件夹名
  static String get defaultAppFolder => 'NovelMgt';
}
