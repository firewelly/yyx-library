# YYX书库 · 通用 Docker 版（服务端查询架构）
#
# 与 UGOS upk 内置镜像同源：ui/ = Flutter Web 构建产物，bin/ = novel_server.py，
# demo/ = 示例书库（可选，用户未放置自有书库时兜底）。
#
# 构建（仓库根目录，需先 flutter build web --release，或使用 deploy/docker/build.sh）：
#   docker build -t yyx-library:10.0.3 -f deploy/docker/Dockerfile .
#
# 运行：
#   docker run -d --name yyx-library \
#     -p 12702:12702 \
#     -v $(pwd)/data:/data \
#     yyx-library:10.0.3
#   浏览器打开 http://<host>:12702/
#
# 数据说明：
#   /data/novelmgt.db        书库（把已有 novelmgt.db 放进挂载目录即可替换示例库）
#   /data/novelmgt_state.db  阅读进度/书签/笔记（状态库）
#   两者都在挂载卷内，容器升级/重建数据不丢。

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PORT=12702 \
    DB=/data/novelmgt.db \
    STATE_DB=/data/novelmgt_state.db

WORKDIR /app

COPY deploy/docker/rootfs/ui  /app/ui
COPY deploy/docker/rootfs/bin /app/bin
COPY deploy/docker/rootfs/demo /app/demo

EXPOSE 12702
VOLUME ["/data"]

CMD ["sh", "-c", "exec python3 /app/bin/novel_server.py \
     --web-dir=/app/ui \
     --db=${DB} \
     --state-db=${STATE_DB} \
     --demo-db=/app/demo/novelmgt-demo.db \
     --port=${PORT}"]
