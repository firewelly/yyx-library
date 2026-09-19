# 打包说明

Windows / macOS / Linux 桌面端安装包。**Flutter 桌面端不支持交叉编译**——每个平台的包必须在对应系统上构建。

## Windows（本机可出包）

```powershell
flutter build windows --release
# 产物: build\windows\x64\runner\Release\  （整个目录拷走即可运行）
# 压缩包:
Compress-Archive -Path build\windows\x64\runner\Release\* -DestinationPath dist\novelmgt_flutter-windows-x64.zip
```

如需正式安装器（开始菜单/卸载项），建议用 Inno Setup 或 MSIX：
- MSIX: `flutter pub add msix` + `dart run msix:create`（需要配置 publisher）
- Inno Setup 脚本可后续补充

## macOS（在 Mac 上运行 `tool/package_macos.sh`）

要求：Xcode + Flutter。产物为 zip（含 .app）；脚本末尾附 .dmg 命令。

```bash
bash tool/package_macos.sh
```

注意：默认未签名的 .app 在他人 Mac 上需右键→打开，或 `xattr -cr novelmgt_flutter.app` 去隔离属性。分发需要 Apple Developer 签名/公证。

## Linux（在 Linux 上运行 `tool/package_linux.sh`）

要求：clang/cmake/ninja/pkg-config + Flutter。产物为 tar.gz（自包含 bundle，解压即运行）。

```bash
bash tool/package_linux.sh
```

如需 .deb/.AppImage，建议后续用 `dart run flutter_distributor:package` 或手写 .desktop。

## Web

```bash
flutter build web --release   # build/web/ 整目录静态部署
```

## NAS（fnOS / UGOS Pro，单文件直连版）

架构：浏览器内 SQLite WASM 经 HTTP Range 按需读取 NAS 上的单文件 `novelmgt.db`
（只读），服务端仅静态托管（python3 标准库）+ `/api/state/*` 用户状态 API
（进度/书签/笔记存 NAS 本地状态库，跨浏览器共享；`?nas=1` 模式，
见 `lib/services/nas/` 与 docs/REQUIREMENTS.md 附录 D）。

两条部署路径（同一架构，前端都是 `flutter build web --release`）：

| 目标 | 打包/部署 | 文档 |
|------|-----------|------|
| misc (fnOS) | `python tool/fnos/build_fpk.py` → dist/novelmgt-fnos.fpk，`deploy_misc.py` 一键装 | `tool/fnos/README.md` |
| DXP4800 (UGOS Pro) | `python tool/ugos/deploy_dxp4800.py`（快照+上传+docker compose up 一键） | `tool/ugos/README.md` |

库更新：dx4600/misc 走 `python ../scrapers/upload_novel_db_to_dx4600.py`；
DXP4800 重跑 `tool/ugos/deploy_dxp4800.py --skip-ui`（远端同大小自动跳过）。
注意 UGOS Pro 的 SFTP 残缺（只读），部署脚本走 SSH exec 分块传输。
