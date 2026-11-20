# YYX书库 · UGOS Pro 应用镜像（服务端查询架构）
#
# 镜像内容：
#   ui/   Flutter Web 构建产物（由 `flutter build web --release` 生成）
#   bin/  novel_server.py —— 书库 API 与静态资源服务（Python 标准库）
#   demo/ 示例书库（四大名著，公版）——用户尚未放入自有书库时兜底
#
# 书库与阅读状态由 docker-compose 挂载：
#   ./db    用户书库目录（放置 novelmgt.db；Web 导入需服务端写库，故为读写挂载）
#   ./state 阅读进度/书签/笔记（可写）
FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1
WORKDIR /app

COPY ui /app/ui
COPY bin /app/bin
COPY demo /app/demo
COPY PRIVACY.md /app/PRIVACY.md
COPY entrypoint.sh /entrypoint.sh
RUN chmod 0755 /entrypoint.sh
# 防预置凭据（10.0.6.0001 事故）：增量构建（FROM 旧镜像）会继承运行时残留的
# pin.conf 与 config Env WEB_PIN——构建期强制清空/删除
ENV WEB_PIN=
RUN rm -f /app/pin.conf

EXPOSE 12702

ENTRYPOINT ["/entrypoint.sh"]

CMD ["python3", "/app/bin/novel_server.py", \
     "--web-dir=/app/ui", \
     "--db=/app/db/novelmgt.db", \
     "--state-db=/app/state/novelmgt_state.db", \
     "--demo-db=/app/demo/novelmgt-demo.db", \
     "--port=12702", \
     "--pin-file=/app/pin.conf", \
     "--privacy-file=/app/PRIVACY.md"]
