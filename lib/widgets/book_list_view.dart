import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../theme/app_colors.dart';
import '../utils/formatters.dart';
import 'generated_cover.dart';

/// 书籍列表视图 - 虚拟化行列表(支持上万本流畅滚动)
class BookListView extends ConsumerWidget {
  const BookListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(libraryProvider);

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null) {
      return Center(child: Text('加载失败: ${state.error}'));
    }

    if (state.books.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.auto_stories_rounded, size: 72, color: AppColors.emptyState),
              const SizedBox(height: 20),
              Text('书库还是空的', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                '点击右下角 + 导入你的第一本小说\n支持 TXT / EPUB / PDF / MOBI',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.hintText),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: state.books.length,
      itemExtent: 76,
      itemBuilder: (context, index) {
        final book = state.books[index];
        return _BookRow(
          book: book,
          isSelectionMode: state.isSelectionMode,
          isSelected: state.selectedBookIds.contains(book.id),
          onTap: () => _onBookTap(context, ref, book, state.isSelectionMode),
          onToggle: () => ref.read(libraryProvider.notifier).toggleBookSelection(book.id!),
        );
      },
    );
  }

  void _onBookTap(BuildContext context, WidgetRef ref, Book book, bool isSelectionMode) {
    if (isSelectionMode) {
      ref.read(libraryProvider.notifier).toggleBookSelection(book.id!);
    } else {
      context.go('/book/${book.id}');
    }
  }
}

class _BookRow extends StatelessWidget {
  final Book book;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _BookRow({
    required this.book,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected ? cs.primaryContainer.withValues(alpha: 0.5) : cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                if (isSelectionMode) ...[
                  Checkbox(value: isSelected, onChanged: (_) => onToggle()),
                  const SizedBox(width: 4),
                ],
                GeneratedCover(title: book.title, width: 40, height: 54, fontSize: 18),
                const SizedBox(width: 12),
                // 标题 + 作者/标签
                Expanded(
                  flex: 4,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        book.author ?? '未知',
                        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // 状态
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: book.status == '已完结' ? AppColors.completedStatus : AppColors.ongoingStatus,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    book.status,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 16),
                // 字数 / 章节(窄屏隐藏)
                if (MediaQuery.sizeOf(context).width >= 900) ...[
                  _Metric(label: '字数', value: Formatters.formatWordCount(book.wordCount)),
                  const SizedBox(width: 20),
                  _Metric(label: '章节', value: '${book.chapterCount}'),
                  const SizedBox(width: 20),
                ],
                // 评分(窄屏隐藏)
                if (MediaQuery.sizeOf(context).width >= 1100)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(5, (i) => Icon(
                      Icons.star,
                      size: 14,
                      color: i < book.rating ? AppColors.ratingStar : AppColors.emptyState,
                    )),
                  ),
                const Spacer(),
                // 导入时间(宽屏显示)
                if (MediaQuery.sizeOf(context).width >= 1200)
                  Text(
                    book.createdAt.startsWith('20') ? book.createdAt.substring(0, 10) : book.createdAt,
                    style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 10, color: theme.colorScheme.onSurfaceVariant,
        )),
      ],
    );
  }
}
