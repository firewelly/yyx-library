#!/bin/bash
# fnOS CLI 安装后补桌面注册（2026-10-25 EQ14 实测）
#
# 背景：`appcenter-cli install-fpk` 装出的应用不出 fnOS 桌面图标——
# GUI/正常安装流程会向 postgres 库 appcenter 的 app_service 表写启动注册
# （service_name=manifest 的 desktop_applaunchname、type=url、
#   url=http://${host}:<service_port>/、icon=ui/images/icon_{0}.png），
# CLI 通道不写。fnOS 桌面图标来自 trim_sac 库 entry 表，
# trim_app_center 重启时从 app_service 重建。
#
# 用法（拷到 fnOS 上以 root 执行）：
#   register_after_cli_install.sh <appname>
# 步骤：① 插 app_service 行（缺才插）② 补 ui/images/icon_{64,256}.png
#       ③ systemctl restart trim_app_center（触发 entry 重建）
# 残留：应用中心详情页"打开"按钮（/app-center/v1/app/installed 的
#       appServiceInfo/isOpen）仍为空，重启各守护进程无效；GUI 卸载重装
#       才能彻底修复。不影响桌面图标与直接访问 http://<nas>:<port>/。
set -euo pipefail

APP="${1:?用法: $0 <appname>}"
MF="/var/apps/$APP/manifest"
[ -f "$MF" ] || { echo "manifest 不存在: $MF" >&2; exit 1; }

get() { awk -v k="$1" '$1==k {sub(/^[^=]*=[ ]*/,""); print}' "$MF"; }

PORT=$(get service_port)
LAUNCH=$(get desktop_applaunchname)
[ -n "$PORT" ] || { echo "manifest 缺 service_port" >&2; exit 1; }
[ -n "$LAUNCH" ] || { echo "manifest 缺 desktop_applaunchname" >&2; exit 1; }
TITLE=$(get display_name)
UIDIR=$(get desktop_uidir); UIDIR=${UIDIR:-ui}

echo "== $APP (port=$PORT launch=$LAUNCH) =="

# ① app_service 注册行
if sudo -u postgres psql -At -d appcenter -c \
    "select 1 from app_service where service_name='$LAUNCH'" | grep -q 1; then
  echo "app_service 已有 $LAUNCH，跳过"
else
  APP_ID=$(sudo -u postgres psql -At -d appcenter -c \
    "select id from app where app_name='$APP'")
  sudo -u postgres psql -d appcenter <<SQL
insert into app_service
  (app_id, service_name, title, "desc", icon, type, url, default_url,
   is_admin, control, full_url, no_display, file_types, i18n_matadata,
   gateway_socket, gateway_prefix)
values
  ($APP_ID, '$LAUNCH', '$TITLE', '', '$UIDIR/images/icon_{0}.png', 'url',
   'http://\${host}:$PORT/', 'http://\${host}:$PORT/', true,
   '{"show":0,"showRoute":0,"auth":0,"port":0,"path":0,"fullUrl":0,"accessPerm":"editable","portPerm":"editable","pathPerm":"editable","fullUrlPerm":"editable"}',
   '', false, '[]', '', '', '');
SQL
  echo "app_service 已插入（app_id=$APP_ID）"
fi

# ② 桌面图标文件（Flutter build/web 没有 images/ 目录）
TARGET=$(readlink -f "/var/apps/$APP/target")
mkdir -p "$TARGET/$UIDIR/images"
cp "/var/apps/$APP/ICON_256.PNG" "$TARGET/$UIDIR/images/icon_256.png"
cp "/var/apps/$APP/ICON.PNG" "$TARGET/$UIDIR/images/icon_64.png"
cp "/var/apps/$APP/ICON.PNG" "$TARGET/$UIDIR/images/icon.png"
chmod 644 "$TARGET/$UIDIR/images/"*.png
echo "图标已就位: $TARGET/$UIDIR/images/"

# ③ 重启守护进程，重建 trim_sac.entry
systemctl restart trim_app_center.service
sleep 5
systemctl is-active trim_app_center.service
echo "完成——刷新 fnOS 桌面应出现图标，点击经 window.open 打开 http://<nas>:$PORT/"
