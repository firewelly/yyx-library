# GUI 测试报告

- 时间：2026-11-01 07:46:42
- 结果：**2/3 通过**，跳过 0，失败 1

| # | 用例 | 结果 | 说明 | 截图 |
|---|---|---|---|---|
| I-1 | TXT 导入成功（GBK+GB18030 宽容解码） | FAIL | 未在 API 找到新书或总数异常 | [I-1-import_result.png](I-1-import_result.png) |
| I-4 | 重复导入幂等（增量合并） | PASS |  |  |
| I-9 | 导入页渲染（文件模式） | PASS | 截图确认（Web 端仅文件选择模式） | [I-9-import_page.png](I-9-import_page.png) |