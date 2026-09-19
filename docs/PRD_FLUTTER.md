# 小说管理系统 Flutter 版 - 产品需求文档 (PRD)

## 文档信息

| 项目 | 内容 |
|------|------|
| **文档版本** | 1.0 |
| **创建时间** | 2026-04-08 |
| **技术栈** | Flutter + Riverpod + sqflite/Hive + dio |
| **目标平台** | macOS / Windows / Linux 桌面端（主力），Web（辅助） |

---

## 1. 项目概述

### 1.1 项目名称
NovelMgt Flutter（小说管理系统跨平台版）

### 1.2 项目目标
基于现有 Python/Flet 版小说管理系统的功能需求，使用 Flutter 技术栈彻底重构，打造一个：
- 架构清晰、类型安全的现代化跨平台桌面+Web 应用
- 功能完整的小说全生命周期管理平台
- 具备完善自动化测试的高质量工程
- 一套代码，桌面主力使用、Web 辅助访问

### 1.3 核心技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **UI 框架** | Flutter 3.x + Material 3 | 跨平台 UI，桌面+Web |
| **状态管理** | Riverpod + riverpod_generator | 类型安全、测试友好、代码生成 |
| **结构化存储** | sqflite | 书籍、章节、阅读进度等 |
| **偏好存储** | Hive | 主题、字体、边距等用户设置 |
| **网络请求** | dio | NAS 后端通信预留 |
| **序列化** | json_serializable + freezed | 数据模型 JSON 序列化 |
| **路由** | go_router | 声明式路由，深链接支持 |
| **文件解析** | epubx + charset_detect | EPUB 解析 + 编码检测 |
| **测试** | flutter_test + mockito + integration_test | 单元/Widget/端到端完整覆盖 |

---

## 2. 功能需求

### 2.1 小说管理（CRUD）
- **添加小说**：手动输入标题、作者、简介、状态(连载中/已完结)、标签
- **编辑小说**：修改基本信息、标签、评分(1-5星)、备注
- **删除小说**：带确认对话框，级联删除章节、标签关联、阅读进度、书签、笔记
- **搜索小说**：标题/简介模糊搜索，支持章节全文搜索
- **筛选小说**：按标签、状态、评分筛选
- **排序小说**：按标题、章节数、字数、评分、导入时间排序

### 2.2 导入功能
- **TXT 导入**：单文件 + 批量文件夹导入（递归）
- **自动编码识别**：UTF-8, GBK, GB2312, BIG5, UTF-16
- **智能章节识别**：中文数字、阿拉伯数字、英文 Chapter
- **章节去重和重排序**
- **EPUB 导入**：解析元数据（标题、作者、简介）、提取章节内容
- **导入进度可视化**：进度条+实时百分比
- **导入后删除原文件**（可选）

### 2.3 爬取功能（预留，Phase 2）
- 多网站支持（框架预留，具体站点适配后续实现）
- 断点续传、多线程并发
- 水印清理模块预留

### 2.4 章节管理
- 章节列表：三列网格布局，升序排列
- 章节编辑：修改标题、内容
- 章节删除：带确认
- 章节重排序：自动识别序号重新排列
- 章节搜索：在章节内搜索关键词

### 2.5 阅读功能
- **阅读器**：基于 PageView 的章节内容显示
- **字体大小调整**：12-30，步进1
- **左右边距调整**：20-200，步进10
- **行间距调整**：1.0-3.0，步进0.1
- **章节导航**：上一章/下一章，快速跳转
- **键盘快捷键**：← → ↑ ↓ PageUp PageDown Home End
- **阅读进度自动记录与恢复**
- **深色/浅色/跟随系统主题**

### 2.6 书签功能
- 添加/删除书签
- 书签列表管理（按时间降序）
- 点击书签快速跳转
- 书签备注

### 2.7 笔记功能
- 在章节中添加笔记
- 笔记与章节+位置关联
- 笔记列表查看
- 笔记编辑与删除

### 2.8 导出功能
- TXT 格式导出：包含标题、作者、简介、所有章节
- EPUB 格式导出：标准电子书含目录
- 导出路径可选
- 批量导出

### 2.9 标签管理
- 添加、编辑、删除标签
- 标签筛选（下拉框）
- 查看标签下小说数量
- 标签颜色自定义

### 2.10 统计与可视化
- 总小说数、总章节数、总字数、作者数
- 状态分布（连载中/已完结）
- 评分分布
- 标签 Top 10、作者 Top 10
- 最近阅读列表

### 2.11 设置与偏好
- **阅读设置**：字体大小、边距、行间距、主题
- **导入设置**：默认编码、是否删除原文件
- **导出设置**：默认路径、默认格式
- **数据管理**：数据库备份/恢复、缓存清理
- **自动备份**：可配置频率和保留份数

### 2.12 键盘快捷键

| 快捷键 | 功能 | 适用页面 |
|--------|------|---------|
| `Ctrl+F` | 聚焦搜索框 | 全局 |
| `Ctrl+I` | 打开导入 | 全局 |
| `Ctrl+S` | 打开设置 | 全局 |
| `←` | 上一章 | 阅读器 |
| `→` | 下一章 | 阅读器 |
| `↑` | 向上滚动 | 阅读器 |
| `↓` | 向下滚动 | 阅读器 |
| `PageUp/PageDown` | 翻页 | 阅读器 |
| `Home/End` | 顶/底部 | 阅读器 |
| `Ctrl+B` | 书签 | 阅读器 |
| `Ctrl+N` | 笔记 | 阅读器 |
| `Esc` | 返回 | 全局 |

---

## 3. 非功能需求

### 3.1 性能
| 指标 | 目标 |
|------|------|
| 冷启动 | < 2 秒 |
| 书籍列表加载 (1000本) | < 500ms |
| 全文搜索 (10万章节) | < 1.5 秒 |
| 批量导入 (100文件) | < 30 秒 |
| 内存占用 | < 300MB |

### 3.2 可用性
- 直观 Material 3 界面，窗口空间充分利用"平铺满页"
- 两栏/三栏响应式布局（窄屏2栏，宽屏3栏）
- 操作即时反馈（SnackBar、进度条）
- 重要操作（删除、覆盖）需确认

### 3.3 可靠性
- 数据完整性：sqflite 事务保证
- 异常处理：文件/网络操作均 try-catch
- 断点续传：导入/爬取中断可继续

### 3.4 平台兼容
- **桌面**：macOS 12+, Windows 10+, Ubuntu 20.04+
- **Web**：现代浏览器（Chrome/Firefox/Safari/Edge 最新两版）
- **屏幕**：≥ 1280×720

### 3.5 测试覆盖

| 测试类型 | 覆盖目标 |
|---------|---------|
| 单元测试 | ≥ 80% 业务逻辑层 |
| Widget 测试 | 主流程 UI 组件 |
| 集成测试 | 导入、阅读、进度恢复 |

---

## 4. 数据模型

### 4.1 核心表结构

**books 表**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| title | TEXT NOT NULL | 书名 |
| author | TEXT | 作者 |
| summary | TEXT | 简介 |
| status | TEXT DEFAULT '连载中' | 状态 |
| source_url | TEXT | 来源URL |
| cover_image | TEXT | 封面URL |
| cover_image_path | TEXT | 本地封面路径 |
| rating | INTEGER DEFAULT 0 | 评分(0-5) |
| notes | TEXT | 备注 |
| word_count | INTEGER DEFAULT 0 | 总字数 |
| last_read_at | TEXT | 最后阅读时间(ISO8601) |
| created_at | TEXT NOT NULL | 创建时间 |
| updated_at | TEXT NOT NULL | 更新时间 |

**chapters 表**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| book_id | INTEGER FK | 所属书籍 |
| chapter_number | INTEGER NOT NULL | 章节序号 |
| original_order | INTEGER | 原始序号 |
| title | TEXT NOT NULL | 章节标题 |
| content | TEXT NOT NULL | 章节内容 |
| source_url | TEXT | 来源URL |
| created_at | TEXT NOT NULL | 创建时间 |

**tags 表**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| name | TEXT NOT NULL UNIQUE | 标签名 |
| color | TEXT DEFAULT '#1976D2' | 标签颜色 |

**book_tags 表**（多对多关联）
| 字段 | 类型 | 说明 |
|------|------|------|
| book_id | INTEGER FK | 书籍ID |
| tag_id | INTEGER FK | 标签ID |

**reading_progress 表**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| book_id | INTEGER FK UNIQUE | 书籍ID |
| chapter_id | INTEGER FK | 当前章节ID |
| scroll_position | INTEGER DEFAULT 0 | 滚动位置 |
| last_read_at | TEXT | 最后阅读时间 |

**bookmarks 表**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| book_id | INTEGER FK | 书籍ID |
| chapter_id | INTEGER FK | 章节ID |
| position | INTEGER DEFAULT 0 | 字符偏移 |
| title | TEXT | 书签标题 |
| note | TEXT | 书签备注 |
| created_at | TEXT NOT NULL | 创建时间 |

**notes 表**
| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增主键 |
| book_id | INTEGER FK | 书籍ID |
| chapter_id | INTEGER FK | 章节ID |
| position | INTEGER DEFAULT 0 | 字符偏移 |
| content | TEXT NOT NULL | 笔记内容 |
| created_at | TEXT NOT NULL | 创建时间 |
| updated_at | TEXT NOT NULL | 更新时间 |

---

## 5. 开发阶段

### Phase 1 — 核心架构与基础 CRUD（当前）
- [x] 项目骨架搭建
- [ ] 数据模型定义
- [ ] sqflite DatabaseService
- [ ] Hive SettingsService
- [ ] Riverpod Providers
- [ ] TXT/EPUB 导入
- [ ] TXT/EPUB 导出
- [ ] 主界面（书籍列表网格/列表视图）
- [ ] 书籍详情页
- [ ] 阅读器基础版
- [ ] 单元测试 + Widget 测试

### Phase 2 — 完善功能
- [ ] 书签 / 笔记完整 CRUD
- [ ] 高级搜索 / 全文检索
- [ ] 统计面板
- [ ] 设置页面全功能
- [ ] 爬虫框架搭建
- [ ] NAS 同步（dio）

### Phase 3 — 打磨与发布
- [ ] 集成测试覆盖
- [ ] 性能优化
- [ ] 桌面端打包（macOS/Windows/Linux）
- [ ] Web 端适配部署
- [ ] 数据库迁移脚本
- [ ] 用户文档