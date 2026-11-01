# GUI 测试报告

- 时间：2026-11-01 08:04:33
- 结果：**11/12 通过**，跳过 1，失败 0

| # | 用例 | 结果 | 说明 | 截图 |
|---|---|---|---|---|
| N-1 | 深链直达各页 | PASS | 7 条深链全部渲染（见截图） | [N-1-route_settings.png](N-1-route_settings.png) |
| N-2 | 桌面侧栏逐项切换 | PASS | 侧栏切换后回到书架 | [N-2-sidebar_round.png](N-2-sidebar_round.png) |
| N-3 | 手机底部导航切换 | SKIP | 桌面视口用 N-2 | |
| N-4 | 阅读器独立全屏（无外壳） | PASS | 路由在 /reader/1 | [N-4-reader_fullscreen.png](N-4-reader_fullscreen.png) |
| N-5 | 未知路由回落有效页 | PASS | 未崩溃（见截图） | [N-5-unknown_route.png](N-5-unknown_route.png) |
| R-1 | 第一章内容渲染 | PASS | 路由在阅读器 | [R-1-reader_ch1.png](R-1-reader_ch1.png) |
| R-2 | 下一章翻章（序号递进） | PASS | 进度已落库：chapterId=225 | [R-2-reader_ch2.png](R-2-reader_ch2.png) |
| R-3 | 翻章后回到顶部（回归） | PASS | 截图确认新章从标题开始（非滚动中部） | [R-3-reader_next_top.png](R-3-reader_next_top.png) |
| R-10 | 键盘 ←/→ 翻章 | PASS | http://192.168.3.146:12702/#/reader/3 → 键盘翻章后截图 | [R-10-reader_arrow.png](R-10-reader_arrow.png) |
| R-4 | 重开书恢复上次阅读章节（回归） | PASS | 重进后进度章节一致（226） | [R-4-reader_reopen.png](R-4-reader_reopen.png) |
| R-5 | 进度 API 结构完整 | PASS | 字段：['id', 'bookId', 'chapterId', 'scrollPosition', 'lastReadAt', 'createdAt'] |  |
| RG-1 | 运行时零外部请求（隐私回归） | PASS | 全页面遍历外部请求数 = 0 |  |