#!/bin/sh
# YYX书库 · 容器入口：WEB_PIN 迁出后再 exec 服务端。
#
# 为什么不能只靠 novel_server.py 里的 del os.environ：Python 的 unsetenv 改的是
# 进程当前环境副本，/proc/1/environ 显示的是内核记录的启动初始块，用户态清不掉。
# 在 shell 里 unset 后 exec，内核以新环境重写初始块 → /proc/1/environ 无明文。
# （与 nasoc/nasdsh 的 entrypoint unset+setpriv 模式同源。）
if [ -n "${WEB_PIN:-}" ]; then
  umask 077
  printf '%s' "$WEB_PIN" > /app/pin.conf
  unset WEB_PIN
  echo "[novelmgt] WEB_PIN 已落盘 pin.conf(0600) 并迁出进程环境"
fi
exec "$@"
