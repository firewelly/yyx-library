import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/stats_provider.dart';
import '../utils/formatters.dart';
import '../theme/app_colors.dart';
import '../l10n/s.dart';

/// 统计页面
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(statsProvider);

    if (state.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(t('📊 统计'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final stats = state.stats;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t('📊 统计'))),
      body: RefreshIndicator(
        onRefresh: () => ref.read(statsProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 总览卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t('总览'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        _StatItem(label: t('小说'), value: '${stats.totalBooks}', icon: Icons.menu_book),
                        _StatItem(label: t('章节'), value: '${stats.totalChapters}', icon: Icons.article),
                        _StatItem(label: t('字数'), value: Formatters.formatWordCount(stats.totalWords), icon: Icons.text_fields),
                        _StatItem(label: t('作者'), value: '${stats.totalAuthors}', icon: Icons.person),
                        _StatItem(label: t('标签'), value: '${stats.totalTags}', icon: Icons.label),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 状态分布
            if (stats.statusDistribution.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('状态分布'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...stats.statusDistribution.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 12, height: 12,
                              decoration: BoxDecoration(
                                color: e.key == '已完结' ? AppColors.completedStatus : AppColors.ongoingStatus,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(t(e.key)),
                            const Spacer(),
                            Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // 评分分布
            if (stats.ratingDistribution.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('评分分布'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...stats.ratingDistribution.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            ...List.generate(5, (i) => Icon(Icons.star, size: 14, color: i < e.key ? AppColors.ratingStar : AppColors.emptyState)),
                            const SizedBox(width: 8),
                            Text(t('{p1}星', {'p1': e.key})),
                            const Spacer(),
                            Text(t('{p1}本', {'p1': e.value})),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // 标签TOP10
            if (stats.topTags.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('标签 TOP {p1}', {'p1': stats.topTags.length}), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...stats.topTags.map((tg) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.tagColors[stats.topTags.indexOf(tg) % AppColors.tagColors.length].withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                              child: Text(tg.name, style: const TextStyle(fontSize: 12)),
                            ),
                            const Spacer(),
                            Text(t('{p1}本', {'p1': tg.count})),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // 作者TOP10
            if (stats.topAuthors.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('作者 TOP {p1}', {'p1': stats.topAuthors.length}), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...stats.topAuthors.map((a) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.person, size: 18, color: AppColors.hintText),
                            const SizedBox(width: 8),
                            Expanded(child: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Text(t('{p1}本', {'p1': a.count}), style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // 最近阅读
            if (stats.recentlyRead.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('最近阅读'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      ...stats.recentlyRead.take(5).map((b) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.menu_book, size: 20),
                        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: b.author != null ? Text(b.author!, style: const TextStyle(fontSize: 12)) : null,
                        trailing: const Icon(Icons.chevron_right, size: 16),
                        onTap: () => context.go('/book/${b.id}'),
                      )),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}