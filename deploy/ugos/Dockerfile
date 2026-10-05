# YYX书库 · UGOS Pro 应用镜像（服务端查询架构）
#
# 镜像内容：
#   ui/   Flutter Web 构建产物（由 `flutter build web --release` 生成）
#   bin/  novel_server.py —— 书库 API 与静态资源服务（Python 标准库）
#   demo/ 示例书库（四大名著，公版）——用户尚未放入自有书库时兜底
#
# 书库与阅读状态由 docker-compose 挂载：
#   ./db    用户书库目录（放置 novelmgt.db；只读挂载）
#   ./state 阅读进度/书签/笔记（可写）
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1
WORKDIR /app

COPY ui /app/ui
COPY bin /app/bin
COPY demo /app/demo

EXPOSE 12702

CMD ["python3", "/app/bin/novel_server.py", \
     "--web-dir=/app/ui", \
     "--db=/app/db/novelmgt.db", \
     "--state-db=/app/state/novelmgt_state.db", \
     "--demo-db=/app/demo/novelmgt-demo.db", \
     "--port=12702"]
