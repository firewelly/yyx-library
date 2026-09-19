import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 生成式封面 - 无封面图时按书名生成彩色占位封面
///
/// 用书名 hash 稳定选取色相,首字大字居中,书脊高光模拟实体书。
class GeneratedCover extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final double fontSize;
  final BorderRadius borderRadius;

  const GeneratedCover({
    super.key,
    required this.title,
    this.width = 56,
    this.height = 76,
    double? fontSize,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  })  : fontSize = fontSize ?? 22,
        assert(height > 0 && width > 0);

  @override
  Widget build(BuildContext context) {
    final hash = title.hashCode.abs();
    final base = AppColors.tagColors[hash % AppColors.tagColors.length];
    final firstChar = title.isEmpty ? '?' : title[0];

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, Color.lerp(base, Colors.black, 0.35)!],
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(1, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            // 书脊高光
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width * 0.12,
              child: Container(
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
            // 首字
            Center(
              child: Padding(
                padding: EdgeInsets.only(left: width * 0.08),
                child: Text(
                  firstChar,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
