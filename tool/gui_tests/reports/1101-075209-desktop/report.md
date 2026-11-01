# GUI 测试报告

- 时间：2026-11-01 07:57:13
- 结果：**27/30 通过**，跳过 2，失败 1

| # | 用例 | 结果 | 说明 | 截图 |
|---|---|---|---|---|
| N-1 | 深链直达各页 | PASS | 7 条深链全部渲染（见截图） | [N-1-route_settings.png](N-1-route_settings.png) |
| N-2 | 桌面侧栏逐项切换 | PASS | 侧栏切换后回到书架 | [N-2-sidebar_round.png](N-2-sidebar_round.png) |
| N-3 | 手机底部导航切换 | SKIP | 桌面视口用 N-2 | |
| N-4 | 阅读器独立全屏（无外壳） | PASS | 路由在 /reader/1 | [N-4-reader_fullscreen.png](N-4-reader_fullscreen.png) |
| N-5 | 未知路由回落有效页 | PASS | 未崩溃（见截图） | [N-5-unknown_route.png](N-5-unknown_route.png) |
| L-1 | 书架加载与 /api 一致（4 部） | PASS | API 4 部，截图确认 UI 渲染 | [L-1-shelf.png](L-1-shelf.png) |
| L-3 | 搜索命中与空态 | PASS |  | [L-3-search_hit.png](L-3-search_hit.png) |
| library | 流程异常 | FAIL | TimeoutError('Locator.click: Timeout 30000ms exceeded.\nCall log:\n  - waiting for locator("input:visible:not([type=file])").first\n') |  |
| BD-1 | 详情元数据与 API 一致（GUI测试书） | PASS | API 章节数 8，截图人工比对 | [BD-1-detail.png](BD-1-detail.png) |
| BD-2 | 章节目录渐进渲染（大书 ≤300 首屏 + 显示更多） | SKIP | 当前书仅 8 章，大书用例见 RG-3 | |
| BD-9 | 阅读按钮存在 | PASS | 截图确认 继续阅读/开始阅读 按钮 |  |
| R-1 | 第一章内容渲染 | PASS | 路由在阅读器 | [R-1-reader_ch1.png](R-1-reader_ch1.png) |
| R-2 | 下一章翻章（序号递进） | PASS | 进度已落库：chapterId=1160 | [R-2-reader_ch2.png](R-2-reader_ch2.png) |
| R-3 | 翻章后回到顶部（回归） | PASS | 截图确认新章从标题开始（非滚动中部） | [R-3-reader_next_top.png](R-3-reader_next_top.png) |
| R-10 | 键盘 ←/→ 翻章 | PASS | http://192.168.3.146:12702/#/reader/9 → 键盘翻章后截图 | [R-10-reader_arrow.png](R-10-reader_arrow.png) |
| R-4 | 重开书恢复上次阅读章节（回归） | PASS | 重进后进度章节一致（1161） | [R-4-reader_reopen.png](R-4-reader_reopen.png) |
| R-5 | 进度 API 结构完整 | PASS | 字段：['id', 'bookId', 'chapterId', 'scrollPosition', 'lastReadAt', 'createdAt'] |  |
| I-1 | TXT 导入成功（GBK+GB18030 宽容解码） | PASS | 新书入库 id=10 章节数=8（预期 8） | [I-1-import_result.png](I-1-import_result.png) |
| I-4 | 重复导入幂等（增量合并） | PASS | 章节数不变（8），无重复建书 |  |
| I-9 | 导入页渲染（文件模式） | PASS | 截图确认（Web 端仅文件选择模式） | [I-9-import_page.png](I-9-import_page.png) |
| I-6 | 手动添加书籍对话框 | PASS | 新书 id=11 | [I-6-manual_saved.png](I-6-manual_saved.png) |
| T-1 | 标签页渲染（4 个标签） | PASS | API 标签数 4，截图比对 | [T-1-tags.png](T-1-tags.png) |
| A-1 | 作者页渲染（4 位作者） | PASS | API 作者集合 ['吴承恩', '曹雪芹', '未知', '罗贯中']…，截图比对 | [A-1-authors.png](A-1-authors.png) |
| S-1 | 统计页渲染（总书籍 4） | PASS | API totalBooks=4 totalChapters=340 | [S-1-stats.png](S-1-stats.png) |
| C-1 | 爬虫页渲染（不发真实请求） | PASS | 截图确认书源列表渲染（离线安全） | [C-1-crawler.png](C-1-crawler.png) |
| ST-1 | 设置页渲染 | PASS | 截图确认各分区 | [ST-1-settings.png](ST-1-settings.png) |
| RG-1 | 运行时零外部请求（隐私回归） | PASS | 全页面遍历外部请求数 = 0 |  |
| RG-3 | 大书（800 章）详情页渐进渲染 | PASS | 打开耗时 10.0s（含加载等待），截图确认首屏目录已渲染 | [RG-3-bigbook_detail.png](RG-3-bigbook_detail.png) |
| BD-3 | 「显示更多章节」追加 | PASS | 截图确认加载更多按钮（章节 >300 时出现） | [BD-3-bigbook_more.png](BD-3-bigbook_more.png) |
| RG-7 | 测试书清理（DELETE /api/books） | PASS | 已删除 GUI-大书测试 |  |