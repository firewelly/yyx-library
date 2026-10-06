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

## 当前状态（截至 2026-10-06）

- 9/14 绿联初审反馈**全部修复**并在 DXP4800 实测通过：应用中心安装、桌面图标持久、
  局域网与 UGREENlink 中继（web 端全流程：书架/详情/阅读/翻章/搜索/统计/进度保存）。
- 存量书库正文已全部 gzip 迁移：5.37GB → 2.61GB（备份 `novelmgt.db.bak-plain-20261006` 保留在原目录）。
- 回执材料就绪：信息表（10.0.1.0003）、自测用例报告（全部实测项已填「通过」）、详情图 PC×3 + 移动×3。

## 剩余待办

> 用户计划 **2026-10-08** 执行 1–3 项。提交材料已备齐（2026-10-06）：
> 邮件草稿 `提交邮件草稿-20261008.md` 与附件包 `附件包_20261008.zip`（52.8MB，
> 含 upk/信息表/自测报告/详情图 6 张，均在 OneDrive ugreen_review_20260914/ 目录）。

1. **【提交审核】向绿联重新提交修复版**（计划 2026-10-08）
   按 `提交邮件草稿-20261008.md` 发邮件至 developers_bd@ugreen.com，
   附件用 `附件包_20261008.zip`（邮件超限则改发 GitHub Release 链接 + 网盘）。
2. **【承诺函】**《开发者承诺函_novelmgt已填待签署.docx》签字按手印（计划 2026-10-08，按需附上）。
3. **【新设备调试签名】**在外机装 upk 需先为该设备 SN 申请 `.sig`
   （开发者平台添加设备 SN，或回信 developers_bd@ugreen.com 报型号+SN），
   拿到后在目标设备 App development 标签上传；upk 仅 amd64、要求 UGOS Pro ≥1.13。
4. **【待 EQ14 在线】fnOS 2.0.1 fpk 升级**：EQ14（192.168.3.153）当前离线；
   新 fpk 含示例库兜底与 `--demo-db`，上线后在 fnOS 应用中心原地升级即可。
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
