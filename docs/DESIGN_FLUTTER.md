# 小说管理系统 Flutter 版 - 架构设计文档

## 文档信息

| 项目 | 内容 |
|------|------|
| **文档版本** | 1.0 |
| **创建时间** | 2026-04-08 |
| **技术栈** | Flutter 3.x + Riverpod + sqflite/Hive + dio |

---

## 1. 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter UI Layer                        │
│  ┌──────────┬───────────┬───────────┬───────────────────┐  │
│  │ Screens  │  Widgets   │  Router   │   Theme (M3)      │  │
│  └──────────┴───────────┴───────────┴───────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                  Riverpod State Layer                       │
│  ┌──────────┬────────────┬──────────┬─────────────────┐   │
│  │ Library  │ Reader      │ Settings │ Import/Export    │   │
│  │ Notifier │ Notifier    │ Notifier │ Notifier         │   │
│  └──────────┴────────────┴──────────┴─────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                   Service Layer (DI)                        │
│  ┌──────────┬────────────┬──────────┬─────────────────┐   │
│  │ Database │ Settings   │ Import   │ Export           │   │
│  │ Service  │ Service    │ Service  │ Service          │   │
│  ├──────────┼────────────┼──────────┼─────────────────┤   │
│  │ NAS Api  │ Chapter    │ Scraper  │ Backup           │   │
│  │ Client   │ Parser     │ Service  │ Service          │   │
│  └──────────┴────────────┴──────────┴─────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Data Access Layer                         │
│  ┌──────────────────┬────────────────────────────────────┐ │
│  │ sqflite (结构化)  │ Hive (偏好设置)                    │ │
│  │ books/chapters/  │ theme/fontSize/                   │ │
│  │ tags/bookmarks/  │ margin/lineHeight/                │ │
│  │ notes/progress   │ scraperConfig/...                 │ │
│  └──────────────────┴────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    Platform Layer                            │
│  ┌──────────────────┬────────────────────────────────────┐ │
│  │ File I/O (dart:io)│ Network (dio)                     │ │
│  │ file_picker       │ epubx / charset_detect             │ │
│  └──────────────────┴────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 2. 目录结构

```
novelmgt_flutter/
├── lib/
│   ├── main.dart                     # 应用入口
│   ├── app.dart                      # MaterialApp 配置
│   ├── router/                       # 路由
│   │   └── app_router.dart           # go_router 配置
│   ├── models/                       # 数据模型
│   │   ├── book.dart                 # 书籍模型
│   │   ├── chapter.dart              # 章节模型
│   │   ├── bookmark.dart             # 书签模型
│   │   ├── note.dart                 # 笔记模型
│   │   ├── tag.dart                  # 标签模型
│   │   ├── reading_progress.dart     # 阅读进度模型
│   │   └── app_settings.dart         # 设置模型
│   ├── services/                     # 服务层
│   │   ├── database_service.dart     # sqflite 数据库服务
│   │   ├── settings_service.dart     # Hive 偏好服务
│   │   ├── import_service.dart       # 导入服务 (TXT/EPUB)
│   │   ├── export_service.dart       # 导出服务
│   │   ├── chapter_parser.dart       # 章节解析器
│   │   ├── nas_api_client.dart       # NAS API (预留)
│   │   └── backup_service.dart       # 备份服务
│   ├── providers/                    # Riverpod 状态
│   │   ├── library_provider.dart     # 书库状态
│   │   ├── reader_provider.dart      # 阅读器状态
│   │   ├── settings_provider.dart    # 设置状态
│   │   ├── import_provider.dart      # 导入状态
│   │   └── stats_provider.dart       # 统计状态
│   ├── screens/                      # 页面
│   │   ├── home_screen.dart          # 主页(书籍列表)
│   │   ├── book_detail_screen.dart   # 书籍详情
│   │   ├── reader_screen.dart        # 阅读器
│   │   ├── import_screen.dart        # 导入页
│   │   ├── settings_screen.dart      # 设置页
│   │   ├── stats_screen.dart         # 统计页
│   │   └── scraper_screen.dart       # 爬取页
│   ├── widgets/                      # 可复用组件
│   │   ├── responsive_layout.dart    # 响应式布局
│   │   ├── book_grid_view.dart       # 书籍网格视图
│   │   ├── book_list_view.dart       # 书籍列表视图
│   │   ├── book_card.dart            # 书籍卡片
│   │   ├── chapter_grid.dart         # 章节网格
│   │   ├── reading_progress_bar.dart # 阅读进度条
│   │   ├── tag_chip.dart             # 标签芯片
│   │   ├── search_bar.dart           # 搜索栏
│   │   └── shortcut_handler.dart     # 键盘快捷键
│   ├── theme/                        # 主题
│   │   ├── app_theme.dart            # Material 3 主题定义
│   │   └── app_colors.dart           # 色彩系统
│   └── utils/                        # 工具
│       ├── constants.dart            # 常量
│       ├── formatters.dart           # 格式化工具
│       └── platform_utils.dart       # 平台适配
├── test/
│   ├── unit/
│   │   ├── database_service_test.dart
│   │   ├── settings_service_test.dart
│   │   ├── import_service_test.dart
│   │   ├── export_service_test.dart
│   │   ├── models_test.dart
│   │   └── chapter_parser_test.dart
│   ├── widgets/
│   │   ├── book_grid_view_test.dart
│   │   ├── book_list_view_test.dart
│   │   ├── responsive_layout_test.dart
│   │   └── search_bar_test.dart
│   └── integration/
│       └── app_test.dart
├── integration_test/
│   └── full_flow_test.dart
├── pubspec.yaml
├── analysis_options.yaml
├── windows/                       # Windows 桌面配置
├── macos/                         # macOS 桌面配置
├── linux/                         # Linux 桌面配置
└── web/                           # Web 配置
```

## 3. 核心设计模式

### 3.1 依赖注入（Riverpod）

```dart
// 通过 Riverpod Provider 实现依赖注入
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final libraryProvider = AsyncNotifierProvider<LibraryNotifier, LibraryState>(() {
  return LibraryNotifier();
});
```

所有 Service 通过 Provider 注入，单元测试时替换为 Mock。

### 3.2 分层职责

| 层级 | 职责 | 依赖方向 |
|------|------|---------|
| **UI Layer** | 页面渲染、用户交互、事件处理 | → Provider |
| **Provider Layer** | 状态管理、业务编排、数据转换 | → Service |
| **Service Layer** | 数据库操作、文件IO、网络请求 | → Model / Platform |
| **Model Layer** | 数据结构定义、序列化 | 无外部依赖 |

### 3.3 状态管理策略

- **LibraryState**: 书籍列表、筛选条件、排序方式、搜索关键词
- **ReaderState**: 当前书籍、当前章节、滚动位置、阅读设置
- **SettingsState**: 主题模式、字体大小、边距、爬虫配置
- **ImportState**: 导入进度、导入结果、文件列表

使用 `@riverpod` 注解 + `riverpod_generator` 生成代码，避免样板代码。

### 3.4 数据库版本迁移

```dart
// DatabaseService 中处理迁移
static const _migrations = <int, String>{
  1: 'CREATE TABLE books (...)',
  2: 'ALTER TABLE books ADD COLUMN cover_image_path TEXT',
  3: 'CREATE TABLE bookmarks (...)',
};
```

## 4. UI 设计规范

### 4.1 Material 3 主题

```dart
// 浅色主题
ColorScheme lightScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF1976D2), // Material Blue 700
  brightness: Brightness.light,
);

// 深色主题
ColorScheme darkScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFF90CAF9), // Material Blue 200
  brightness: Brightness.dark,
);
```

### 4.2 响应式布局断点

| 宽度 | 布局 | 说明 |
|------|------|------|
| < 600px | 单栏 | 手机/窄屏 |
| 600-1200px | 双栏 | 列表+详情 |
| > 1200px | 三栏 | 导航+列表+详情 |

### 4.3 间距规范

| 名称 | 值 | 用途 |
|------|------|------|
| xs | 4px | 紧凑元素间距 |
| sm | 8px | 标签、小元素 |
| md | 16px | 卡片内容、列表项 |
| lg | 24px | 区域间距 |
| xl | 32px | 大区域间距 |

## 5. 服务接口设计

### 5.1 DatabaseService

```dart
abstract class DatabaseService {
  // 初始化
  Future<void> initialize();
  
  // Books
  Future<Book> createBook(Book book);
  Future<Book?> getBook(int id);
  Future<List<Book>> listBooks({int page = 1, int perPage = 20, ...});
  Future<Book> updateBook(Book book);
  Future<bool> deleteBook(int id);
  Future<List<Book>> searchBooks(String query, {bool searchContent = false});
  Future<Map<String, dynamic>> getStats();
  
  // Chapters
  Future<Chapter> createChapter(Chapter chapter);
  Future<List<Chapter>> getChapters(int bookId, {int page = 1, int perPage = 50});
  Future<Chapter> updateChapter(Chapter chapter);
  Future<bool> deleteChapter(int id);
  Future<List<Chapter>> searchChapters(int bookId, String query);
  
  // Tags
  Future<Tag> createTag(String name, {String color = '#1976D2'});
  Future<List<Tag>> getAllTags();
  Future<bool> deleteTag(int id);
  
  // ReadingProgress
  Future<ReadingProgress?> getProgress(int bookId);
  Future<ReadingProgress> updateProgress(int bookId, int chapterId, {int scrollPosition = 0});
  
  // Bookmarks
  Future<Bookmark> createBookmark(Bookmark bookmark);
  Future<List<Bookmark>> getBookmarks(int bookId);
  Future<bool> deleteBookmark(int id);
  
  // Notes
  Future<Note> createNote(Note note);
  Future<List<Note>> getNotesByBook(int bookId);
  Future<List<Note>> getNotesByChapter(int chapterId);
  Future<Note> updateNote(Note note);
  Future<bool> deleteNote(int id);
  
  // Backup
  Future<String> backupDatabase(String targetPath);
  Future<void> restoreDatabase(String sourcePath);
}
```

### 5.2 SettingsService

```dart
abstract class SettingsService {
  Future<void> initialize();
  
  // 主题
  ThemeMode get themeMode;
  Future<void> setThemeMode(ThemeMode mode);
  
  // 阅读设置
  double get fontSize;
  Future<void> setFontSize(double size);
  double get marginSize;
  Future<void> setMarginSize(double size);
  double get lineHeight;
  Future<void> setLineHeight(double height);
  
  // 爬虫设置
  int get scraperMaxWorkers;
  Future<void> setScraperMaxWorkers(int value);
  int get scraperMinDelay;
  Future<void> setScraperMinDelay(int value);
  int get scraperMaxDelay;
  Future<void> setScraperMaxDelay(int value);
  
  // 导入导出设置
  String get defaultExportPath;
  Future<void> setDefaultExportPath(String path);
  bool get deleteAfterImport;
  Future<void> setDeleteAfterImport(bool value);
}
```

### 5.3 ImportService

```dart
abstract class ImportService {
  Future<ImportResult> importTxtFile(String filePath, {String? author, List<String>? tags, ...});
  Future<ImportResult> importEpubFile(String filePath, {String? author, List<String>? tags, ...});
  Future<BatchImportResult> importFolder(String folderPath, {bool recursive = false, ...});
  
  // 进度回调
  void setProgressCallback(void Function(int current, int total, String message)? callback);
}
```

## 6. 测试策略

### 6.1 单元测试
- DatabaseService: 各 CRUD 方法、边界条件、事务回滚
- SettingsService: 读写偏好、类型转换、默认值
- ImportService: TXT解析（编码检测、章节识别）、EPUB解析
- Models: JSON 序列化/反序列化往返

### 6.2 Widget 测试
- BookGridView: 渲染数量、点击回调
- BookListView: 渲染、滚动、筛选
- ResponsiveLayout: 不同宽度断点切换
- SearchBar: 输入防抖、过滤

### 6.3 集成测试
- 启动应用 → 验证空状态
- 导入书籍 → 验证书库显示
- 点击书籍 → 验证阅读器加载
- 模拟翻页 → 验证进度保存
- 冷启动 → 验证进度恢复

### 6.4 Mock 策略

```dart
// 使用 mockito 生成 Mock
@GenerateNiceMocks([MockSpec<DatabaseService>()])
import 'database_service_test.mocks.dart';

// 测试中使用 MemoryFileSystem 替代真实文件系统
// sqflite 提供 sqflite_common_ffi 用于桌面测试
```