# YYX书库 GUI 自动化测试套件

Playwright 驱动**真实部署的 YYX书库**（NAS 上的 Flutter Web + Python 服务端）做端到端 GUI 测试。
用例设计全集见 `docs/GUI_TEST_PLAN.md`（约 60 条用例矩阵，可作绿联自测报告底稿）。

## 为什么是"坐标 + API 断言"

Flutter Web 为 canvas 渲染，控件无 DOM 节点（语义树在本 Flutter 版本无法编程启用）。
因此：

- **导航**：hash 路由（`/#/reader/3`），稳定不依赖坐标；
- **页内按钮**：`anchors.py` 实测坐标（按视口标定；UI 改动后用 `--calibrate` 重新标定）；
- **文本输入**：真实 DOM `<input>`（排除常驻隐藏 input 与 file input）；
- **断言**：优先 `/api/*` 服务端状态（真值），辅以截图（人工复核）与像素采样（主题类）；
- **取证**：每个用例截图存 `reports/<时间戳>-<视口>/`，附 `report.md`。

## 使用

```bash
# 全套（桌面 1440×900）
python3 run_suite.py --base http://192.168.3.146:12702 --view desktop

# 全套（手机 390×844）
python3 run_suite.py --view mobile

# 两个视口都跑
python3 run_suite.py --view both

# 只跑某几个模块（nav,library,detail,reader,import,manual,pages,mobile,privacy,regression）
python3 run_suite.py --only reader,import

# UI 改版后重新标定锚点（输出 calibrate_*.png 标注截图）
python3 run_suite.py --calibrate
```

依赖：`pip install playwright pillow` + `playwright install chromium`。
默认含 GBK/GB18030 合成书导入（自建自清理，不污染书库）；`--slow` 另含大文件用例。

## 模块

| 模块 | 覆盖 |
|---|---|
| nav | 深链直达、侧栏/底部导航、阅读器全屏、未知路由回落 |
| library | 书架数量与 API 一致、搜索命中/空态、进详情 |
| detail | 详情元数据比对、大书渐进渲染目录、阅读按钮 |
| reader | 内容渲染、翻章递进、**翻章回顶（回归）**、**重开恢复位置（回归）**、进度 API、键盘翻章 |
| import | GBK+GB18030 导入切章、**重复导入幂等**、导入页渲染（手机视口跳过 chooser） |
| manual | 手动添加书籍对话框（仅桌面） |
| pages | 标签/作者/统计/爬虫/设置渲染与 API 比对 |
| mobile | 手机书架/详情全宽行/阅读回顶/顶栏不溢出 |
| privacy | **运行时零外部请求**（全页面遍历网络监听，隐私回归） |
| regression | 800 章大书渐进渲染计时 + 测试书清理（DELETE /api/books） |

## 实测基线（2026-11-01，DXP4800 10.0.2.0008）

- 桌面：11 通过 + 1 跳过 + **0 失败**
- 手机：28 通过 + 4 跳过 + **0 失败**

## 已知坑（写测试前必读）

1. Flutter DOM 里有一个**常驻隐藏 `<input>`**（键盘捕获），定位文本框必须
   `input:visible:not([type=file])`，否则 click/fill 永久超时；
2. 深链必须 `/#/route`（hash 路由），`/route` 会落到书架；
3. 解析器有**内容相似度去重**：合成测试书的各章正文必须互不相同，否则章节数断言失败；
4. 导入的书名来自文件名且 `-/_` 会被替换为空格——测试书名避免连字符；
5. demo 模式数据随容器重建丢失；本套件自建数据自清理，进度记录会残留（无删除 API，无害）。
