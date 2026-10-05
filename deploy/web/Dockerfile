# YYX书库 - Flutter Web 静态部署镜像
# 构建产物 build/web 由构建脚本/CI 生成后拷入，无需在容器内装 Flutter。
#
# 本机构建镜像：
#   flutter build web --release
#   docker build -t novelmgt-web:latest -f deploy/web/Dockerfile .
#
# UGOS Pro 上加载：导入镜像 tar（docker save 产物）或直接用 compose 项目构建。
FROM nginx:1.27-alpine

COPY deploy/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY build/web /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=60s --timeout=5s CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
