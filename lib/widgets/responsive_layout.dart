import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// 响应式布局组件 - 根据屏幕宽度自动切换布局
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    required this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppConstants.tabletBreakpoint) {
          return desktop;
        } else if (constraints.maxWidth >= AppConstants.mobileBreakpoint) {
          return tablet;
        } else {
          return mobile;
        }
      },
    );
  }

  /// 判断当前是否为桌面宽度
  static bool isDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= AppConstants.tabletBreakpoint;
  }

  /// 判断当前是否为平板宽度
  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= AppConstants.mobileBreakpoint && width < AppConstants.tabletBreakpoint;
  }

  /// 判断当前是否为手机宽度
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < AppConstants.mobileBreakpoint;
  }
}