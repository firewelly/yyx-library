import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/book.dart';
import '../providers/library_provider.dart';
import '../theme/app_colors.dart';
import 'book_card.dart';

/// 书籍网格视图
class BookGridView extends ConsumerWidget {
  const BookGridView({super.key});

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
      return _buildEmptyState(context);
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: 0.78,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: state.books.length,
      itemBuilder: (context, index) {
        final book = state.books[index];
        final isSelected = state.selectedBookIds.contains(book.id);
        return BookCard(
          book: book,
          isSelected: isSelected,
          isSelectionMode: state.isSelectionMode,
          onTap: () => _onBookTap(context, ref, book, state.isSelectionMode),
          onLongPress: () => _onLongPress(ref, book, state.isSelectionMode),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.auto_stories_rounded, size: 72, color: AppColors.emptyState),
            const SizedBox(height: 20),
            Text('书库还是空的', style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            )),
            const SizedBox(height: 8),
            Text(
              '点击右下角 + 导入你的第一本小说\n支持 TXT / EPUB / PDF / MOBI',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.hintText),
            ),
          ],
        ),
      ),
    );
  }

  void _onBookTap(BuildContext context, WidgetRef ref, Book book, bool isSelectionMode) {
    if (isSelectionMode) {
      ref.read(libraryProvider.notifier).toggleBookSelection(book.id!);
    } else {
      context.go('/book/${book.id}');
    }
  }

  void _onLongPress(WidgetRef ref, Book book, bool isSelectionMode) {
    if (!isSelectionMode) {
      ref.read(libraryProvider.notifier).toggleSelectionMode();
      ref.read(libraryProvider.notifier).toggleBookSelection(book.id!);
    }
  }
}