# YYX书库 · 通用 Docker 版

服务端查询架构的通用容器发行版（与 UGOS upk / fnOS fpk 同源同代码）：
任意有 Docker 的机器（NAS / 服务器 / 桌面）`docker run` 即可使用。

## 快速开始

```bash
git clone https://github.com/firewelly/yyx-library && cd yyx-library
deploy/docker/build.sh          # 构建 yyx-library:10.0.3
cd deploy/docker && docker compose up -d
# 浏览器打开 http://<host>:12702/
```

或使用 GitHub Release 附带的离线镜像包（无需 git/构建）：

```bash
docker load -i yyx-library-10.0.3-docker-amd64.tar.gz   # → yyx-library:10.0.3
cd deploy/docker && docker compose up -d
```

## 数据

| 容器路径 | 说明 |
|---|---|
| `/data/novelmgt.db` | 书库 SQLite（放入已有 novelmgt.db 即切换为个人书库；缺省时自动用内置示例书库兜底） |
| `/data/novelmgt_state.db` | 阅读进度/书签/笔记（状态库，服务端自动创建） |

两个文件都在 `docker-compose.yml` 挂载的 `./data` 目录里，**容器升级/重建数据不丢**。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PORT` | `12702` | Web/API 监听端口 |
| `DB` | `/data/novelmgt.db` | 书库路径 |
| `STATE_DB` | `/data/novelmgt_state.db` | 状态库路径 |

## 多设备共用

手机/平板/电脑浏览器打开同一地址（`http://<NAS>:12702`）即共用同一书库；
阅读进度、书签与笔记保存在 NAS 状态库中，多设备自动同步。

## Singularity / Apptainer

HPC/科研环境请使用 [`deploy/singularity/`](../singularity/) 的 Apptainer 版本。
