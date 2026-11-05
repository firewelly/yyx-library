# YYX书库 · Apptainer / Singularity 版

面向 HPC / 科研集群环境的单文件发行版（SIF），与服务端查询架构 Docker/upk/fpk 同源同代码。

## 构建

```bash
git clone https://github.com/firewelly/yyx-library && cd yyx-library
deploy/docker/build.sh                    # 先生成 deploy/docker/rootfs/{ui,bin,demo}
sudo apptainer build yyx-library.sif deploy/singularity/yyx-library.def
```

离线 / docker hub 受限环境（先在有 docker 的机器上构建好镜像）：

```bash
docker build -t yyx-library:10.0.3 -f deploy/docker/Dockerfile .   # 任意可联网机器
docker save yyx-library:10.0.3 | gzip > yyx-image.tar.gz           # 拷到目标机
docker load -i yyx-image.tar.gz
apptainer build yyx-library.sif docker-daemon://yyx-library:10.0.3
```

## 运行

```bash
mkdir -p ~/yyx-data
# 可选：把已有 novelmgt.db 拷入 ~/yyx-data/（缺省时内置示例书库兜底）
apptainer run --bind ~/yyx-data:/data yyx-library.sif
# 浏览器打开 http://<host>:12702/
```

自定义端口 / 路径：

```bash
PORT=8080 DB=/data/my.db STATE_DB=/data/my_state.db \
  apptainer run --bind ~/yyx-data:/data yyx-library.sif
```

## 数据

| 路径（bind 挂载） | 说明 |
|---|---|
| `~/yyx-data/novelmgt.db` | 书库 SQLite |
| `~/yyx-data/novelmgt_state.db` | 进度/书签/笔记状态库（自动创建） |

SIF 是只读单文件，所有可写数据都在 bind 挂载的宿主目录里。
