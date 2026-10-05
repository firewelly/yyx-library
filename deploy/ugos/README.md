# YYX书库 · UGOS Pro（绿联云）应用打包

上架 UGOS Pro 应用中心（nasync 系列）的 Docker 应用工程。

## 架构（v10 起：服务端查询）

```
浏览器 ──HTTP──► 容器 novelmgt (python:3.11-slim)
                  ├─ /            Flutter Web 静态资源（ui/）
                  ├─ /api/books…  书库查询（服务端打开 SQLite，读全书库）
                  └─ /api/user/…  进度 / 书签 / 笔记（状态库，可写）
     挂载：./db    用户书库目录（novelmgt.db，只读）
           ./state 阅读状态（novelmgt_state.db，升级保留）
```

与旧版「浏览器 SQLite WASM + HTTP Range 直读」相比，查询全部在 NAS 本地完成：
书架分页、章节树、全文检索都不再受浏览器端读取大文件的影响（旧版对 5 GB 级
书库会卡在章节搜索上）。

**首次安装的初版书库**：容器内置示例书库（四大名著，公版古籍原文），
用户把 `novelmgt.db` 放进应用数据目录 `db/` 并重启应用后即切换为个人书库。
服务端在 `/api/health` 用 `"demo": true/false` 标明当前是否为示例库。

## 目录

| 路径 | 说明 |
|---|---|
| `project.yaml` | 应用元数据（合规链接、描述、端口、依赖） |
| `Dockerfile` | 镜像定义（ui + bin + demo） |
| `rootfs_common/` | 所有架构共用：`docker-compose.yaml`（`{{.TZ}}` 由 ugcli 替换）、`icon.png` |
| `rootfs_amd64/images/` | 导出的镜像 tar（`build_upk.sh` 生成，不入库） |
| `fetch_demo_texts.py` | 抓取公版古籍原文（维基文库）→ `demo_texts/*.json` |
| `make_demo_db.py` | 由 `demo_texts/` 构建示例书库 `novelmgt-demo.db` |
| `build_upk.sh` | 一键：示例库 → 镜像 → `ugcli check/pack` |

服务端源码只有一份：`deploy/fnos/bin/novel_server.py`（fnOS 与 UGOS 共用）。

## 打包步骤

在有 docker 与 [ugcli](https://developer.ugreen.com) 的 Linux 机器上
（本项目实际使用的是 DXP4800：`/home/frie/ugcli/ugcli`）：

```bash
# 0) 前端产物（仓库根目录，需要 Flutter SDK）
flutter build web --release

# 1) 首次打包前抓一次公版原文（已入库，可跳过；除非要更新示例书库）
python3 deploy/ugos/fetch_demo_texts.py

# 2) 一键打包（构建号 +1，产出 10.0.1.<n>）
UGCLI=/home/frie/ugcli/ugcli deploy/ugos/build_upk.sh --build 3

# 产物
ls deploy/ugos/build/pkgs/upk/
```

没有 docker 的机器可只做前端与示例库，把两者拷到 NAS 构建镜像：

```bash
python3 deploy/ugos/make_demo_db.py
scp build/web（整体）+ novelmgt-demo.db + deploy/fnos/bin/novel_server.py  →  NAS
# NAS 上：docker build --platform linux/amd64 -t novelmgt-app:10.0.1 .
#         docker save novelmgt-app:10.0.1 -o rootfs_amd64/images/novelmgt-app-10.0.1-amd64.tar
#         ugcli check && ugcli pack --build 3 --arch amd64
```

## 安装与验证

1. UGOS 应用中心 → 手动安装 upk（或 `appcenter` 上传）。
2. 桌面出现「YYX书库」图标，点开即用（`open_type: tab`，端口 12702）。
3. 未放入自有书库时，书架显示内置示例书库（四大名著，约 340 章）。
4. 放入自有书库：

   ```bash
   # 应用数据目录（UGOS 上的 compose 工作目录）下
   mkdir -p db && cp /path/to/your/novelmgt.db db/
   docker restart novelmgt
   ```

## 已知坑

* **镜像格式**：必须 `docker save` 出 docker-archive（含 `manifest.json`）。
  OCI 布局的 tar 在 UGOS 的 docker 20.10 上 `docker load` 会静默失败 →
  表现为「应用中心显示已安装、Docker 里没有容器、应用管理器无日志」。
  `build_upk.sh` 会显式校验。
* **healthcheck**：走 `/api/health`（服务端查询架构才有该端点），
  旧版 compose 里的 `/index.html` 检测无法反映书库是否可读。
* **`{{.TZ}}`**：`docker-compose.yaml` 里的时区占位符由 ugcli 打包时替换，
  手工 `docker compose up` 调试时需自行替换。
