# GUI 测试报告

- 时间：2026-11-01 07:45:03
- 结果：**5/7 通过**，跳过 0，失败 2

| # | 用例 | 结果 | 说明 | 截图 |
|---|---|---|---|---|
| L-1 | 书架加载与 /api 一致（4 部） | PASS | API 4 部，截图确认 UI 渲染 | [L-1-shelf.png](L-1-shelf.png) |
| L-3 | 搜索命中与空态 | PASS |  | [L-3-search_hit.png](L-3-search_hit.png) |
| library | 流程异常 | FAIL | TimeoutError('Locator.click: Timeout 30000ms exceeded.\nCall log:\n  - waiting for locator("input").first\n    - locator resolved to <input tabindex="-1" autocorrect="on" autocomplete="on" autocapital |  |
| I-1 | TXT 导入成功（GBK+GB18030 宽容解码） | FAIL |  | [I-1-import_result.png](I-1-import_result.png) |
| I-4 | 重复导入幂等（增量合并） | PASS |  |  |
| I-9 | 导入页渲染（文件模式） | PASS | 截图确认（Web 端仅文件选择模式） | [I-9-import_page.png](I-9-import_page.png) |
| I-6 | 手动添加书籍对话框 | PASS | 新书 id=6 | [I-6-manual_saved.png](I-6-manual_saved.png) |