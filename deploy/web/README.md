# 路线 A：Flutter Web 静态部署（UGOS Pro / DXP4800）

静态站点部署，无需任何后端。注意：此模式下数据存放在**各浏览器本地**（IndexedDB），
不同设备互不相通；单文件导入受 30MB 上限限制。共享书库请等路线 B（feat/remote-library 分支）。

## 本机构建

```bash
flutter build web --release
docker build -t novelmgt-web:latest -f deploy/web/Dockerfile .
docker save novelmgt-web:latest -o novelmgt-web.tar.gz && gzip novelmgt-web.tar
```

## UGOS Pro 部署（二选一）

### 方式 1：Docker UI 导入镜像（推荐）

1. UGOS Pro → Docker → 镜像 → 从文件导入 `novelmgt-web.tar.gz`；
2. Docker → 项目/Compose → 新建，粘贴 `deploy/web/compose.yaml`（去掉 image 的 build 注释行按需调整）；
3. 启动后访问 `http://NAS_IP:8765`。

### 方式 2：SSH + compose（已开启 SSH 时）

```bash
ssh user@NAS_IP
cd /volume1/docker/novelmgt   # 上传 compose.yaml 与镜像 tar 到此类目录
docker load < novelmgt-web.tar
docker compose -f compose.yaml up -d
```

## 更新版本

本机重新 `flutter build web` → 重建镜像 → `docker save` → NAS 上 `docker load` 后重启容器。
`index.html` 不缓存，其余资源带版本哈希，刷新即生效。

## 远程访问安全

不要把 8765 端口直接暴露公网。外网访问走 UGREENlink（UGOS 自带远程）或 Tailscale 等隧道。
