import 'package:flutter/material.dart';
import '../utils/formatters.dart';
import '../models/book.dart';
import '../theme/app_colors.dart';
import 'generated_cover.dart';

/// 书籍卡片组件 - 用于网格/列表视图中显示单本书
class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isSelectionMode;

  const BookCard({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isSelectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: isSelected ? cs.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 生成式封面
                  GeneratedCover(
                    title: book.title,
                    width: 52,
                    height: 72,
                    fontSize: 24,
                  ),
                  const SizedBox(width: 12),
                  // 右侧文字区
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题
                        Text(
                          book.title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isSelected ? cs.onPrimaryContainer : cs.primary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // 作者
                        if (book.author != null && book.author!.isNotEmpty)
                          Text(
                            book.author!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isSelected
                                  ? cs.onPrimaryContainer.withValues(alpha: 0.8)
                                  : cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        const SizedBox(height: 6),
                        // 标签
                        if (book.tags.isNotEmpty)
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: book.tags.take(3).map((tag) {
                              final idx = book.tags.indexOf(tag);
                              final color = AppColors.tagColors[idx % AppColors.tagColors.length];
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: color.withValues(alpha: 0.3)),
                                ),
                                child: Text(
                                  tag.name,
                                  style: TextStyle(fontSize: 10, color: color),
                                ),
                              );
                            }).toList(),
                          ),
                        const Spacer(),
                        // 进度 + 底部信息行
                        if (book.progressPercent > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: (book.progressPercent / 100).clamp(0.0, 1.0),
                                minHeight: 3,
                                backgroundColor: cs.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isSelected ? cs.onPrimaryContainer : cs.primary,
                                ),
                              ),
                            ),
                          ),
                        Row(
                          children: [
                            // 状态标签
                            _StatusBadge(status: book.status, isSelected: isSelected),
                            const SizedBox(width: 8),
                            // 格式标识
                            if (book.sourceFormat != null)
                              _FormatChip(
                                format: book.sourceFormat!,
                                isSelected: isSelected,
                              ),
                            const Spacer(),
                            // 字数
                            if (book.wordCount > 0)
                              Text(
                                Formatters.formatWordCount(book.wordCount),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isSelected
                                      ? cs.onPrimaryContainer.withValues(alpha: 0.7)
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 选择指示器
            if (isSelectionMode)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? cs.primary : cs.surface,
                    border: Border.all(
                      color: isSelected ? cs.primary : cs.outline,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Icon(Icons.check, size: 14, color: cs.onPrimary)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 书籍状态徽章
class _StatusBadge extends StatelessWidget {
  final String status;
  final bool isSelected;
  const _StatusBadge({required this.status, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == '已完结';
    final color = isCompleted ? AppColors.completedStatus : AppColors.ongoingStatus;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 来源格式标识
class _FormatChip extends StatelessWidget {
  final String format;
  final bool isSelected;
  const _FormatChip({required this.format, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = format.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
