# 小说管理系统 Flutter 版 - 需求审计与功能完整性文档

## 文档信息

| 项目 | 内容 |
|------|------|
| **文档版本** | 1.1（状态校准版） |
| **创建时间** | 2026-04-13 |
| **最近校准** | 2026-08-05（对照 commit `ade9486` 后的实际代码逐项核对） |
| **基于代码版本** | novelmgt_flutter 当前主线（master） |
| **参考文档** | PRD_FLUTTER.md, DESIGN_FLUTTER.md |
| **审计范围** | novelmgt (/app, /flet_app) + novelmgt_flutter (/lib) |
| **校准说明** | 1.0 版基于 2026-04-13 代码快照，此后大量 P0/P1/P2/P3 已修复但文档未跟进。本次 1.1 版重新逐条比对 `lib/` 源码，修正过时状态，并把真正剩余的缺口（缓存清理、章节搜索 UI、作者管理）单独列出。 |

---

## 1. 审计概述

### 1.1 审计目的

对 novelmgt（Python/Flet 版，已废弃）和 novelmgt_flutter（Flutter 版，现行开发版）进行全面功能审计，识别：

1. **已实现功能**（✅）：代码完备、逻辑正确、UI 可用
2. **部分实现功能**（⚠️）：代码存在但有缺陷/不完整/逻辑问题
3. **未实现功能**（❌）：PRD 中定义但尚无代码

### 1.2 审计基准

- **需求来源**：`docs/PRD_FLUTTER.md` 中的功能定义
- **实现来源**：`lib/` 目录下所有 Dart 源码
- **对比方法**：逐条 PRD 功能 vs 代码实际实现
- **测试数据**：`D:\OneDrive\bioinfo\Novel_scraber\H` 目录下 145 个 TXT 文件

### 1.3 严重性定义

| 等级 | 说明 |
|------|------|
| 🔴 **P0 - 阻断** | 功能完全不可用或数据丢失风险 |
| 🟠 **P1 - 严重** | 核心功能异常，影响正常使用 |
| 🟡 **P2 - 一般** | 功能有缺陷但可绕过 |
| 🟢 **P3 - 轻微** | 体验问题或非关键缺失 |

---

## 2. 功能完整性审计表

### 2.1 小说管理（CRUD）

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.1.1 | 添加小说（手动） | 手动输入标题、作者、简介、状态、标签 | ✅ | — | `database_service.dart` createBook + home_screen 浮动按钮添加 |
| 2.1.2 | 编辑小说 | 修改基本信息、标签、评分(1-5星)、备注 | ✅ | — | book_detail_screen edit dialog |
| 2.1.3 | 删除小说 | 确认对话框、级联删除章节/标签关联/进度/书签/笔记 | ✅ | — | DB 有 ON DELETE CASCADE |
| 2.1.4 | 搜索小说 | 标题/简介模糊搜索 | ✅ | — | home_screen 搜索框 + library_provider searchBooks |
| 2.1.5 | 章节全文搜索 | 搜索章节内容 | ✅ | — | **✅ 已实现**：后端 `database_service.dart` 的 `searchChapters` 支持 `title LIKE / content LIKE` + 上下文提取；前端 `reader_screen.dart` 顶栏有章节搜索按钮（`_showChapterSearch` 弹窗）。仅 `book_detail_screen` 暂无入口（阅读器内可搜索，非阻断） |
| 2.1.6 | 按标签筛选 | 标签下拉框筛选 | ✅ | — | home_screen FilterBottomSheet 有 tag filter |
| 2.1.7 | 按状态筛选 | 连载中/已完结 | ✅ | — | FilterBottomSheet status filter |
| 2.1.8 | 按评分筛选 | 1-5 星筛选 | ✅ | — | FilterBottomSheet rating filter |
| 2.1.9 | 排序 | 标题/章节数/字数/评分/导入时间 | ✅ | — | home_screen sort menu |
| 2.1.10 | 标签管理 CRUD | 添加、编辑、删除标签 | ✅ | — | **✅ 已实现**：独立 `tags_screen.dart`（371 行），支持创建/删除标签 |
| 2.1.11 | 标签颜色自定义 | 标签颜色 | ✅ | — | **✅ 已实现**：tags 表已加 `color` 字段（默认 `#1976D2`），tags_screen 有颜色选择器 |
| 2.1.12 | 查看标签下小说数量 | 标签关联小说计数 | ✅ | — | **✅ 已实现**：`getBookCountByTag` + tags_screen 的 `TagWithCount` 显示 |
| 2.1.13 | 作者管理 | 作者 CRUD | ⚠️ | 🟡 P2 | 仍无独立作者管理，只能在 book edit / 导入时设置 author 字段 |

### 2.2 导入功能

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.2.1 | TXT 单文件导入 | 导入单个 TXT 文件 | ✅ | — | import_screen 单文件选择 |
| 2.2.2 | TXT 批量文件夹导入 | 递归导入文件夹 | ✅ | — | import_screen 文件夹选择 + import_service importFolder |
| 2.2.3 | 自动编码检测 | UTF-8→GBK→GB2312→Big5 级联 | ✅ | — | import_service _detectEncoding |
| 2.2.4 | 智能章节识别 | 中文数字/阿拉伯数字/英文 Chapter | ✅ | — | chapter_parser.dart 全面正则 |
| 2.2.5 | 章节去重与重排序 | 去重+按序号排序 | ✅ | — | chapter_parser _deduplicateAndSortChapters |
| 2.2.6 | EPUB 导入 | 解析元数据+提取章节 | ✅ | — | import_service _importEpubFile |
| 2.2.7 | 导入进度可视化 | 进度条+百分比 | ✅ | — | import_screen 进度条 + import_provider |
| 2.2.8 | 导入后删除原文件 | 可选删除 | ✅ | — | **✅ 已实现**：settings_screen 有 SwitchListTile，import_service 已实现 deleteAfterImport |
| 2.2.9 | 重复导入检测 | 检测已存在书籍 | ✅ | — | **✅ 已实现**：`findBookByTitleAndAuthor` + `_updateExistingBook`，TXT/EPUB/PDF/MOBI 四条导入路径全部覆盖，重复导入显示"无变化" |
| 2.2.10 | 导入失败回滚 | 事务回滚 | ✅ | — | **✅ 已实现**：`import_service.dart` 抽取 `_createBookWithChapters`，用 `_db.db.transaction((txn) => ...)` 包裹"建书 + 逐章写入"。TXT/EPUB/PDF/MOBI 四条新书导入路径全部覆盖，任一章写入失败自动回滚，不再残留"半本书" |

### 2.3 爬取功能

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.3.1 | 爬虫框架 | Phase 2 预留 | ❌ | — | PRD 标注 Phase 2，当前未实现 |
| 2.3.2 | 爬取页面 | scraper_screen | ❌ | — | DESIGN 中描述但未实现 |
| 2.3.3 | NAS API Client | Phase 2 预留 | ❌ | — | PRD 标注 Phase 2 |

### 2.4 章节管理

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.4.1 | 章节列表 | 三列网格布局 | ✅ | — | book_detail_screen ChapterGrid |
| 2.4.2 | 章节编辑 | 修改标题、内容 | ✅ | — | **✅ 已实现**：ChapterGrid `onLongPress` 弹出菜单含编辑标题 |
| 2.4.3 | 章节删除 | 带确认删除 | ✅ | — | **✅ 已实现**：ChapterGrid `onLongPress` 弹出菜单含删除 |
| 2.4.4 | 章节重排序 | 自动识别序号重排 | ✅ | — | chapter_parser 排序逻辑 |
| 2.4.5 | 章节内搜索 | 搜索关键词 | ✅ | — | **✅ 已实现**：后端 `searchChapters`；前端 `reader_screen.dart` `_showChapterSearch` 弹窗提供章节内搜索入口（标题+正文匹配 + 上下文） |

### 2.5 阅读功能

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.5.1 | 章节内容显示 | PageView 章节阅读 | ✅ | — | reader_screen PageView |
| 2.5.2 | 字体大小调整 | 12-30，步进1 | ✅ | — | reader_screen 字体滑块 |
| 2.5.3 | 左右边距调整 | 20-200，步进10 | ✅ | — | reader_screen 边距滑块 |
| 2.5.4 | 行间距调整 | 1.0-3.0，步进0.1 | ✅ | — | reader_screen 行高滑块 |
| 2.5.5 | 上一章/下一章 | 章节导航 | ✅ | — | reader_screen 左右滑动手势 + 按钮 |
| 2.5.6 | 快速跳转 | 章节跳转列表 | ✅ | — | reader_screen 底部章节列表弹窗 |
| 2.5.7 | 键盘快捷键 | ← → ↑ ↓ PageUp/Down Home/End | ✅ | — | reader_screen KeyboardListener |
| 2.5.8 | Ctrl+B 书签 | 阅读器内添加书签 | ✅ | — | reader_screen |
| 2.5.9 | Ctrl+N 笔记 | 阅读器内添加笔记 | ✅ | — | reader_screen |
| 2.5.10 | 阅读进度自动记录 | 保存当前章节+位置 | ✅ | — | **✅ 已修复**：ReaderState 增加 currentScrollPosition，ScrollController listener 记录实际滚动位置 |
| 2.5.11 | 深色/浅色/跟随系统 | 主题切换 | ✅ | — | settings_screen 主题选择 |
| 2.5.12 | 恢复阅读位置 | 冷启动恢复到上次位置 | ✅ | — | **✅ 已修复**：章节 ID + scroll_position 均可恢复 |
| 2.5.13 | 阅读器字体/边距持久化 | 跨 session 保留阅读设置 | ✅ | — | **✅ 已修复**：ReaderNotifier 联动 SettingsNotifier/Hive，setFont/setMargin/setLineHeight 同步写回 |
| 2.5.14 | Ctrl+F 全局搜索 | 聚焦搜索框 | ✅ | — | **✅ 已实现**：home_screen CallbackShortcuts Ctrl+F 聚焦搜索框 |
| 2.5.15 | Ctrl+I 打开导入 | 快捷键导入 | ✅ | — | **✅ 已实现**：home_screen CallbackShortcuts Ctrl+I 跳转 /import |
| 2.5.16 | Ctrl+S 打开设置 | 快捷键设置 | ✅ | — | **✅ 已实现**：home_screen CallbackShortcuts Ctrl+S 跳转 /settings |
| 2.5.17 | Esc 返回 | 全局返回 | ✅ | — | **✅ 已实现**：home_screen CallbackShortcuts Esc 清空搜索/返回 |

### 2.6 书签功能

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.6.1 | 添加书签 | 阅读中添加书签 | ✅ | — | reader_screen + DB createBookmark |
| 2.6.2 | 删除书签 | 删除书签 | ✅ | — | book_detail_screen 书签删除 |
| 2.6.3 | 书签列表 | 按时间降序 | ✅ | — | book_detail_screen 书签 Tab |
| 2.6.4 | 点击书签跳转 | 跳转到书签位置 | ✅ | — | 点击书签导航到对应章节 |
| 2.6.5 | 书签备注 | 添加备注 | ✅ | — | DB 支持 note 字段，UI 支持备注输入 |

### 2.7 笔记功能

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.7.1 | 添加笔记 | 章节中添加笔记 | ✅ | — | reader_screen + DB createNote |
| 2.7.2 | 笔记与位置关联 | 章节ID+字符偏移 | ✅ | — | notes 表有 chapter_id + position |
| 2.7.3 | 笔记列表查看 | 按书籍查看笔记 | ✅ | — | book_detail_screen 笔记 Tab |
| 2.7.4 | 笔记编辑 | 编辑已有笔记 | ✅ | — | **✅ 已实现**：reader_screen 笔记列表 `onTap: _showEditNote` 编辑弹窗 |
| 2.7.5 | 笔记删除 | 删除笔记 | ✅ | — | 长按/滑动删除 |

### 2.8 导出功能

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.8.1 | TXT 导出 | 导出为 TXT 文件 | ✅ | — | export_service exportToTxt |
| 2.8.2 | EPUB 导出 | 导出为 EPUB 文件 | ✅ | — | export_service exportToEpub |
| 2.8.3 | 导出路径可选 | 选择保存位置 | ✅ | — | file_picker 选择路径 |
| 2.8.4 | 批量导出 | 多书同时导出 | ✅ | — | **✅ 已实现**：home_screen 选择模式（`toggleSelectionMode`）+ `_showBatchExportDialog` |

### 2.9 统计与可视化

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.9.1 | 总数统计 | 小说数/章节数/字数/作者数 | ✅ | — | stats_screen 顶部卡片 |
| 2.9.2 | 状态分布 | 连载中/已完结 | ✅ | — | stats_screen 饼图 |
| 2.9.3 | 评分分布 | 星级分布 | ✅ | — | stats_screen 评分柱状图 |
| 2.9.4 | 标签 Top 10 | 标签使用排行 | ✅ | — | **✅ 已实现**：stats_screen 展示 `stats.topTags`（带颜色标签） |
| 2.9.5 | 作者 Top 10 | 作者作品数排行 | ✅ | — | **✅ 已实现**：stats_screen 展示 `stats.topAuthors` |
| 2.9.6 | 最近阅读列表 | 最近阅读的书籍 | ✅ | — | **✅ 已实现**：stats_screen 展示 `stats.recentlyRead`（点击跳转详情） |

### 2.10 设置与偏好

| # | 功能 | PRD 定义 | 实现状态 | 严重性 | 备注 |
|---|------|---------|---------|--------|------|
| 2.10.1 | 阅读设置 | 字体/边距/行高/主题 | ✅ | — | **✅ 已修复**：阅读器读取 SettingsNotifier，全局设置生效 |
| 2.10.2 | 导入设置 | 默认编码 | ❌ | 🟢 P3 | 未实现（当前自动检测 UTF-8→GBK→GB2312→Big5，无手动默认项） |
| 2.10.3 | 导出设置 | 默认路径/格式 | ✅ | — | **✅ 已实现**：settings_screen 默认导出格式（TXT/EPUB/PDF）+ 导出路径配置 |
| 2.10.4 | 导入后删除原文件 | 可选删除 | ✅ | — | **✅ 已实现**：settings_screen SwitchListTile + import_service.deleteAfterImport |
| 2.10.5 | 数据库备份 | 备份数据库 | ✅ | — | settings_screen + backup_service |
| 2.10.6 | 数据库恢复 | 恢复数据库 | ✅ | — | settings_screen + backup_service |
| 2.10.7 | 自动备份清理 | 保留最近 N 份 | ✅ | — | backup_service autoCleanup |
| 2.10.8 | 缓存清理 | 清理缓存 | ✅ | — | **✅ 已实现**：`cache_service.dart` + `cache_provider.dart` + settings_screen"清理缓存"ListTile（确认对话框 + 释放空间/文件数反馈） |

---

## 3. 逻辑缺陷与 Bug 清单

### 3.1 P0 - 阻断级问题

| # | 严重性 | 问题描述 | 影响范围 | 修复建议 |
|---|--------|---------|---------|---------|
| BUG-001 | 🔴 P0 | ~~重复导入无检测~~ **✅ 已修复**：`findBookByTitleAndAuthor` 已实现，TXT/EPUB/PDF/MOBI 四条导入路径均先查询，命中则调用 `_updateExistingBook` / `_updateExistingBookFromParsed` 检测章节变化并跳过/更新，不再创建重复记录（重复导入显示"无变化"）。已由 `import_service_test.dart` 的 'skips duplicate imports' / 'prevents duplicates' 用例覆盖。 | 导入流程 | — |

### 3.2 P1 - 严重级问题

| # | 严重性 | 问题描述 | 影响范围 | 修复建议 |
|---|--------|---------|---------|---------|
| BUG-002 | 🟠 P1 | ~~阅读器设置不持久化~~ **✅ 已修复**：`ReaderNotifier` 构造时从 `_settingsNotifier.state.settings` 读取字体/边距/行高；`setFontSize/setMarginSize/setLineHeight` 同步写回 `SettingsNotifier`（Hive 持久化）。跨 session 设置保留。 | 阅读体验 | — |
| BUG-003 | 🟠 P1 | ~~章节全文搜索未实现~~ **✅ 已修复**：`searchChapters` 已实现 `title LIKE ? OR content LIKE ?` + 匹配上下文提取。已由 `database_service_test.dart` 的 'searchChapters finds content' 用例覆盖。**✅ UI 已补**：`reader_screen.dart` 顶栏有章节搜索按钮，调用 `_showChapterSearch`（StatefulBuilder 弹窗 + 结果列表 + 上下文展示）。仅 `book_detail_screen` 仍无入口（P3 体验项）。 | 搜索功能 | — |

### 3.3 P2 - 一般级问题

| # | 严重性 | 问题描述 | 影响范围 | 修复建议 |
|---|--------|---------|---------|---------|
| BUG-004 | 🟡 P2 | **阅读进度 scroll_position 始终为 0**：`reader_provider.dart` 保存进度时 `scroll_position` 参数始终传 0，DB 字段存在但从未被写入有效值。恢复阅读时只能恢复到章节开头，无法恢复到精确位置。 | 阅读恢复 | ~~在 ScrollController 变化时记录 position，保存时传入实际值~~ **✅ 已修复：ReaderState 增加 currentScrollPosition，reader_screen 添加 ScrollController listener** |
| BUG-005 | 🟡 P2 | **book_detail_screen 的数据库访问 hack**：第 480 行使用 `_getDb() => ProviderScope.containerOf(context).read(databaseProvider)` 来绕过正常的 Provider 访问模式。这种做法在 Widget 生命周期外可能抛异常，且破坏了 Riverpod 的状态管理原则。 | 详情页稳定性 | **✅ 已修复：当前代码已统一使用 `ref.read(databaseServiceProvider)`** |
| BUG-006 | 🟡 P2 | **类型安全丧失**：`book_detail_screen.dart` 第 200 行 `chapters[index] as dynamic` 访问 Chapter 属性，完全绕过了 Dart 的类型系统。如果 Chapter 模型字段变更，编译器无法捕获错误。 | 详情页类型安全 | **✅ 已修复：当前代码使用 `List<Chapter>` 正确类型，无 dynamic 转换** |
| BUG-007 | 🟡 P2 | **章节编辑/删除 UI 缺失**：数据库层有完整的 `updateChapter`、`deleteChapter` 方法，但 book_detail_screen 的章节网格只提供"点击进入阅读"功能，没有编辑/删除入口。 | 章节管理 | **✅ 已修复：ChapterGrid 使用 `onLongPress` 弹出菜单，含编辑标题/删除/阅读** |
| BUG-008 | 🟡 P2 | **笔记编辑 UI 缺失**：DB 有 `updateNote` 方法，UI 只能新增和删除笔记，无法编辑已有笔记内容。 | 笔记管理 | **✅ 已修复：reader_screen 笔记列表有 `onTap: _showEditNote` 编辑弹窗** |
| BUG-009 | 🟡 P2 | **导入后删除原文件功能缺失**：PRD 要求"导入后删除原文件（可选）"，但 ImportScreen 和 SettingsScreen 都没有此开关。 | 导入设置 | **✅ 已修复：settings_screen 已有 SwitchListTile，import_service 已实现 deleteAfterImport** |
| BUG-010 | 🟡 P2 | **性能隐患**：`reader_provider.dart` 中 `getChapters(perPage: 100000)` 一次性加载所有章节到内存。对于超大部头小说（数千章），可能导致内存压力。 | 阅读器性能 | **✅ 已修复：新增 `getChapterList` 只加载元数据，`getChapterContent` 按需加载单章内容** |
| BUG-010b | 🟡 P2 | ~~Widget 导入路径错误~~ **✅ 已修复**：widgets 下文件已统一使用一级路径 `../models/book.dart` 等。 | 构建失败 | — |
| BUG-010c | 🟡 P2 | ~~BookGridView 点击无导航~~ **✅ 已修复**：`_onBookTap` 已实现 `context.go('/book/${book.id}')`（选择模式下改为勾选）。 | 核心导航 | — |
| BUG-010d | 🟡 P2 | ~~ReaderProvider firstOrNull 无导入~~ **✅ 已修复**：已移除 `firstOrNull` 用法（grep 全 lib 无残留）。 | 编译失败 | — |

### 3.3b P1 - 编译阻断问题

| # | 严重性 | 问题描述 | 影响范围 | 修复建议 |
|---|--------|---------|---------|---------|
| BUG-P1-01 | 🟠 P1 | **app_theme.dart WidgetStateProperty 类型错误**：`headingRowColor` 使用 `WidgetStateProperty.all(...)`，Flutter 正确 API 是 `MaterialStateProperty`。这将导致编译失败。 | 全局主题 | ~~替换 WidgetStateProperty 为 MaterialStateProperty~~ **经核实，SDK>=3.2.0 使用 WidgetStateProperty 是正确的（Flutter 3.22+ 新名称），无需修改** |
| BUG-P1-02 | 🟠 P1 | **dart:io 平台兼容性（Web 构建）**：lib 下曾有 10 个文件无条件 `import 'dart:io'`（services×7 + platform_utils + import_screen + book_detail_screen），Web 构建必然编译失败；设置页在 Web 上还会因 path_provider 崩溃。 | Web 构建 | **✅ 已修复（2026-08-18）**：dart:io 全部收敛到条件导入文件（`utils/database_factory_init_io.dart`、`utils/web_launcher_io.dart`、`services/platform_fs_io.dart`），共享代码经 `platform_fs.dart` / `web_launcher.dart` 条件导入访问；`platform_utils.dart` 改用 `defaultTargetPlatform`；Web 端导入/导出/设置页适配见「附录 C：Web 版支持」 |

### 3.4 P3 - 轻微级问题

| # | 严重性 | 问题描述 | 影响范围 | 修复建议 |
|---|--------|---------|---------|---------|
| BUG-011 | 🟢 P3 | ~~全局快捷键缺失~~ **✅ 已修复**：home_screen 用 CallbackShortcuts 注册 Ctrl+F（聚焦搜索）/Ctrl+I（导入）/Ctrl+S（设置）/Esc（清空搜索/返回）。 | 操作效率 | — |
| BUG-012 | 🟢 P3 | ~~标签颜色不可自定义~~ **✅ 已修复**：tags 表已加 `color TEXT DEFAULT '#1976D2'`，tags_screen 有 8 色选择器 + `Formatters.colorToHex`。 | 标签管理 | — |
| BUG-013 | 🟢 P3 | ~~统计页面数据不完整~~ **✅ 已修复**：stats_screen 展示总数/状态分布/评分分布/**标签TOP/作者TOP/最近阅读**六项。 | 统计展示 | — |
| BUG-014 | 🟢 P3 | ~~批量导出 UI 缺失~~ **✅ 已修复**：home_screen AppBar 选择模式 + `_showBatchExportDialog` 批量导出选中书籍。 | 导出效率 | — |
| BUG-015 | 🟢 P3 | ~~缓存清理缺失~~ **✅ 已修复**：新增 `lib/services/cache_service.dart` + `lib/providers/cache_provider.dart`（计算缓存大小、扫描删除临时/缩略图缓存）。`settings_screen.dart` 数据管理卡片已增加"清理缓存"ListTile（含确认对话框、结果 SnackBar、`CacheCleanResult` 反馈释放空间/文件数）。 | 设置 | — |
| BUG-016 | 🟢 P3 | ~~章节搜索 UI 缺失~~ **✅ 已修复（reader 端）**：`reader_screen.dart` 顶栏有搜索按钮 → `_showChapterSearch` 弹窗（搜索框 + 结果列表 + 匹配上下文 + 点击跳转章节）。后端 `searchChapters` 已就绪。**⚠️ 剩余**：`book_detail_screen` 仍无章节搜索入口（非阻断，可在阅读器内搜索）。 | 搜索体验 | （可选）在 book_detail_screen 章节区增加搜索入口 |
| BUG-017 | 🟢 P3 | **作者管理页缺失**：无独立作者 CRUD（PRD 2.1.13）。 | 元数据管理 | （可选）新增作者管理页，或复用 tags_screen 模式做 authors_screen |

---

## 4. 数据模型与代码实现对照

### 4.1 数据库 Schema 对照

| 表 | PRD 字段 | 实际实现 | 差异 |
|---|---------|---------|------|
| **books** | id, title, author, summary, status, source_url, cover_image, cover_image_path, rating, notes, word_count, last_read_at, created_at, updated_at | 全部实现 | ✅ 完全一致 |
| **chapters** | id, book_id, chapter_number, original_order, title, content, source_url, created_at | 全部实现 | ✅ 完全一致 |
| **tags** | id, name, color | id, name, color（默认 `#1976D2`） | ✅ 已加 color 字段 |
| **book_tags** | book_id, tag_id | 全部实现 | ✅ 完全一致 |
| **reading_progress** | id, book_id, chapter_id, scroll_position, last_read_at | 全部实现 | ✅ 完全一致（scroll_position 已被 ReaderState 使用） |
| **bookmarks** | id, book_id, chapter_id, position, title, note, created_at | 全部实现 | ✅ 完全一致 |
| **notes** | id, book_id, chapter_id, position, content, created_at, updated_at | 全部实现 | ✅ 完全一致 |

### 4.2 Provider / State 对照

| Provider | PRD 定义的状态 | 实际实现 | 差异 |
|----------|-------------|---------|------|
| **LibraryProvider** | books, searchQuery, filterTags, filterStatus, filterRating, sortBy, sortOrder, page, perPage | 全部实现 | ✅ 完全一致 |
| **ReaderProvider** | currentBook, currentChapter, chapters, fontSize, margin, lineHeight, isDarkMode | 已联动 SettingsProvider，isDarkMode 跟随全局 themeMode | ✅ 已对齐 |
| **ImportProvider** | isImporting, currentFile, totalFiles, progress, result | 全部实现 | ✅ 完全一致 |
| **SettingsProvider** | themeMode, fontSize, margin, lineHeight, exportPath | 已含 deleteAfterImport / defaultExportFormat / customDbPath；scraper 配置 Phase 2 预留 | ⚠️ 部分实现（scraper 待 Phase 2） |
| **StatsProvider** | stats | 全部实现 | ✅ |

### 4.3 目录结构对照

| PRD 设计路径 | 实际存在 | 差异 |
|-------------|---------|------|
| `lib/router/app_router.dart` | ✅ 存在 | — |
| `lib/models/book.dart` 等模型文件 | ✅ 存在+`.g.dart` | — |
| `lib/services/database_service.dart` | ✅ 存在 (779 行) | — |
| `lib/services/settings_service.dart` | ✅ 存在 | — |
| `lib/services/import_service.dart` | ✅ 存在 (286 行) | — |
| `lib/services/export_service.dart` | ✅ 存在 (176 行) | — |
| `lib/services/chapter_parser.dart` | ✅ 存在 (233 行) | — |
| `lib/services/nas_api_client.dart` | ❌ 未创建 | Phase 2 预留 |
| `lib/services/scraper_service.dart` | ❌ 未创建 | Phase 2 预留 |
| `lib/screens/scraper_screen.dart` | ❌ 未创建 | Phase 2 预留 |
| `lib/screens/tags_screen.dart` | ✅ 已创建（371 行） | 标签管理 CRUD + 颜色 + 计数 |
| `lib/widgets/` 独立组件 | ✅ 已拆分 | book_card / book_grid_view / book_list_view / responsive_layout |
| `lib/theme/app_theme.dart` | ✅ 独立文件 | 与 app_colors.dart 同目录 |
| `lib/utils/formatters.dart` | ✅ 已创建 | 含 formatWordCount / colorToHex 等 |
| `lib/utils/platform_utils.dart` | ✅ 已创建 | — |
| `test/` 测试文件 | ✅ 已创建 | unit×6 + integration×1 + widget，覆盖 DB/导入/章节解析/格式化/模型 |

---

## 5. H 文件夹批量导入需求规范

### 5.1 测试数据

| 项目 | 内容 |
|------|------|
| **路径** | `D:\OneDrive\bioinfo\Novel_scraber\H` |
| **文件数** | 145 个 TXT 文件 (+ 2 个 .crdownload 临时文件) |
| **编码** | 主要为 GBK/GB2312，部分 UTF-8 |
| **文件名** | 小说标题作为文件名，如 `诡秘之主.txt`、`斗破苍穹.txt` 等 |
| **大小** | 从数十 KB 到数 MB 不等 |
| **章节格式** | 均为中文网络小说格式，含第X章/第X节等标志 |

### 5.2 批量导入功能需求

#### 5.2.1 核心流程

```
用户点击"导入" → 选择"文件夹导入" → 选择 H 文件夹
    → 扫描文件夹内所有 .txt 文件（递归可选）
    → 过滤掉非 .txt 文件（如 .crdownload 临时文件）
    → 对每个文件:
        1. 检测文件编码（UTF-8 → GBK → GB2312 → Big5）
        2. 读取文件内容
        3. 解析章节（正则匹配中文/阿拉伯数字/英文章节标题）
        4. 检查是否已存在（按 title+author 去重）
        5. 创建 Book 记录
        6. 创建 Chapter 记录（批量插入）
        7. 计算总字数并回写
    → 显示导入结果：成功 N 本，跳过 N 本（已存在），失败 N 本
    → 用户确认完成
```

#### 5.2.2 性能要求

| 指标 | 目标值 |
|------|--------|
| 145 文件批量导入总时间 | < 30 秒 |
| 单文件导入（含 500 章） | < 500ms |
| 导入过程 UI 不卡顿 | 必须（异步+进度回调） |
| 内存峰值 | < 300MB |

#### 5.2.3 重复导入处理策略

| 策略 | 说明 | 优先级 |
|------|------|--------|
| **跳过**（默认） | 检测到 title+author 完全匹配时跳过，不创建重复记录 | P0 必须 |
| **覆盖** | 删除旧书记录（级联删除章节/进度/书签/笔记），重新导入 | P2 可选 |
| **保留两份** | 允许重复，但添加 `(2)` 后缀 | 不推荐 |

#### 5.2.4 文件过滤规则

| 规则 | 说明 |
|------|------|
| `.txt` 扩展名 | 只导入 .txt 文件 |
| `.crdownload` 排除 | 排除 Chrome 下载临时文件 |
| 空文件排除 | 跳过大小为 0 的文件 |
| 编码失败跳过 | 编码检测失败时记入错误列表，不阻塞其他文件 |

#### 5.2.5 导入结果报告

批量导入完成后显示摘要：

```
导入完成！
- 成功：132 本
- 跳过（已存在）：10 本
- 失败：3 本
  - [文件名]: [错误原因]

查看失败详情 → [展开]
```

---

## 6. novelmgt（Python/Flet 版）审计摘要

> 以下为 Python/Flet 版的审计结论，该版本已被判定为"垃圾"，仅供参考对比。

### 6.1 关键问题

| 问题 | 说明 |
|------|------|
| **架构混乱** | Flask Web 路由 + Flet GUI 混用，两套 UI 系统竞争 |
| **多个 main.py** | flet_app/ 下有 clean_main.py、compatible_main.py、final_compatible.py 等多个变体，无法确定哪个是正式入口 |
| **路由不完整** | routes/ 下有 novels.py、reading.py 等但很多路由返回 404 或未实现 |
| **Flet UI 不可用** | 多个 Flet 控件绑定到错误的数据源或缺少事件处理 |
| **数据库模型不匹配** | models/__init__.py 中的模型与 database.py 的表结构有差异 |

### 6.2 结论

novelmgt（Python/Flet 版）**不建议继续维护**。所有后续开发集中在 novelmgt_flutter 版。

---

## 7. 修复优先级路线图

### Phase 1 — 必须修复（P0 + P1，编译阻断优先）— ✅ 全部已完成

| 优先级 | 问题 | 状态 |
|--------|------|------|
| 🟠 P1 | ~~BUG-P1-01: app_theme WidgetStateProperty~~ 已核实：Flutter 3.22+ 中 WidgetStateProperty 是正确 API，无需修改 | ✅ |
| 🟠 P1 | ~~BUG-P1-02: main.dart dart:io Web 兼容性~~ 降级为 P3：桌面端为主，Web 辅助 | ✅ |
| 🟡 P2 | ~~BUG-010b: Widget 导入路径~~ | ✅ |
| 🟡 P2 | ~~BUG-010c: BookGridView 点击导航~~ | ✅ |
| 🟡 P2 | ~~BUG-010d: ReaderProvider firstOrNull~~ | ✅ |
| 🔴 P0 | ~~BUG-001: 重复导入检测~~ `findBookByTitleAndAuthor` + 四格式覆盖 | ✅ |
| 🟠 P1 | ~~BUG-002: 阅读器设置持久化~~ ReaderNotifier ↔ SettingsNotifier/Hive | ✅ |
| 🟠 P1 | ~~BUG-003: 章节全文搜索（后端）~~ `searchChapters` LIKE 搜索 | ✅（⚠️ UI 入口仍缺，转 P3） |

### Phase 2 — 应当修复（P2）— ✅ 全部已完成

| 优先级 | 问题 | 预计工时 | 状态 |
|--------|------|---------|------|
| 🟡 P2 | BUG-004: scroll_position 保存 | 1h | ✅ 已修复 |
| 🟡 P2 | BUG-005: book_detail DB 访问 hack | 2h | ✅ 代码已修正 |
| 🟡 P2 | BUG-006: chapters as dynamic 类型安全 | 1h | ✅ 代码已修正 |
| 🟡 P2 | BUG-007: 章节编辑/删除 UI | 3h | ✅ 已实现 |
| 🟡 P2 | BUG-008: 笔记编辑 UI | 1h | ✅ 已实现 |
| 🟡 P2 | BUG-009: 导入后删除原文件设置 | 1h | ✅ 已实现 |
| 🟡 P2 | BUG-010: 章节分页加载 | 3h | ✅ 已修复（getChapterList + getChapterContent） |

### Phase 3 — 建议完善（P3）

| 优先级 | 问题 | 状态 |
|--------|------|------|
| 🟢 P3 | ~~BUG-011: 全局快捷键~~ home_screen Ctrl+F/I/S/Esc 已实现 | ✅ |
| 🟢 P3 | ~~BUG-012: 标签颜色自定义~~ tags 表加 color 字段 + 颜色选择器 | ✅ |
| 🟢 P3 | ~~BUG-013: 统计页面完善~~ topTags/topAuthors/recentlyRead 已展示 | ✅ |
| 🟢 P3 | ~~BUG-014: 批量导出 UI~~ 选择模式 + 批量导出对话框 | ✅ |
| 🟢 P3 | **BUG-015（新）: 缓存清理** settings_screen 无缓存清理入口 | ❌ |
| 🟢 P3 | **BUG-016（新）: 章节搜索 UI** `searchChapters` 后端就绪但无 screen 入口 | ❌ |
| 🟢 P3 | **BUG-017（新）: 作者管理页** 仍无独立作者 CRUD | ❌ |

### Phase 4 — 剩余缺口（2026-08-05 校准后确认未做）

> 经逐行核对 `lib/` 源码，P0/P1/P2/P3 的历史 bug 均已修复。下列为本校准过程中**新识别**或**沿用**的真正未完成项，按建议优先级排序。

| 优先级 | 编号 | 缺口 | 实施位置 | 建议 |
|--------|------|------|---------|------|
| 🟢 P3 | BUG-016 | **章节搜索 UI**（`searchChapters` 后端就绪，无入口） | `reader_screen.dart` / `book_detail_screen.dart` | reader 顶栏加搜索图标 → 弹层输入关键词 → 调 `db.searchChapters(bookId, q)` → 展示「章节号 · 标题 · ...上下文...」列表 → 点击跳转对应章节 |
| 🟢 P3 | BUG-015 | **缓存清理** | `settings_screen.dart` 数据管理卡片 | 新增「清理缓存」ListTile：扫描 `getTemporaryDirectory()` / `getApplicationSupportDirectory()` 下缩略图与临时文件，计算大小、确认后删除；`backup_service` 可扩展或新建 `cache_service.dart` |
| 🟢 P3 | BUG-017 | **作者管理页**（可选） | 新增 `screens/authors_screen.dart` | 复用 `tags_screen.dart` 模式：列作者 + 作品数，点击筛选该作者书籍。或仅在 home 筛选器增强即可，不强制独立页 |
| 🟢 P3 | — | **lint 收尾**（106 info，0 error/warning） | 全局 | 可选：批量加 `const`、调整构造函数顺序、删 `unnecessary_import`。纯风格，不影响功能 |
| ⚪ Phase 2 | — | **爬虫模块**（PRD Phase 2 预留） | 新增 `scraper_service.dart` / `scraper_screen.dart` / `nas_api_client.dart` | 可对接项目根 `scrapers/zzxx_crawler.py`（成熟），或用 Dart(dio) 直连 zzxx.org 新版 URL `https://www.zzxx.org/files/article/{vol}/{id}/`，在 App 内浏览/下载新书 |

---

---

## 8. 测试需求

### 8.1 必须通过的测试用例

> 自动化状态对照：`test/` 下 unit×6 + integration×1 + widget。下列 T-003/T-007 等核心路径已有自动化用例覆盖。

| # | 测试场景 | 前置条件 | 操作步骤 | 预期结果 | 自动化覆盖 |
|---|---------|---------|---------|---------|-----------|
| T-001 | 单文件 TXT 导入 | H 文件夹存在 | 导入 `诡秘之主.txt` | 创建书籍+解析章节+显示在书库 | ✅ `import_service_test.dart` 'imports a simple TXT file' |
| T-002 | 批量文件夹导入 | H 文件夹有 145 个文件 | 选择 H 文件夹导入 | 显示进度+完成摘要+所有非空 .txt 导入成功 | ✅ 'imports multiple TXT files' + `h_folder_import_test.dart` |
| T-003 | 重复导入检测 | 已导入 `诡秘之主.txt` | 再次导入同文件 | 提示已存在并跳过，不创建重复记录 | ✅ 'skips duplicate imports' / 'prevents duplicates' |
| T-004 | GBK 编码检测 | H 文件夹有 GBK 编码文件 | 导入 GBK 文件 | 正确识别编码，内容无乱码 | ✅ 'imports TXT with GBK encoding' |
| T-005 | 阅读器设置持久化 | 设置字体20、边距100 | 退出并重新进入阅读器 | 字体20、边距100 保持不变 | ❌（需 widget/集成测试） |
| T-006 | 阅读进度恢复 | 阅读至第50章中间 | 退出应用，重新打开该书 | 恢复到第50章（滚动位置也应恢复） | ⚠️ `updateProgress` 有单测，端到端未覆盖 |
| T-007 | 章节全文搜索 | 书库有多本书 | 搜索"灵根" | 返回包含"灵根"的章节列表 | ✅ 'searchChapters finds content'（⚠️ UI 入口缺，见 BUG-016） |
| T-008 | 书签 CRUD | 阅读中 | 添加→查看→删除书签 | 书签正确增删查 | ✅ 'creates and deletes bookmarks' |
| T-009 | 笔记编辑 | 已有笔记 | 编辑笔记内容 | 笔记内容更新 | ✅ 'creates and updates notes' |
| T-010 | 数据库备份恢复 | 书库有数据 | 备份→清空→恢复 | 数据完整恢复 | ❌（backup_service 无单测） |

---

## 附录 A：文件结构与实现对照

```
novelmgt_flutter/lib/
├── main.dart                          ✅ 入口（✅ Web 兼容：经条件导入初始化数据库工厂）
├── app.dart                           ✅ MaterialApp 配置
├── models/                            ✅ 全部模型+生成代码
│   ├── book.dart                      ✅ (含 .g.dart, 含 Tag 类)
│   ├── chapter.dart                   ✅ (含 .g.dart)
│   ├── bookmark.dart                  ✅ (含 .g.dart)
│   ├── note.dart                      ✅ (含 .g.dart)
│   ├── reading_progress.dart          ✅ (含 .g.dart)
│   ├── import_result.dart             ✅ (含 .g.dart, 含 BatchImportResult/LibraryStats)
│   ├── app_settings.dart              ✅ (含 .g.dart)
│   └── models.dart                    ✅ barrel export
├── services/
│   ├── database_service.dart          ✅ (779行, 核心, 含级联删除)
│   ├── import_service.dart            ✅ (286行)
│   ├── chapter_parser.dart            ✅ (233行)
│   ├── export_service.dart            ✅ (176行)
│   ├── backup_service.dart            ✅ (167行)
│   └── settings_service.dart          ✅ (Hive)
├── providers/
│   ├── library_provider.dart          ✅ (159行)
│   ├── reader_provider.dart          ✅ (已联动 SettingsProvider，无 firstOrNull)
│   ├── import_provider.dart           ✅ (123行)
│   ├── settings_provider.dart         ✅
│   ├── backup_provider.dart           ✅
│   ├── database_provider.dart         ✅
│   └── stats_provider.dart            ✅
├── screens/
│   ├── home_screen.dart               ✅ (206行)
│   ├── import_screen.dart             ✅ (380行)
│   ├── book_detail_screen.dart        ✅ (已用 ref.read(databaseServiceProvider)，无 dynamic)
│   ├── reader_screen.dart             ✅ (482行)
│   ├── settings_screen.dart           ✅ (284行)
│   ├── stats_screen.dart              ✅ (展示总数/状态/评分/标签TOP/作者TOP/最近阅读)
│   └── tags_screen.dart               ✅ (371行, 标签CRUD+颜色+计数)
├── widgets/
│   ├── book_card.dart                 ✅ (路径已修正为 ../)
│   ├── book_grid_view.dart            ✅ (路径修正 + onTap 跳转 /book/{id})
│   ├── book_list_view.dart            ✅ (路径已修正为 ../)
│   └── responsive_layout.dart         ✅
├── theme/
│   ├── app_theme.dart                 ✅ (WidgetStateProperty 在 Flutter 3.22+ 正确)
│   └── app_colors.dart                ✅
├── utils/
│   ├── constants.dart                  ✅
│   ├── formatters.dart                 ✅
│   └── platform_utils.dart             ✅
├── router/
│   └── app_router.dart                ✅
└── (缺失: nas_api_client.dart, scraper_service.dart, scraper_screen.dart - Phase 2)
```

## 附录 B：novelmgt（Python/Flet 版）废弃清单

以下组件已确认废弃，不再维护：

| 废弃组件 | 路径 | 说明 |
|---------|------|------|
| Flask Web 路由 | novelmgt/app/routes/ | 不再使用 |
| Flet GUI | novelmgt/flet_app/ | 多个变体，全部废弃 |
| SQLAlchemy 模型 | novelmgt/app/models/ | 被 Flutter 版 sqflite 模型替代 |
| Python 服务层 | novelmgt/app/services/ | 被 Flutter 版 services/ 替代 |
| HTML 模板 | novelmgt/app/templates/ | 不再使用 |

---

## 附录 C：Web 版支持（2026-08-18）

### C.1 架构

Web 版与桌面版共用同一份代码，通过**条件导入**隔离平台差异：

| 条件导入入口 | io 实现 | web 实现 | 用途 |
|---|---|---|---|
| `services/platform_fs.dart` | `platform_fs_io.dart`（dart:io + path_provider） | `platform_fs_web.dart`（全部抛 UnsupportedError） | 本地文件读写/目录遍历/du 占位检测/缓存清理 |
| `utils/web_launcher.dart` | `web_launcher_io.dart`（Process.run cmd/open/xdg-open） | `web_launcher_web.dart`（dart:html window.open / Blob 下载） | 打开 URL、浏览器下载 |
| `utils/database_factory_init.dart` | `database_factory_init_io.dart`（sqflite_ffi） | `database_factory_init_web.dart`（sqflite_common_ffi_web，NoWebWorker） | 数据库工厂 |

数据库：Web 端用 SQLite WASM（`web/sqlite3.wasm`，运行时由 sqflite_common_ffi_web 相对页面根路径拉取）+ IndexedDB 持久化。选用 `databaseFactoryFfiWebNoWebWorker`（主线程，非 SharedWorker）以兼容受限 WebView 环境。

### C.2 功能矩阵

| 功能 | 桌面 | Web | 说明 |
|---|---|---|---|
| 书架/阅读/进度/书签/笔记/统计/标签/作者 | ✅ | ✅ | 纯 DB，直接可用 |
| 手动添加书籍 | ✅ | ✅ | |
| 文件导入（TXT/EPUB/PDF/MOBI/AZW3） | ✅ 路径导入 | ✅ 字节导入 | Web 走 `file_picker withData:true` + `ImportService.importByBytes` |
| 文件夹批量导入 / 书库扫描 | ✅ | ❌ 隐藏入口 | Web 无本地文件系统 |
| 导出（TXT/EPUB/PDF/Kindle） | ✅ 选目录写文件 | ✅ 浏览器逐本下载 | Web 走 `ExportService.exportDownload`（Blob + a[download]） |
| 备份/恢复/缓存清理/自定义 DB 路径 | ✅ | ❌ 隐藏入口 | Web 数据在 IndexedDB，设置页有说明文案 |
| 打开书源 URL | ✅ 系统浏览器 | ✅ 新标签页 | `WebLauncher.openUrl` |
| 书源爬虫 | ✅ | ⚠️ 受 CORS 限制 | 多数小说站不允许浏览器跨域，失败时按普通错误提示 |

### C.3 已知限制

1. ~~**编码**：`charset_converter` 无 Web 实现，Web 导入 GBK/GB2312/Big5 的 TXT 会回退 UTF-8 替换~~ **✅ 已解决（2026-08-20）**：`TextDecode` 改用纯 Dart 解码链（charset 包 GBK/GB18030 + dart3_big5 Big5，UTF-8 优先），桌面/Web 行为一致；并新增「导入设置-TXT 默认编码」手动指定（auto/UTF-8/GBK/GB18030/Big5，PRD 2.10.2）。自动探测含假名/私用区误码校验（防 Big5 被误解为 GBK）。
2. **数据隔离**：Web 端数据存浏览器 IndexedDB，与桌面端数据库互不相通；清空浏览器站点数据会丢失，无备份能力（待后续实现基于 SQL dump 的 Web 备份/恢复）。
3. **部署**：需以正确 MIME（`application/wasm`）服务 `sqlite3.wasm`；`web/sqflite_sw.js` 当前未使用（NoWebWorker 模式不需要），保留以备切换 SharedWorker。

### C.5 繁简转换与搜索（2026-08-20）

- **词典**：内置 OpenCC 官方词典（`assets/zh_dict/`，ST 4012 字 + 49174 词组 / TS 4148 字 + 477 词组，约 1.1MB），`lib/utils/zh_converter.dart` 最大正向匹配转换（词组优先、单字兜底、多候选取第一），结果缓存（按 方向+文本 键控，32 条）。
- **阅读器繁简切换**：顶栏 🌐 菜单（原文/简体/繁体）+ 设置页「阅读设置-繁简显示」；设置持久化（`readerZhVariant`），显示层转换不改数据库内容。启动时预加载词典，失败则退化原文并提示。
- **搜索繁简同匹配**：`searchBooks` / `searchChapters` 将查询词展开为 {原文, 简体, 繁体} 变体 OR 查询；词典不可用时回退原始查询。
- 单测：`test/zh_converter_test.dart`（9 例，含词组优先「头发→頭髮」与缓存方向隔离）、`test/text_decode_test.dart`（8 例，UTF-8/GBK/Big5 自动+手动）。

### C.6 依赖与稳定性修复（2026-08-20）

| 变更 | 原因 |
|---|---|
| + `charset ^2.0.1`、`+ dart3_big5 ^0.1.1` | 纯 Dart 多编码解码（桌面/Web 一致），替代平台通道方案 |
| − `charset_converter` | 无 Web 实现，被上面两包取代 |
| `pdfrx` → 本地 vendor（`third_party/pdfrx`，上游 1.3.5 + 空安全补丁 + CMake 本地 pdfium 归档优先补丁，含 `pdfium-win-x64.tgz`） | Dart 3.11（Flutter 3.47，2026-08-11 发布）收紧闭包捕获变量类型提升，上游 1.3.5 与 pdfrx_engine 0.4.4 的 `pdf_file_cache.dart` 在 AOT 与测试编译均报错；2.x 则与 epubx 的 image 3/archive 3 依赖冲突（image 4 需 archive 4，epubx 锁 archive 3）。vendor 补丁仅将闭包内可空 `cache` 提升为非空局部变量，等上游发版后可移除（搜「本地补丁」）；CMake 补丁解决受限网络下 pdfium 二进制下载卡死 |
| **导入事务死锁修复**：`createBook`/`createChapter`/`_ensureTag` 增加 `executor` 参数，`_createBookWithChapters` 事务内传 `txn` | 历史代码在 `db.transaction` 回调里用**外层 db 对象**写库，新版 sqflite 严格化后等锁死锁（导入新书必挂）。此前相关测试一直因加载失败未暴露 |
| 测试 schema 补 `filePath` 列 | 三个测试文件自建表结构落后于模型（模型早含 filePath），INSERT 报「no column named filePath」 |
| 测试环境资产挂起修复 | `database_service_test` 补 `TestWidgetsFlutterBinding.ensureInitialized()`（searchChapters 内 rootBundle 需绑定）；`ZhConverter.ensureLoaded` 加 3s 超时（无绑定环境 rootBundle 永久挂起，搜索回退原词） |
| ✅ 测试结果 | 全量 `flutter test`：**113 通过 + 1 跳过，0 失败**（含此前从未跑通的 `h_folder_import_test` / `import_service_test`，及新增 T-005/T-010/SQL dump/CrawlImporter 测试）；`flutter analyze`：**No issues found（203→0）**；`flutter build windows --debug` ✓（产出 novelmgt_flutter.exe）；`flutter build web --release` ✓（含繁简词典资产） |

### C.7 2026-08-20 第二批功能

| 项 | 说明 |
|---|---|
| **BUG-016 收尾** | 书籍详情页章节目录区新增搜索入口（与阅读器内搜索共用 `searchChapters`，简繁同搜，点击结果跳转对应章节） |
| **SQL dump 备份/恢复（全平台）** | `DatabaseService.exportSqlDump/restoreFromSqlDump`：全表导出为 INSERT 语句文本（单引号安全转义、语句切分器识别字符串内分号），恢复=清空重建 schema+单事务导入（失败回滚）；`BackupService.backupSqlDump/restoreSqlDump` + `BackupProvider.backupSql/restoreSql` + 设置页 Web 分支「备份数据库（下载 SQL）/恢复数据库（上传 SQL）」。SQL 文件可在 Web↔桌面之间互导（跨端迁移格式）。桌面端保留原文件备份 |
| **爬虫框架完善**（REQUIREMENTS 2.3 状态已过时——框架此前已基本实现） | ① 修复 `CrawlImporter` 事务死锁（同 C.6 的 executor 问题，含事务内字数统计外移）② 更新模式**增量抓取**：按章号只抓库中没有的章节 ③ 单章失败重试 1 次、仍失败跳过并汇总 ④ 随时取消（已抓部分仍入库）⑤ Web 端 CORS 提示横幅 |
| **跨系统相对路径**（2026-08-20 新需求，按用户实际布局定型） | 目标布局：程序与 `novels/`、`H/` 同级（项目根），任何系统装在任何位置都能定位。三层设计：① **书库文件夹支持相对路径**（以**程序所在目录**为基准，如 `novels`、`H`）——设置页可手填或浏览选择，相对项显示解析后的实际位置，扫描时统一解析（`PlatformFs.resolvePath/programDir`）② **书籍 filePath 默认相对程序目录存储**（`PlatformFs.effectiveLibraryRoot`：显式配置「书库根目录」优先，否则程序目录；`lib/utils/book_path.dart` 盘符/分隔符/大小写兼容）③ **存量迁移支持旧系统前缀**：`analyzeBookPaths` 逐组件最长公共前缀自动推断旧库根（如 macOS 的 OneDrive 挂载路径），迁移对话框勾选后随当前根一并转换（`relativizeBookPaths(root, legacyRoots:)`）。详情页展示按本机生效基准解析。未在任何根下的路径保持不变（向后兼容）。测试：`book_path_test`（7）+ `path_migration_test`（3，含 macOS 路径真实场景） |
| **打包** | `tool/PACKAGING.md` + `tool/package_macos.sh` + `tool/package_linux.sh`；Windows 本机出包 `dist/novelmgt_flutter-1.0.0-windows-x64.zip`（20MB，冒烟通过）。注：Flutter 桌面不支持交叉编译，mac/Linux 包需在对应系统运行脚本 |
| **lint 清零（203→0）** | 移除与全库风格冲突的 `sort_constructors_first`；CLI 工具 `avoid_print` 文件级豁免；其余逐条修复（47 处 const、`value:`→`initialValue:` 弃用迁移、11 处 context.mounted 守卫、10 处 unawaited、authors 页对话框改为先关闭再异步等）。测试环境发现 `:memory:` 单例跨测试泄漏，已加 tearDown 关闭 |

### C.8 启动问题审计修复（2026-08-21，用户实测反馈）

用户实跑 Windows 版反馈「启动有不少问题 / 会调起记事本 / 错误的盘符 ///」。逐项排查定位到 **4 个真实病灶**，全部修复：

| 病灶 | 根因 | 修复 |
|---|---|---|
| 书时有时无（启动不稳定） | sqflite_ffi 默认 `getDatabasesPath()` = **当前工作目录**/.dart_tool/...，换目录启动即开新空库；且这台机的 customDbPath 曾被指向 `.dart_tool`（`flutter clean` 会清掉） | ① Windows/Linux 库固定到 `getApplicationSupportDirectory()`（`PlatformFs.stableDatabaseDir`），并自动迁移 .dart_tool / exe 同目录的旧库 ② 启动时检测 customDbPath 含 `.dart_tool` → 迁库到稳定目录并改写设置 |
| 启动报错 lock failed | Hive 默认放**文档目录**，而该目录被 OneDrive 重定向（`D:\OneDrive\文档\app_settings.lock`），同步+多实例持锁冲突 | 桌面端 Hive 固定到应用支持目录 `…/hive/`（`PlatformFs.hiveInitDir`），一次性迁移旧 box 文件；Web 端不变 |
| 会调起记事本 | `cmd /c start` 被喂了本地文件路径（非 http）时，Windows 用默认关联程序（记事本）打开 | `WebLauncher.openUrl` 仅放行 http/https，其余直接忽略 |
| 路径显示 /// 与混合分隔符 | 拼接未折叠连续斜杠；Windows 下显示正斜杠不直观 | `BookPath.normalize` 折叠 `/{2,}`；展示统一经 `PlatformFs.nativeSeparators`（Windows 反斜杠，存储仍正斜杠） |

**验证**：analyze 零问题；124 测试全过（新增 normalize 折叠用例）；实机启动确认——Hive 与 735 本书的数据库均已落在 `%APPDATA%\com.example\novelmgt_flutter\`，换任意目录启动打开同一份库。Windows 包已重打（dist/）。

### C.4 构建与运行

```bash
flutter pub get
flutter run -d chrome            # 开发调试
flutter build web                # 产物在 build/web/
# 本地预览（wasm MIME 正确）：python -m http.server -d build/web 8080
```


*文档结束 - 最后更新 2026-08-05（v1.1 状态校准版，对照 commit `ade9486`）*
## 附录 D：NAS 单文件直连模式（2026-09-03）

### D.1 目标与架构

在 NAS（fnOS 的 misc 优先，UGOS Pro 的 dx4600 后续）上部署网页版：
**浏览器直读 NAS 上的单文件书库 `novelmgt.db`，无后端 API，鉴权交给 NAS 用户体系**。

```
[Flutter web ?nas=1] --HTTP Range--> [python3 静态服务器 / nginx] --> novelmgt.db（只读）
   书架/章节：远程库直连                    fnOS: .fpk 应用(appcenter)      misc 经 NFS 读 dx4600
   进度/书签/笔记：浏览器 IndexedDB         UGOS: docker compose            dx4600 本机卷
```

### D.2 前端实现（lib/services/nas/）

| 文件 | 说明 |
|---|---|
| `nas_backend.dart` | 条件导出入口（html → web 实现，其余平台 stub） |
| `nas_backend_web.dart` | `NasReadonlyDatabase extends DatabaseService`：books/chapters/tags 读远程；progress/bookmarks/notes 写本地 `novelmgt_local.db`（IndexedDB），章节元数据两边拼合；stats 组合 |
| `nas_sql_worker.dart` | dart:js_interop 封装 `__nasBridge`；结果在 JS 侧 JSON.stringify、Dart 侧 jsonDecode（绕开 Comlink Proxy 与 dart2js 互操作的隐式转换冲突） |

- 模式入口：URL `?nas=1`（`db=` 可指定库 URL，默认 `db/novelmgt.db`）；普通模式零改动。
- 远程读引擎：vendored [sql.js-httpvfs 0.8.12](https://github.com/phiresky/sql.js-httpvfs)
  （`web/sqlite_http/`：sqlite.worker.js + sql-wasm.wasm + sqlhttp.js UMD + 自写 nas_bridge.js）。
  选型原因：Flutter web 无法起第二个 Dart 入口 worker，原生 sqlite3 wasm 又无 HttpVfs；
  sql.js-httpvfs 用 Asyncify+读头加速，在无 COOP/COEP 的静态托管上久经验证。
- 路径必须绝对化后传入 worker（worker 内相对基准是 worker 脚本自身位置）。

### D.3 服务端

- fnOS：`tool/fnos/build_fpk.py` 打出 `dist/novelmgt-fnos.fpk`（纯 tar.gz，无需 fnpack，
  结构对照 firewelly/FnOS-terminal）。python3 标准库静态服务器（含 Range 206），
  `service_port=12702`，wizard 填书库路径（默认 misc 的 NFS 挂载路径），桌面 iframe 入口
  `/index.html?nas=1`。详见 `tool/fnos/README.md`。
- UGOS Pro：等价 docker compose（README 有示例），库路径 `/volume3/hermes3/novelmgt/novelmgt.db`。
- 本地验证服务器：`tool/serve_nas_test.py`（自实现 Range；python http.server 原生不支持）。

### D.4 数据流与限制

- 书库更新：桌面端导入 → `scrapers/upload_novel_db_to_dx4600.py`（backup API 快照 +
  SFTP 断点续传上传，幂等）→ dx4600 `hermes3/novelmgt/novelmgt.db` → misc 经 NFS 直见。
- **库索引依赖**：books(createdAt/rating/wordCount)、book_tags(tagId/bookId) 已补建
  （2026-09-03）；缺失会使排序退化为全表扫描，经 HTTP 不可用。快照上传包含这些索引。
- 进度/书签/笔记按浏览器隔离（v1 无跨设备同步）；标签编辑在 NAS 模式不作用于远程库。
- SQLite 不可经 NFS 双机并发写：misc 侧只读，唯一写入方是桌面端。
- 章节标题搜索（LIKE 前置通配）首次顺序扫描标题区约 28MB，LAN 十几秒，之后走内存缓存。
- 端到端已验证（2026-09-03，Chrome + tool/serve_nas_test.py + fpk 模拟）：书架 4,529 本、
  详情 318 章、正文阅读（Range+gzip）、进度"继续阅读 1%"持久化、并发查询、搜索触发。

*文档结束 - 最后更新 2026-09-03（附录 D：NAS 单文件直连模式）*

### D.5 用户状态服务端化（2026-09-04，v2）

v1 状态存浏览器 IndexedDB（按浏览器隔离）；v2 改为服务端状态库：

- `novel_webserver.py` 增加 `/api/state/*` JSON API（进度/书签/笔记 CRUD，
  python3 标准库 sqlite3，独立状态库 `novelmgt_state.db`，与只读书库分离）。
- 前端 `lib/services/nas/nas_state_api.dart`（dart:html HttpRequest JSON 客户端）；
  `NasReadonlyDatabase` 的 progress/bookmarks/notes 读写全部改走 API，
  章节元数据仍与远程书库拼合。状态跟部署走：**同一 NAS 部署下所有浏览器/设备共享**。
- fnOS wizard 增加状态库路径字段（默认应用 var 目录）；service-setup 持久化
  `state.conf`；webserver 增加 `--state-db` 参数（缺省时 /api/state 返回 503）。
- 已验证：服务端写入 → UI「继续阅读 6%」；UI 翻章 → 服务端 chapterId/lastReadAt
  更新（createdAt 保留）；清空浏览器 IndexedDB/localStorage 后进度仍来自服务端。
- 注意：浏览器缓存可能让旧版前端驻留（无 SW，纯 HTTP 缓存）；服务端已发
  `Cache-Control: no-cache`，发布新版后强刷一次即可。
