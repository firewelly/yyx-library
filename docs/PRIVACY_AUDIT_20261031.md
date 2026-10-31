# YYX书库 隐私审计报告（2026-10-31）

**范围**：v10.0.2（upk 10.0.2.0008 / fpk 2.0.2）安装包内容 + 项目源码 + 运行时网络行为
**方法**：依赖清单审查、源码外联扫描、编译产物 URL 扫描、包内容解包检查、
Playwright 运行时网络监控（遍历全部主要页面 + 手机视口）、与 PRIVACY.md 声明逐条比对。

## 结论

**审计后应用可完全离线运行：运行时外部请求数 = 0**，与 PRIVACY.md
「不进行任何外部网络通信（除用户主动发起的爬虫访问）」声明一致。

## 审计项与结果

### 1. 依赖清单（pubspec.yaml）✓

无任何分析/广告/遥测 SDK（无 firebase/analytics/crashlytics/admob/sentry/umeng/google_fonts）。
全部依赖为功能性本地库：sqflite（SQLite）、hive（本地 KV）、file_picker、epubx/pdfrx/kindle_unpack
（格式解析）、archive（gzip）、charset/dart3_big5（编码）、http/dio（用户书库/爬虫的网络访问）。

### 2. 服务端（deploy/fnos/bin/novel_server.py）✓

Python 标准库实现，**零主动外联**（无 urllib.request/requests/http.client/socket 外连）。
仅监听 12702 提供本机 API 与静态资源；数据落本地 SQLite（书库只读 + 状态库可写）。

### 3. 源码外联扫描 ✓

客户端代码中的外部地址仅有三类：
1. **爬虫内置书源**（lib/models/book_source.dart：zzxx.org / yebiquge.com / 22biqu.com）——
   仅当用户主动进入「爬虫」页搜索/抓取时访问，符合 PRIVACY.md「用户主动发起」条款；
2. XML/EPUB 解析命名空间常量（不产生请求）；
3. 应用自身源码/隐私政策链接（展示用）。

### 4. Web 构建产物 ✗ → ✓（本次修复）

**发现的问题（运行时监控实测 171 个外部请求）**：
- CanvasKit 渲染引擎从 `gstatic.com` 加载（此前 index.html 的本地配置未覆盖全部路径）；
- 中文回退字体（Noto Sans SC/TC、Noto Color Emoji、JP/Symbols）从 `fonts.gstatic.com`
  按需拉取约 170 个字体子集——浏览器 IP/User-Agent 暴露给 Google CDN；
  且国内网络下 gstatic 不可达 → 白屏/中文豆腐块（也是"首次打开慢"的因素之一）。

**修复**：
1. `flutter build web --no-web-resources-cdn`：CanvasKit/引擎资源全部本地打包；
2. `web/fonts.gstatic.com/s/` 本地字体镜像（452 个子集，15MB，Noto 系列为 SIL OFL 许可，
   允许随包分发；文件清单来自引擎运行时实测请求 + 按引擎子集编号枚举补全）；
3. `tool/patch_web_offline_fonts.py`：编译产物中字体回退基址
   `https://fonts.gstatic.com/s/` → 相对路径 `fonts.gstatic.com/s/`
   （该常量在当前 Flutter 3.47 loader 中无配置透传，故做产物补丁；已挂入
   `deploy/ugos/build_upk.sh` 与 `deploy/fnos/build_fpk.sh`，幂等可重跑）。

**修复后运行时验证**：遍历 书库/详情/阅读器/导入/爬虫/统计/标签/作者/设置 +
手机视口，**外部请求数 0、资源加载失败 0**。

### 5. 包内容清单（fpk 解包 + docker 镜像）✓

载荷仅四类：`bin/novel_server.py`（服务端）、`ui/`（Flutter Web 产物 + 本地字体镜像 +
本地 canvaskit/sqlite wasm）、`demo/novelmgt-demo.db`（公版古籍示例库，来源维基文库，
sourceUrl 均指向 zh.wikisource.org）、图标资源。
无密钥/凭据/个人数据/多余文件（"password/token" 命中均为框架自动补全提示与 PDF 参数文档）。

### 6. 权限与网络面 ✓

docker-compose 仅映射 12702 端口，无额外 capabilities/特权；书库目录读写（Web 导入需要），
其余数据仅存应用数据目录。应用不申请任何设备权限（与信息表声明一致）。

### 7. PRIVACY.md 一致性 ✓

修复后全部声明与实际行为一致：无数据收集、无遥测、数据仅存用户 NAS、
外部通信仅限用户主动发起的爬虫访问。

## 遗留说明

- 爬虫功能的内置书源指向第三方小说站，其内容合规性由使用者自行负责（政策已声明）；
- 用户若通过 UGREENlink 远程访问，流量经由绿联中继通道，属用户自行配置的远程访问方式。
