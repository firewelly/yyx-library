# YYX书库 - 远程书库 API + 静态 Web 一体容器
# 挂载：
#   /data/novelmgt.db  共享书库数据库（只读使用）
#   /data              books 共享文件夹（预留）
#   /srv/web           Flutter Web 静态资源（由部署脚本上传）
# 端口：8080（容器内），映射到宿主 8765
FROM dart:3.9.4 AS build
WORKDIR /app
COPY deploy/api/pubspec.* ./
RUN dart pub get
COPY deploy/api/ .
RUN dart compile exe bin/server.dart -o /app/server

FROM debian:bookworm-slim
# libsqlite3-0 提供运行库，libsqlite3-dev 提供 .so 符号链接（dart sqlite3 包按无版本名加载）
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-0 libsqlite3-dev ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/server /app/server
EXPOSE 8080
ENTRYPOINT ["/app/server"]
