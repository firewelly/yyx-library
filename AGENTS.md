# AGENTS.md — YYX书库（firewelly/yyx-library）

给 AI 代理 / 新会话的最小上下文与当前待办。细节见 `docs/`、`deploy/ugos/README.md`、`deploy/fnos/`。

## 项目一句话

跨平台个人书库管理与阅读器（Flutter）：桌面端（macOS/Windows/Linux）+ Web/NAS 形态。
NAS 形态为**服务端查询架构**：Python 标准库服务端提供 `/api/*` 与静态 UI 同源托管，
客户端自动探测 `/api/health` 进入远程模式；书库 SQLite 对服务端只读，进度/书签/笔记落状态库。

## 架构与关键路径

| 事项 | 位置 |
|---|---|
| 服务端唯一源码（UGOS/fnOS 共用） | `deploy/fnos/bin/novel_server.py` |
| UGOS Pro 打包工程（ugcli） | `deploy/ugos/`（`build_upk.sh` 一键：示例库→镜像→check/pack） |
| fnOS 打包 | `deploy/fnos/build_fpk.sh`（需 `build/web` Flutter 产物） |
| 示例书库（随包分发，公版四大名著 340 章） | `deploy/ugos/demo_texts/*.json` → `make_demo_db.py` |
| 正文压缩迁移工具（存量库） | `tool/migrate_compress_content.py` |
| 正文压缩格式 | gzip BLOB；写入端 Dart `ContentCodec`（>4096 字），两端读取明文/压缩自适应 |
| 搜索范围（设计约定） | 仅 书名/作者/简介 + 章节标题索引（状态库）；**不做正文检索** |
| 发布 | GitHub Release `v10.0.1`（10.0.1.0003 upk + 2.0.1 fpk）；改动经 PR 合并 `main` |

## 环境

- **DXP4800（主测试机，UGOS Pro amd64）**：`ssh frie@192.168.3.146`（密钥已配）；Web 界面 `https://192.168.3.146:9443`，账号 `frie`（口令同 sudo）。已安装 YYX书库 10.0.1.0003，入口 `http://192.168.3.146:12702`（当前示例库模式；应用数据目录 `/volume2/@appstore/com.firewell.novelmgt/`）。注意 12704/12705 是已清理的临时测试端口。
- **GitHub 访问必须走代理**：`https_proxy=socks5h://127.0.0.1:1080`。`gh release upload` 传大文件会卡死 → 用 curl 直传 `https://uploads.github.com/.../assets?name=...`。
- **upk 开发者签名按设备绑定**：每台测试设备需绿联按其 SN 签发 `.sig`，在目标设备 应用中心 → 设置 → App development 上传（DXP4800 已配，`/ugreen/.config/ugdev.sig`，有效至 2027-09-07）。
- 上架材料与审核往来：OneDrive `Novel_scraber/novelmgt_flutter/docs/ugreen_review_20260914/`（台账 README.md、回执/、详情图/、安装包/+SHA256SUMS）。

## 当前状态（截至 2026-10-31）

- **10-31 v10.0.2 发布**（upk 10.0.2.0007 + fpk 2.0.2；PR #7/#8/#9 已并 main）：
  ① 服务端 novel_server.py 新增导入写入端点（books/chapters rw + DELETE），书库连接仍默认只读、
  写操作全局锁串行化；docker-compose 的 db 挂载由 `:ro` 改读写（升级后已自动重渲染）。
  ② 客户端 RemoteDatabaseService 覆写导入所需写方法（findBookByTitleAndAuthor/createBook/
  createChaptersBatch/updateChapterContent/touchBook/updateBook/deleteBook/runInTransaction）。
  ③ **TXT 导入乱码根因**：charset 包的 gbk 对 GB18030 四字节序列（第二字节 0x30-0x39）抛
  FormatException → 兜底按 UTF-8 解出全文乱码 → 章节切不开（紫川.txt 316 万字挤成 1 章）。
  修复：TextDecode 增加宽容 GBK 解码（结构扫描按字符边界切段，坏序列替换 U+FFFD，82ms/4MB），
  探测的 GBK 步骤同样改宽容解码。回归测试见 test/text_decode_test.dart。
  ④ **Web 导入上限 30MB→100MB**（与桌面端统一，PR #8）。
  ⑤ **移动端适配与性能**（PR #9）：宽<700 用底部导航栏；翻章回顶 + 重开书恢复上次位置
  （goToChapter 进度语义修正：旧章偏移记旧章）；数千章大书详情页章节目录渐进渲染
  （首批 300 + 每次追加 500；shrinkWrap 网格全量构建是首开卡死根因，6715 章→1.5s）；
  窄屏章节改全宽行、阅读器窄边距、书架顶栏自适应。多分辨率 E2E（390×844/844×390/1854×986）通过。
  ⑥ **全新应用图标**（书堆，PIL 绘制 1024 master，替换一直误用的 Flutter 默认图标），
  upk/fpk/web 图标源全部更新；新规范详情图 4 张（PC 1854×1236 / 移动 1125×2436，
  真实截图+品牌区合成，位于 `~/Downloads/YYX跟进材料_20261031/详情图/`）。
  E2E（DXP4800 实测）：紫川导入 165 章、45MB 重生之妖孽人生导入 6715 章、手机竖/横屏、
  翻章回顶、进度/搜索、桌面快捷方式直达全部通过。注意 demo 模式导入的书随容器重建丢失（真实库放 `db/`）。

- **审核往来时间线（读自 126/139 Mail，2026-10-31）**：
  - **YYX书库**：10-15 经 139 重新提交（附件丢失）→ 10-18 经 126 补发材料包 →
    **10-19 绿联回复：缺「主流程说明/自测用例报告/基本信息表」要求补**（此回复晚于 10-18 补发，
    疑未处理到）→ **截至 10-31 YYX 线程无新回复，10-18 补发是否收到未确认**。
  - **NasOC**：10-12 第二轮意见（架构/隐私弹窗/许可协议关联证明/视觉规范）→ 10-17 提交 v0.1.0.0010 →
    10-19 第三轮意见（MIT 证明+具体版权声明+**详情图新尺寸 PC 1854×1236 / 移动 1125×2436**，每端≥2张）→
    10-21 提交 v0.1.0.0011 → 10-21 绿联：信息表缺电话/注册地址 + 承诺函需签字 → 10-23 绿联：
    注册地址个人不适用，**请完善表格后随附已签字《承诺函》重新提交**（本地表格 10-05 起就已填全电话，
    绿联审的是旧版）。
  - **DX4600 调试签名**：10-19 申请 → 10-19 绿联要 MAC+用户名 → 10-26 已提供
    （MAC `98:6e:e8:21:a6:4f` / frie），**签名承诺 5 个工作日内出（约 11-03 前），注意查收**。
  - **10-31 已在 Mail.app 备好两封草稿（未发送，待用户过目后发送）**：
    ① YYX 线程跟进：确认 10-18 补发 + 告知 v10.0.2 + 附新版信息表(10.0.2.0007)/新规范详情图/圆角图标/承诺函重发；
    ② NasOC 回信：附完善后信息表(v0.1.0.0011) + 已签字承诺函。
    材料在 `~/Downloads/YYX跟进材料_20261031/`、`~/Downloads/NasOC回信材料_20261031/`。
    **教训（10-15 事故复现）**：发后必须从已发送确认附件真实发出。
  - **上架合规待办（YYX，大概率被要求）**：应用内首启「隐私政策/用户协议」弹窗并取得用户主动同意
    （10-12 对 NasOC 的要求，YYX upk 尚未做）。

- 9/14 绿联初审反馈**全部修复**并在 DXP4800 实测通过：应用中心安装、桌面图标持久、
  局域网与 UGREENlink 中继（web 端全流程：书架/详情/阅读/翻章/搜索/统计/进度保存）。
- 存量书库正文已全部 gzip 迁移：5.37GB → 2.61GB（备份 `novelmgt.db.bak-plain-20261006` 保留在原目录）。
- 回执材料就绪：信息表（10.0.1.0003）、自测用例报告（全部实测项已填「通过」）、详情图 PC×3 + 移动×3。
- NAS 打包工作区：DXP4800 `~/yyx-repo`（deploy + build/web 的 rsync 目标，跑 `deploy/ugos/build_upk.sh`；
  ugcli 是文件 `/home/frie/ugcli`，用 `UGCLI=/home/frie/ugcli` 指定）。

## 剩余待办

> 1–2 项已完成：**2026-10-15** 经 139 邮箱重新提交审核（该邮件附件实际未发出），
> **2026-10-18** 经 126 邮箱补发承诺函扫描件 + `YYX书库_补发材料_20261018.zip`（MIME 已验证完整）。
> 当前**等绿联回复**。历史草稿：`提交邮件草稿-20261008.md` 与 `附件包_20261008.zip`（OneDrive ugreen_review_20260914/）。
> 教训：139 邮箱发信附件会丢，给绿联发信一律走 126 客户端并在发送后验证附件。

1. ~~【提交审核】向绿联重新提交修复版~~ **已完成（2026-10-15 提交 / 10-18 补发附件，见上）**。
2. ~~【承诺函】~~ **已完成**：已签字按手印扫描（`~/Downloads/novelmgt-20261015134755-0001.pdf`），10-18 补发。
3. **【新设备调试签名】**在外机装 upk 需先为该设备 SN 申请 `.sig`
   （开发者平台添加设备 SN，或回信 developers_bd@ugreen.com 报型号+SN），
   拿到后在目标设备 App development 标签上传；upk 仅 amd64、要求 UGOS Pro ≥1.13。
   **DX4600（SN EC554JJ11230BF62）2026-10-19 邮件申请；绿联要求补 MAC+管理员用户名，
   10-26 已回信提供（MAC `98:6e:e8:21:a6:4f` eth0 主网卡 / 用户名 frie），签名承诺提供后 5 个工作日内出**；
   收到后上传其 App development。
4. ~~【fnOS 2.0.1 fpk 升级】~~ **已完成（2026-10-11）**：EQ14（192.168.3.153）在线后经
   `appcenter-cli` 卸载重装 2.0.1 fpk，向导变量（真库路径）自动保留；API + Web UI 全流程、
   示例库兜底（demo-db）、跨会话进度持久化全部实测通过。appcenter-cli 用法与坑见 fnos-app-development 记忆。
   **10-25 补修桌面图标**：CLI 装包缺 `appcenter.app_service` 注册导致 fnOS 桌面不出图标；
   已补注册+图标并验证（脚本 `deploy/fnos/register_after_cli_install.sh`）。
   残留：应用中心详情页"打开"钮灰（GUI 卸载重装可彻底修复），桌面图标与 `:12702` 直访正常。
5. （可选）**把迁移后的真库挂到已安装应用**：拷贝
   `/volume2/docker/novelmgt/db/novelmgt.db`（2.61GB）→ `/volume2/@appstore/com.firewell.novelmgt/db/`
   并重启容器；注意审核员看到的就是这个库（当前为示例库模式）。
6. （可选）**确认无误后删除 5GB 备份** `/volume2/docker/novelmgt/db/novelmgt.db.bak-plain-20261006`。
7. （可选）**移动端 UGREENlink 真机复测**：自测报告 E8 目前是「同链路核验」口径，如需完美可真机补测。

## 常用验证命令

```bash
# 应用健康（DXP4800）
curl http://192.168.3.146:12702/api/health          # {"ok":true,"books":N,"demo":true/false}
# 重打包 upk（在 NAS 上；工程 /home/frie/yyx-upk，ugcli /home/frie/ugcli）
cd /home/frie/yyx-upk && /home/frie/ugcli check && /home/frie/ugcli pack --build N --arch amd64
# 镜像构建上下文（NAS /home/frie/yyx-v2：ui + bin/novel_server.py + demo/）
# 仓库侧一键脚本：deploy/ugos/build_upk.sh（需 docker + ugcli 的 Linux 环境）
```
