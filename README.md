# YYX书库（YYX Library）

> 跨平台个人书库管理与阅读器（Flutter）：macOS / Windows / Linux 桌面端 + **Web 端（NAS 网页版）**。
> Web 端架构：浏览器内 SQLite(WASM) 经 HTTP Range 直读书库文件（对 NAS 完全只读），
> 服务端仅需任意静态服务器 + 极小状态 API（参考 `tool/`）。

书架管理、阅读器、导入导出、统计、标签。

支持平台：**macOS / Windows / Linux 桌面端**（主力）+ **Web**（浏览器预览/轻量使用）。

## 运行

```bash
flutter pub get

# 桌面端（Windows 示例）
flutter run -d windows

# Web 端
flutter run -d chrome
flutter build web          # 产物在 build/web/，可直接静态部署
```

Web 本地预览需正确服务 wasm MIME（不要用 file:// 打开）：

```bash
python -m http.server -d build/web 8080
```

## 特色功能

- **多编码导入**：TXT 自动探测 UTF-8 → GBK/GB18030 → Big5（纯 Dart 解码，桌面/Web 行为一致）；乱码时可在「设置-导入设置」手动指定编码
- **繁简切换**：阅读器顶栏一键切换 原文/简体/繁体（内置 OpenCC 词典，词组级转换）
- **繁简搜索**：书库搜索与书内章节搜索均同时匹配简体与繁体（查「小说」可命中「小說」）
- **SQL 备份**：全平台通用的 .sql 备份/恢复，Web 端数据可迁移到桌面端（反之亦然）
- **跨系统共享书库**：三层相对路径设计——① 书库扫描文件夹可填相对路径（如 `novels`、`H`，以程序所在目录为基准）② 书籍路径默认存为相对程序目录的形式 ③ 存量数据迁移时自动识别旧系统的绝对路径前缀（如 macOS 挂载路径）一并转换。把程序、`novels/`、`H/` 放同一目录，配合「自定义数据库路径」指向同步盘，macOS/Windows/Linux 可共用同一份库

## 打包

桌面端不支持交叉编译，各平台包需在对应系统构建，见 `tool/PACKAGING.md`。Windows：`flutter build windows --release` 后压缩 `build\windows\x64\runner\Release\`；macOS/Linux 分别运行 `tool/package_macos.sh` / `tool/package_linux.sh`。

## Web 端说明

- 数据保存在浏览器 **IndexedDB**（SQLite WASM），与桌面端数据库互不相通
- 导入：支持选择 TXT/EPUB/PDF/MOBI/AZW3 文件（浏览器读取字节导入）；TXT 支持 UTF-8/GBK/GB18030/Big5 自动探测与手动指定
- 导出：TXT/EPUB/PDF/Kindle 逐本触发浏览器下载
- 桌面专属功能（书库文件夹扫描、批量文件夹导入、缓存清理、自定义数据库路径）在 Web 端隐藏；备份/恢复以 SQL 下载/上传实现

详细架构与功能矩阵见 `docs/REQUIREMENTS.md` 附录 C。

## 文档

- `docs/PRD_FLUTTER.md` 产品需求
- `docs/DESIGN_FLUTTER.md` 技术设计
- `docs/REQUIREMENTS.md` 需求实现对照与缺陷清单
