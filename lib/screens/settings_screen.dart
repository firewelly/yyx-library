import 'dart:convert' show utf8;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../providers/database_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/backup_provider.dart';
import '../providers/cache_provider.dart';
import '../models/book_source.dart';
import '../services/book_source_store.dart';
import '../services/platform_fs.dart';
import '../theme/app_colors.dart';
import '../theme/reader_themes.dart';
import '../utils/constants.dart';
import '../utils/platform_utils.dart';
import '../utils/text_decode.dart';
import '../utils/web_launcher.dart';

/// 设置页面
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final s = settings.settings;
    final backup = ref.watch(backupProvider);
    final cache = ref.watch(cacheProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ 设置')),
      body: _adaptiveBody(context, [
          // 主题设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('外观', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  // 主题模式
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<ThemeMode>(
                      segments: const [
                        ButtonSegment(value: ThemeMode.system, label: Text('跟随系统'), icon: Icon(Icons.brightness_auto)),
                        ButtonSegment(value: ThemeMode.light, label: Text('浅色'), icon: Icon(Icons.light_mode)),
                        ButtonSegment(value: ThemeMode.dark, label: Text('深色'), icon: Icon(Icons.dark_mode)),
                      ],
                      selected: {settings.themeMode},
                      onSelectionChanged: (modes) => ref.read(settingsProvider.notifier).setThemeMode(modes.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 配色方案
                  const Text('配色方案'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final palette in AppPalette.all)
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => ref.read(settingsProvider.notifier).setThemeSeed(palette.id),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Column(
                                children: [
                                  Container(
                                    height: 40,
                                    margin: const EdgeInsets.symmetric(horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: palette.seed,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: s.themeSeed == palette.id
                                            ? Theme.of(context).colorScheme.onSurface
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: palette.accent,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    palette.name,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: s.themeSeed == palette.id
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 阅读设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('阅读设置', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  // 字体大小
                  Row(children: [
                    const Text('字体大小'),
                    const Spacer(),
                    Text('${s.fontSize.toInt()}px', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  Slider(
                    value: s.fontSize,
                    min: AppConstants.minFontSize,
                    max: AppConstants.maxFontSize,
                    divisions: (AppConstants.maxFontSize - AppConstants.minFontSize).toInt(),
                    label: '${s.fontSize.toInt()}px',
                    onChanged: (v) => ref.read(settingsProvider.notifier).setFontSize(v),
                  ),
                  // 左右边距
                  Row(children: [
                    const Text('左右边距'),
                    const Spacer(),
                    Text('${s.marginSize.toInt()}px', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  Slider(
                    value: s.marginSize,
                    min: AppConstants.minMargin,
                    max: AppConstants.maxMargin,
                    divisions: ((AppConstants.maxMargin - AppConstants.minMargin) / AppConstants.marginStep).toInt(),
                    label: '${s.marginSize.toInt()}px',
                    onChanged: (v) => ref.read(settingsProvider.notifier).setMarginSize(v),
                  ),
                  // 行间距
                  Row(children: [
                    const Text('行间距'),
                    const Spacer(),
                    Text(s.lineHeight.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  Slider(
                    value: s.lineHeight,
                    min: AppConstants.minLineHeight,
                    max: AppConstants.maxLineHeight,
                    divisions: ((AppConstants.maxLineHeight - AppConstants.minLineHeight) / AppConstants.lineHeightStep).toInt(),
                    label: s.lineHeight.toStringAsFixed(1),
                    onChanged: (v) => ref.read(settingsProvider.notifier).setLineHeight(v),
                  ),
                  // 阅读主题
                  const SizedBox(height: 8),
                  const Text('阅读主题'),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: [
                        for (final t in kReaderThemes)
                          ButtonSegment(
                            value: t.id,
                            label: Text(t.name),
                            icon: Icon(
                              Icons.circle,
                              size: 12,
                              color: t.background,
                            ),
                          ),
                      ],
                      selected: {s.readerTheme},
                      onSelectionChanged: (modes) =>
                          ref.read(settingsProvider.notifier).setReaderTheme(modes.first),
                    ),
                  ),
                  // 繁简显示（阅读器内也可快捷切换）
                  const SizedBox(height: 12),
                  const Text('繁简显示'),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'original', label: Text('原文')),
                        ButtonSegment(value: 'simplified', label: Text('简体')),
                        ButtonSegment(value: 'traditional', label: Text('繁体')),
                      ],
                      selected: {s.readerZhVariant},
                      onSelectionChanged: (modes) => ref
                          .read(settingsProvider.notifier)
                          .setReaderZhVariant(modes.first),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 导入设置
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('导入设置', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('导入后删除原文件'),
                    subtitle: const Text('导入成功后删除源文件（不可恢复）'),
                    value: s.deleteAfterImport,
                    onChanged: (v) => ref.read(settingsProvider.notifier).setDeleteAfterImport(v),
                  ),
                  // 默认编码（TXT 导入解码；自动= UTF-8→GBK→Big5 探测）
                  ListTile(
                    title: const Text('TXT 默认编码'),
                    subtitle: const Text('乱码时可手动指定 GBK / Big5 等编码重新导入'),
                    trailing: DropdownButton<String>(
                      value: TextDecode.encodingOptions
                              .any((o) => o.$1 == s.defaultEncoding)
                          ? s.defaultEncoding
                          : 'auto',
                      items: [
                        for (final (value, label) in TextDecode.encodingOptions)
                          DropdownMenuItem(value: value, child: Text(label)),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          ref.read(settingsProvider.notifier).setDefaultEncoding(v);
                        }
                      },
                    ),
                  ),
                  // 书库根目录（跨系统共享数据库：书籍路径存相对形式）
                  if (!PlatformUtils.isWeb && !PlatformUtils.isMobile)
                    ListTile(
                      leading: const Icon(Icons.folder_shared_outlined),
                      title: const Text('书库根目录（跨系统共享）'),
                      subtitle: Text(
                        s.libraryRootPath.isEmpty
                            ? '未设置：书籍路径按绝对路径存储'
                            : '路径基准：${s.libraryRootPath}',
                        style: TextStyle(
                          fontSize: 12,
                          color: s.libraryRootPath.isEmpty
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : AppColors.success,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _handleSetLibraryRoot(context, ref),
                    ),
                  // 默认导出格式
                  ListTile(
                    title: const Text('默认导出格式'),
trailing: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'txt', label: Text('TXT')),
                          ButtonSegment(value: 'epub', label: Text('EPUB')),
                          ButtonSegment(value: 'pdf', label: Text('PDF')),
                        ],
                        selected: {s.defaultExportFormat},
                        onSelectionChanged: (v) => ref.read(settingsProvider.notifier).setDefaultExportFormat(v.first),
                      ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 数据管理
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('数据管理', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  // 书源管理
                  ListTile(
                    leading: const Icon(Icons.travel_explore),
                    title: const Text('书源管理'),
                    subtitle: const Text('配置爬虫书源规则'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showBookSourceManager(context),
                  ),
                  // 以下条目依赖本地文件系统，仅桌面端显示
                  if (!PlatformUtils.isWeb) ...[
                    const Divider(),
                    // 书库文件夹配置
                    ListTile(
                      leading: const Icon(Icons.folder_copy_outlined),
                      title: const Text('书库文件夹'),
                      subtitle: Text(
                        s.libraryFolders.isEmpty
                            ? '未配置，首页「扫描书库」不可用'
                            : '已配置 ${s.libraryFolders.length} 个文件夹',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _handleManageLibraryFolders(context, ref, s.libraryFolders),
                    ),
                    const Divider(),
                    // 数据库路径配置
                    ListTile(
                      leading: const Icon(Icons.storage),
                      title: const Text('数据库路径'),
                      subtitle: Text(
                        s.customDbPath.isEmpty
                            ? '使用默认路径（仅本机可用）'
                            : s.customDbPath,
                        style: TextStyle(
                          color: s.customDbPath.isEmpty
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : AppColors.success,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _handleSetDbPath(context, ref, s.customDbPath),
                    ),
                    const Divider(),
                    // 缓存清理
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: const Text('清理缓存'),
                      subtitle: cache.isLoading
                          ? const LinearProgressIndicator()
                          : Text(
                              cache.cacheSize > 0
                                  ? '临时文件与缓存占用 ${_formatCacheSize(cache.cacheSize)}'
                                  : '当前无缓存可清理',
                              style: TextStyle(
                                color: cache.cacheSize > 0
                                    ? Theme.of(context).colorScheme.onSurfaceVariant
                                    : AppColors.success,
                              ),
                            ),
                      trailing: cache.isClearing
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: cache.isClearing || cache.cacheSize == 0
                          ? null
                          : () => _handleClearCache(context, ref),
                    ),
                    const Divider(),
                    if (backup.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(backup.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    ListTile(
                      leading: const Icon(Icons.backup),
                      title: const Text('备份数据库'),
                      subtitle: backup.isBackingUp
                          ? const LinearProgressIndicator()
                          : null,
                      trailing: backup.isBackingUp
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: backup.isBackingUp ? null : () => _handleBackup(context, ref),
                    ),
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('恢复数据库'),
                      subtitle: backup.isRestoring
                          ? const LinearProgressIndicator()
                          : null,
                      trailing: backup.isRestoring
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: backup.isRestoring ? null : () => _handleRestore(context, ref),
                    ),
                    // 备份列表
                    if (backup.backups.isNotEmpty) ...[
                      const Divider(),
                      Text('最近的备份', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
                      const SizedBox(height: 4),
                      ...backup.backups.take(5).map((b) => ListTile(
                        dense: true,
                        title: Text(b.fileName, style: Theme.of(context).textTheme.bodySmall),
                        subtitle: Text('${b.formattedSize} · ${_formatDate(b.modifiedTime)}', style: Theme.of(context).textTheme.bodySmall),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _handleDeleteBackup(context, ref, b.path),
                        ),
                      )),
                    ],
                  ] else ...[
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Web 端：数据保存在浏览器 IndexedDB 中（清空站点数据会丢失），请定期备份。'
                              '备份为 SQL 文件，可恢复到 Web 端或导入桌面端。书库扫描与缓存清理请在桌面端使用。',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 备份数据库（SQL dump，浏览器下载）
                    ListTile(
                      leading: const Icon(Icons.backup),
                      title: const Text('备份数据库（下载 SQL）'),
                      subtitle: backup.isBackingUp
                          ? const LinearProgressIndicator()
                          : const Text('导出全部书籍/章节/进度/书签/笔记为 .sql 文件'),
                      trailing: backup.isBackingUp
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: backup.isBackingUp ? null : () => _handleBackupSql(context, ref),
                    ),
                    // 恢复数据库（上传 SQL）
                    ListTile(
                      leading: const Icon(Icons.restore),
                      title: const Text('恢复数据库（上传 SQL）'),
                      subtitle: backup.isRestoring
                          ? const LinearProgressIndicator()
                          : const Text('清空当前数据并导入备份文件（不可撤销）'),
                      trailing: backup.isRestoring
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.chevron_right),
                      onTap: backup.isRestoring ? null : () => _handleRestoreSql(context, ref),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 关于
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('关于', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const ListTile(
                    leading: Icon(Icons.menu_book),
                    title: Text('YYX书库（YYX Library）'),
                    subtitle: Text('版本 1.0.3 · 开源许可 BSD-3-Clause'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 设置页自适应布局:宽屏双列卡片 + 居中限宽,窄屏单列
  static Widget _adaptiveBody(BuildContext context, List<Widget> cards) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: LayoutBuilder(
          builder: (context, cons) {
            final wide = cons.maxWidth >= 900;
            if (!wide) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: cards,
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  // 双列时过滤掉单列布局用的间隔占位
                  for (final card in cards)
                    if (card is! SizedBox)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: (cons.maxWidth - 44) / 2),
                        child: card,
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 书源管理对话框:列表 + 新增/编辑/删除/恢复默认
  Future<void> _showBookSourceManager(BuildContext context) async {
    final store = BookSourceStore();
    await store.initialize();

    Future<void> showEditDialog({BookSource? existing}) async {
      final nameCtrl = TextEditingController(text: existing?.name ?? '');
      final baseCtrl = TextEditingController(text: existing?.baseUrl ?? '');
      final searchCtrl = TextEditingController(text: existing?.search?.url ?? '');
      final searchListCtrl = TextEditingController(
          text: existing?.search?.listSelector ?? 'table.result-item');
      final tocListCtrl = TextEditingController(
          text: existing?.toc.listSelector ?? 'div#list dl dd a');
      final contentSelCtrl = TextEditingController(
          text: existing?.content.selector ?? 'div#content');

      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(existing == null ? '添加书源' : '编辑书源'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl,
                      decoration: const InputDecoration(labelText: '名称 *', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: baseCtrl,
                      decoration: const InputDecoration(labelText: '站点地址 * (https://...)', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: searchCtrl,
                      decoration: const InputDecoration(
                          labelText: '搜索 URL (含 {{key}})',
                          hintText: '留空则该书源不支持搜索',
                          border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: searchListCtrl,
                      decoration: const InputDecoration(labelText: '搜索列表选择器', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: tocListCtrl,
                      decoration: const InputDecoration(labelText: '目录章节选择器', border: OutlineInputBorder(), isDense: true)),
                  const SizedBox(height: 8),
                  TextField(controller: contentSelCtrl,
                      decoration: const InputDecoration(labelText: '正文选择器', border: OutlineInputBorder(), isDense: true)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || baseCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('名称和站点地址必填')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      );
      if (saved != true) return;

      final source = BookSource(
        name: nameCtrl.text.trim(),
        baseUrl: baseCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
        search: searchCtrl.text.trim().isEmpty
            ? null
            : SearchRule(
                url: searchCtrl.text.trim(),
                listSelector: searchListCtrl.text.trim(),
                title: 'a@title',
                urlRule: 'a@href',
                author: 'td.author',
              ),
        toc: TocRule(
          url: '{{bookUrl}}',
          listSelector: tocListCtrl.text.trim(),
        ),
        content: ContentRule(selector: contentSelCtrl.text.trim()),
      );
      await store.upsert(source);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('书源「${source.name}」已保存')));
      }
    }

    // 主对话框
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final sources = store.getAll();
          return AlertDialog(
            title: const Text('书源管理'),
            content: SizedBox(
              width: 440,
              height: 400,
              child: sources.isEmpty
                  ? const Center(child: Text('暂无书源'))
                  : ListView.builder(
                      itemCount: sources.length,
                      itemBuilder: (_, i) {
                        final s = sources[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            s.enabled ? Icons.link : Icons.link_off,
                            color: s.enabled ? AppColors.success : AppColors.hintText,
                          ),
                          title: Text(s.name),
                          subtitle: Text(
                            s.baseUrl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: '编辑',
                                onPressed: () async {
                                  await showEditDialog(existing: s);
                                  setState(() {});
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: '删除',
                                onPressed: () async {
                                  await store.remove(s.name);
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await store.resetToDefaults();
                  setState(() {});
                },
                child: const Text('恢复默认'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await showEditDialog();
                  setState(() {});
                },
                icon: const Icon(Icons.add),
                label: const Text('添加书源'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleClearCache(BuildContext context, WidgetRef ref) async {
    final cache = ref.read(cacheProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: Text(
          '将删除临时文件与缓存，共 ${_formatCacheSize(cache.cacheSize)}。\n\n'
          '数据库与设置不受影响。此操作不可撤销。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('清理')),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final result = await ref.read(cacheProvider.notifier).clear();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? '缓存已清理，释放 ${result.formattedFreed}（${result.removedFiles} 个文件）'
                : '清理完成，但 ${result.errors.length} 个文件失败',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理缓存失败: $e')),
        );
      }
    }
  }

  String _formatCacheSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleBackup(BuildContext context, WidgetRef ref) async {
    try {
      final path = await ref.read(backupProvider.notifier).backup();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份成功: $path')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e')),
        );
      }
    }
  }

  /// 设置书库根目录（跨系统共享数据库）：选目录后询问是否把已有绝对路径迁移为相对
  Future<void> _handleSetLibraryRoot(BuildContext context, WidgetRef ref) async {
    final root = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择书库根目录（小说库所在目录）',
    );
    if (root == null || !context.mounted) return;

    await ref.read(settingsProvider.notifier).setLibraryRootPath(root);

    if (!context.mounted) return;

    // 迁移历史路径：分析库内绝对路径，识别可能的旧系统库根（如 macOS 路径）
    try {
      final analysis = await ref.read(databaseServiceProvider).analyzeBookPaths();
      if (!context.mounted) return;
      if (analysis.absoluteCount > 0) {
        final selected = <String>{};
        final migrate = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setState) => AlertDialog(
              title: const Text('转换已有路径'),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('书库中有 ${analysis.absoluteCount} 条绝对路径、${analysis.relativeCount} 条相对路径。'
                        '跨系统共享数据库需要相对路径。'),
                    const SizedBox(height: 12),
                    const Text('检测到以下可能的旧库根目录（勾选后一并转换）：',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ...analysis.suggestedRoots.map((r) => CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(PlatformFs.nativeSeparators(r),
                              style: const TextStyle(fontSize: 12)),
                          value: selected.contains(r),
                          onChanged: (v) => setState(() =>
                              v == true ? selected.add(r) : selected.remove(r)),
                        )),
                    const SizedBox(height: 4),
                    Text('位于「$root」及勾选目录下的路径将转为相对形式，其余保持不变。',
                        style: const TextStyle(fontSize: 12),
                        ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('暂不')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('转换')),
              ],
            ),
          ),
        );
        if (migrate == true && context.mounted) {
          final count = await ref.read(databaseServiceProvider).relativizeBookPaths(
                root,
                legacyRoots: selected.toList(),
              );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已转换 $count 条书籍路径为相对路径')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('路径分析失败: $e')),
        );
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书库根目录已更新')),
      );
    }
  }

  /// Web 端备份：导出 SQL dump 并触发浏览器下载
  Future<void> _handleBackupSql(BuildContext context, WidgetRef ref) async {
    try {
      final sql = await ref.read(backupProvider.notifier).backupSql();
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final fileName = 'novelmgt_backup_$ts.sql';
      await WebLauncher.downloadBytes(
        fileName,
        utf8.encode(sql),
        mimeType: 'application/sql',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份已下载: $fileName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e')),
        );
      }
    }
  }

  /// Web 端恢复：上传 SQL 备份文件并导入（清空当前库）
  Future<void> _handleRestoreSql(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复数据库'),
        content: const Text('警告：恢复将清空当前全部数据（书籍/章节/进度/书签/笔记），导入备份文件内容。此操作不可撤销。\n\n请选择 .sql 备份文件继续。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('继续')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['sql'],
        withData: true,
        dialogTitle: '选择 SQL 备份文件',
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) return;

      await ref.read(backupProvider.notifier).restoreSql(utf8.decode(bytes));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('恢复成功，请刷新页面（或重启应用）以刷新界面数据')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败: $e')),
        );
      }
    }
  }

  Future<void> _handleRestore(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复数据库'),
        content: const Text('警告：恢复操作将覆盖当前数据库，此操作不可撤销。\n\n请选择备份文件继续。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('继续')),
        ],
      ),
    );

    if (confirmed != true) return;

    // 选择备份文件
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['db'],
      dialogTitle: '选择备份文件',
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    try {
      await ref.read(backupProvider.notifier).restore(filePath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('恢复成功，请重启应用以生效')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败: $e')),
        );
      }
    }
  }

  Future<void> _handleDeleteBackup(BuildContext context, WidgetRef ref, String path) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除备份'),
        content: const Text('确定要删除此备份吗？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删除')),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(backupProvider.notifier).deleteBackup(path);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('备份已删除')),
        );
      }
    }
  }

  Future<void> _handleSetDbPath(BuildContext context, WidgetRef ref, String currentPath) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置数据库路径'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('设置自定义数据库路径可以让 macOS、Windows、NAS 等设备共享同一个数据库。'),
            const SizedBox(height: 12),
            const Text('⚠️ 注意：', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('• 修改路径后需要重启应用'),
            const Text('• 网络路径(NAS)可能有性能问题'),
            const Text('• 请确保路径有读写权限'),
            const SizedBox(height: 12),
            Text('当前路径：${currentPath.isEmpty ? "默认" : currentPath}',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          if (currentPath.isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('恢复默认'),
            ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop('select');
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('选择文件夹'),
          ),
        ],
      ),
    );

    if (result == null) return;
    
    if (result == '') {
      // 恢复默认
      await ref.read(settingsProvider.notifier).setCustomDbPath('');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已恢复默认路径，重启应用生效')),
        );
      }
    } else if (result == 'select') {
      // 选择文件夹
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择数据库存储位置',
      );
      if (path != null) {
        await ref.read(settingsProvider.notifier).setCustomDbPath(path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('路径已设置: $path，重启应用生效')),
          );
        }
      }
    }
  }

  /// 管理书库文件夹（可多个）：设置页 → 书库文件夹
  Future<void> _handleManageLibraryFolders(BuildContext context, WidgetRef ref, List<String> current) async {
    final folders = List<String>.from(current);
    final manualCtrl = TextEditingController();

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('书库文件夹'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '首页「扫描书库」会遍历以下文件夹，自动导入新书与更新章节。'
                  '支持相对路径（以程序所在目录为基准，如 novels、H），跨系统共用同一份配置；'
                  'OneDrive 未物化（占位）文件会自动跳过。',
                  style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 240,
                  child: folders.isEmpty
                      ? Center(
                          child: Text(
                            '尚未添加书库文件夹',
                            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          itemCount: folders.length,
                          itemBuilder: (_, i) {
                            final stored = folders[i];
                            final resolved = PlatformFs.resolvePath(stored);
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.folder, size: 20),
                              title: Text(stored, style: const TextStyle(fontSize: 12)),
                              // 相对路径显示解析后的实际位置（以程序目录为基准）
                              subtitle: stored != resolved
                                  ? Text('→ $resolved',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(ctx).colorScheme.onSurfaceVariant))
                                  : null,
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18),
                                tooltip: '移除',
                                onPressed: () => setDialogState(() => folders.removeAt(i)),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 12),
                // 手动输入（支持相对路径，如 novels、H —— 以程序所在目录为基准，
                // 跨系统共用同一份配置）
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: manualCtrl,
                        decoration: const InputDecoration(
                          hintText: '相对路径（如 novels）或绝对路径',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: () {
                        final v = manualCtrl.text.trim();
                        if (v.isNotEmpty && !folders.contains(v)) {
                          setDialogState(() => folders.add(v));
                          manualCtrl.clear();
                        }
                      },
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final path = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: '选择书库文件夹',
                    );
                    if (path != null) {
                      setDialogState(() {
                        if (!folders.contains(path)) folders.add(path);
                      });
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('浏览选择文件夹'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );

    if (shouldSave == true) {
      await ref.read(settingsProvider.notifier).setLibraryFolders(folders);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('书库文件夹已保存')),
        );
      }
    }
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}