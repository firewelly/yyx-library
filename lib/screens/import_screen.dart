import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../providers/database_provider.dart';
import '../providers/import_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import '../services/database_service.dart';
import '../services/import_service.dart';
import '../services/platform_fs.dart';
import '../models/book.dart';
import '../models/models.dart';
import '../theme/app_colors.dart';
import '../utils/platform_utils.dart';

/// 导入页面
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  bool _recursive = false;
  late bool _deleteAfter;
  String? _selectedPath;
  String? _errorMessage;
  List<String> _selectedFiles = [];
  /// Web 端选择的文件（file_picker 在 Web 上只有字节没有路径）
  final List<PlatformFile> _webFiles = [];
  late bool _isFolderMode;

  @override
  void initState() {
    super.initState();
    // 从全局设置读取默认值
    _deleteAfter = ref.read(settingsProvider).settings.deleteAfterImport;
    // Web 端无文件夹访问能力，固定文件模式
    _isFolderMode = !PlatformUtils.isWeb;
  }

  /// 当前待导入文件的名字列表（桌面=路径，Web=文件名）
  List<String> get _displayNames =>
      PlatformUtils.isWeb ? [for (final f in _webFiles) f.name] : _selectedFiles;

  void _removeSelectedAt(int i) {
    if (PlatformUtils.isWeb) {
      _webFiles.removeAt(i);
    } else {
      _selectedFiles.removeAt(i);
    }
  }

  /// 手动添加书籍对话框（书名/作者/状态/评分/标签）
  Future<void> _showAddBookDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final authorCtrl = TextEditingController();
    final newTagCtrl = TextEditingController();
    String status = '连载中';
    int rating = 0;
    final selectedTags = <Tag>[];
    final db = ref.read(databaseServiceProvider);
    // 加载已有标签供选择
    var allTags = await db.getAllTags();
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('📖 手动添加小说'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '书名 *',
                      hintText: '例如：凡人修仙传',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: authorCtrl,
                    decoration: const InputDecoration(
                      labelText: '作者',
                      hintText: '例如：忘语',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: '状态', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: '连载中', child: Text('连载中')),
                      DropdownMenuItem(value: '已完结', child: Text('已完结')),
                    ],
                    onChanged: (v) => setState(() => status = v ?? status),
                  ),
                  const SizedBox(height: 12),
                  // 评分（星形点击）
                  Row(
                    children: [
                      const Text('评分: '),
                      ...List.generate(5, (i) => IconButton(
                        icon: Icon(
                          i < rating ? Icons.star : Icons.star_border,
                          size: 22,
                          color: i < rating ? AppColors.ratingStar : AppColors.emptyState,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => setState(() => rating = i + 1),
                      )),
                      if (rating > 0)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 14, color: AppColors.hintText),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                          tooltip: '清除评分',
                          onPressed: () => setState(() => rating = 0),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 标签选择
                  Text('标签', style: Theme.of(ctx).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  // 新建标签
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newTagCtrl,
                          decoration: const InputDecoration(
                            hintText: '输入新标签名并回车/点击创建...',
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          onSubmitted: (_) => _createNewTag(ctx, setState, newTagCtrl, db, selectedTags, () async {
                            allTags = await db.getAllTags();
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: () => _createNewTag(ctx, setState, newTagCtrl, db, selectedTags, () async {
                          allTags = await db.getAllTags();
                        }),
                        child: const Text('创建'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (allTags.isNotEmpty)
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: allTags.map((tag) {
                        final selected = selectedTags.any((t) => t.id == tag.id);
                        return FilterChip(
                          label: Text(tag.name),
                          selected: selected,
                          onSelected: (on) => setState(() {
                            if (on) {
                              selectedTags.add(tag);
                            } else {
                              selectedTags.removeWhere((t) => t.id == tag.id);
                            }
                          }),
                        );
                      }).toList(),
                    )
                  else
                    const Text('暂无已有标签，保存后可在详情页添加', style: TextStyle(color: AppColors.hintText, fontSize: 12)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                if (title.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请输入书名')),
                  );
                  return;
                }
                Navigator.pop(dialogCtx);
                final now = DateTime.now().toIso8601String();
                await db.createBook(Book(
                  title: title,
                  author: authorCtrl.text.trim().isEmpty ? null : authorCtrl.text.trim(),
                  status: status,
                  rating: rating,
                  wordCount: 0,
                  sourceFormat: 'manual',
                  createdAt: now,
                  updatedAt: now,
                  tags: selectedTags,
                ));
                // 刷新书库
                unawaited(ref.read(libraryProvider.notifier).refresh());
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已添加《$title》')),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 在手动添加对话框里创建新标签
  Future<void> _createNewTag(
    BuildContext ctx,
    StateSetter setState,
    TextEditingController ctrl,
    DatabaseService db,
    List<Tag> selectedTags,
    Future<void> Function() refreshAll,
  ) async {
    final name = ctrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请输入标签名')));
      return;
    }
    try {
      final tag = await db.createTag(name);
      ctrl.clear();
      setState(() => selectedTags.add(tag));
      await refreshAll();
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('标签「$name」已创建')));
    } catch (e) {
      // 标签已存在等情况
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('创建标签失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(importProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('📥 导入小说')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 手动添加书籍
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('没有文件要导入？', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            '手动添加一本书，然后给它设置状态、标签和评分',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: () => _showAddBookDialog(context),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('手动添加'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 模式切换（Web 端无文件夹访问，固定文件模式，不显示切换）
            if (!PlatformUtils.isWeb) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('导入方式', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            label: Text('选择文件夹'),
                            icon: Icon(Icons.folder_open),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text('选择文件'),
                            icon: Icon(Icons.description),
                          ),
                        ],
                        selected: {_isFolderMode},
                        onSelectionChanged: (v) => setState(() {
                          _isFolderMode = v.first;
                          _selectedPath = null;
                          _selectedFiles = [];
                          _errorMessage = null;
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 文件夹选择
            if (_isFolderMode) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('选择文件夹', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: _selectedPath ?? '点击右侧按钮选择文件夹',
                              child: TextField(
                                decoration: InputDecoration(
                                  hintText: '选择包含小说文件的文件夹...',
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  suffixIcon: const Icon(Icons.folder_open),
                                ),
                                controller: TextEditingController(text: _selectedPath ?? ''),
                                readOnly: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _pickFolder,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('浏览'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('递归查找子文件夹'),
                        subtitle: const Text('在所有子文件夹中搜索 TXT/EPUB/PDF/MOBI 文件'),
                        value: _recursive,
                        onChanged: (v) => setState(() => _recursive = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // 文件选择
            if (!_isFolderMode) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('选择文件', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _displayNames.isEmpty
                                  ? '未选择文件'
                                  : '已选择 ${_displayNames.length} 个文件',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _pickFiles,
                            icon: const Icon(Icons.file_open),
                            label: const Text('选择文件'),
                          ),
                        ],
                      ),
                      if (_displayNames.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 150),
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _displayNames.length,
                            itemBuilder: (_, i) => ListTile(
                              dense: true,
                              leading: Icon(
                                _fileIcon(_displayNames[i]),
                                size: 20,
                                color: _fileIconColor(context, _displayNames[i]),
                              ),
                              title: Text(
                                _displayNames[i].split(RegExp(r'[/\\]')).last,
                                style: const TextStyle(fontSize: 13),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() => _removeSelectedAt(i)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // 选项（导入后删除原文件仅桌面文件夹/文件导入有意义）
            if (!PlatformUtils.isWeb)
              Card(
                child: SwitchListTile(
                  title: const Text('导入后删除原文件'),
                  subtitle: const Text('导入成功后删除源文件（不可恢复）'),
                  value: _deleteAfter,
                  onChanged: (v) => setState(() => _deleteAfter = v),
                ),
              ),
            const SizedBox(height: 16),

            // 错误提示
            if (_errorMessage != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                      ),
                    ],
                  ),
                ),
              ),

            // 导入按钮
            if (_canImport())
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: state.isImporting ? null : _startImport,
                    icon: state.isImporting
                        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary))
                        : const Icon(Icons.upload_file),
                    label: Text(state.isImporting ? '导入中...' : '开始导入'),
                  ),
                ),
              ),

            // 进度
            if (state.isImporting) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 8),
              Text(state.statusMessage, style: theme.textTheme.bodySmall),
            ],

            // 单文件导入结果
            if (state.lastResult != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            state.lastResult!.success ? Icons.check_circle : Icons.error_outline,
                            color: state.lastResult!.success ? AppColors.success : theme.colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              state.lastResult!.success ? '导入成功' : '导入失败',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(state.lastResult!.message,
                          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            ref.read(libraryProvider.notifier).refresh();
                            context.go('/');
                          },
                          icon: const Icon(Icons.home),
                          label: const Text('返回书架'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // 批量导入结果
            if (state.batchResult != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            state.batchResult!.failed == 0 ? Icons.check_circle : Icons.warning,
                            color: state.batchResult!.failed == 0 ? AppColors.success : AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '导入完成: 成功 ${state.batchResult!.succeeded}, 失败 ${state.batchResult!.failed}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      if (state.batchResult!.errors.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text('失败详情:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ...state.batchResult!.errors.take(5).map((e) => Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(e, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
                        )),
                        if (state.batchResult!.errors.length > 5)
                          Text('...还有 ${state.batchResult!.errors.length - 5} 个错误', style: const TextStyle(fontSize: 11, color: AppColors.hintText)),
                      ],
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            ref.read(libraryProvider.notifier).refresh();
                            context.go('/');
                          },
                          icon: const Icon(Icons.home),
                          label: const Text('返回书架'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            if (state.error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(state.error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _canImport() {
    if (_isFolderMode) return _selectedPath != null;
    return _displayNames.isNotEmpty;
  }

  /// 选择文件夹（仅桌面端；Web 端入口已隐藏）
  Future<void> _pickFolder() async {
    setState(() => _errorMessage = null);
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择包含小说的文件夹',
      );
      if (result != null) {
        // 验证文件夹存在并统计可导入文件数(支持 TXT/EPUB/PDF/MOBI/AZW/AZW3)
        if (await PlatformFs.dirExists(result)) {
          final files = await PlatformFs.listFiles(
            result,
            recursive: _recursive,
            extensions: kSupportedImportExtensions.toSet(),
            skipZeroByte: true,
          );
          setState(() {
            _selectedPath = result;
            if (files.isEmpty) {
              _errorMessage = '该文件夹中没有找到可导入的文件(TXT/EPUB/PDF/MOBI)';
            }
          });
        }
      }
    } catch (e) {
      setState(() => _errorMessage = '选择文件夹失败: $e');
    }
  }

  Future<void> _pickFiles() async {
    setState(() => _errorMessage = null);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'epub', 'pdf', 'mobi', 'azw', 'azw3'],
        allowMultiple: true,
        withData: PlatformUtils.isWeb, // Web 端必须读取字节（无路径可用）
        dialogTitle: '选择小说文件（TXT/EPUB/PDF/MOBI）',
      );
      if (result != null && result.files.isNotEmpty) {
        if (PlatformUtils.isWeb) {
          // Web 端：file_picker 只提供 bytes（访问 path 会抛异常）
          final picked = result.files.where((f) => f.bytes != null).toList();
          setState(() => _webFiles
            ..clear()
            ..addAll(picked));
        } else {
          setState(() {
            _selectedFiles = result.files
                .where((f) => f.path != null)
                .map((f) => f.path!)
                .toList();
          });
        }
      }
    } catch (e) {
      setState(() => _errorMessage = '选择文件失败: $e');
    }
  }

  void _startImport() {
    if (_isFolderMode && _selectedPath != null) {
      ref.read(importProvider.notifier).importFolder(
        _selectedPath!,
        recursive: _recursive,
        deleteAfter: _deleteAfter,
      );
    } else if (!_isFolderMode && _displayNames.isNotEmpty) {
      _importSelectedFiles();
    }
  }

  Future<void> _importSelectedFiles() async {
    if (PlatformUtils.isWeb) {
      // Web 端：按字节导入（file_picker 只提供 bytes）
      for (final f in _webFiles) {
        await ref.read(importProvider.notifier).importBytes(f.name, f.bytes!);
      }
      return;
    }
    for (final file in _selectedFiles) {
      // 统一入口:自动按扩展名分派到 TXT/EPUB/PDF/MOBI 导入器
      await ref.read(importProvider.notifier).importFile(file);
    }
  }

  /// 根据文件扩展名返回对应图标
  IconData _fileIcon(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.epub')) return Icons.menu_book;
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.mobi') || lower.endsWith('.azw') || lower.endsWith('.azw3')) {
      return Icons.tablet_mac;
    }
    return Icons.description; // TXT
  }

  /// 文件图标颜色(按格式区分)
  Color _fileIconColor(BuildContext context, String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return const Color(0xFFDC2626); // PDF 红
    if (lower.endsWith('.mobi') || lower.endsWith('.azw') || lower.endsWith('.azw3')) {
      return const Color(0xFFFF6E40); // Kindle 橙
    }
    if (lower.endsWith('.epub')) return const Color(0xFF16A34A); // EPUB 绿
    return Theme.of(context).colorScheme.primary; // TXT 用主色
  }
}
