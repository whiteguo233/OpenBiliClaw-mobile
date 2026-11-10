# iOS App Store 1.0.2（2026-11-08）

## 范围与来源

本次将已经合入移动端主线的扫码与连接改进提交到 App Store，沿用应用 OpenBiliClaw、Bundle ID `com.openbiliclaw.mobile`、App ID `6812025289` 和团队 `JX4KDJUY28`。基线为 `0b40c5b`；主工作区既有的未提交修改保持原状，不混入发布分支。

Apple 当前可分发版本在 2026-11-08 实际核实为 **1.0.1（2012）**，其更新仅为简体中文语言标识修复。GitHub 的 **v0.3.160** 已发布，不能将未签名 IPA 或 Android 发布当作 iOS 上传或提审完成。

签名前核实 TestFlight 的最新构建为 1.0.1（2012）。本次上传 **1.0.2（2013）**，归档通过 Flutter `--build-name 1.0.2 --build-number 2013` 指定。GitHub 的 `pubspec.yaml` 版本和既有发布标签不因此重写。

功能范围包括后端 URL 输入框内的扫码图标、相机识码、系统选图识别二维码截图、合法地址校验、保存与重连、端口和反代路径保留，以及轻量连接检测和相机生命周期修复。安装包中的隐私与帮助说明同步补充选图数据流和实际入口位置。

## 验证与 Apple 状态

build 2013 **已签名并上传 Apple**，已加入审核草稿。

- `flutter pub get --enforce-lockfile` 成功，依赖锁文件未变。
- `flutter analyze --no-pub` 无问题；格式检查 115 个文件、0 改动；完整 `flutter test --no-pub` **196 项通过**；`git diff --check` 通过。
- 候选源码固定为 `8cf9088`。`flutter build ipa --release --no-pub --no-codesign --build-name 1.0.2 --build-number 2013` 在 336.94 秒内生成归档，Flutter 应用配置校验通过。包内核实为 `com.openbiliclaw.mobile`、1.0.2（2013）、最低 iOS 15.0、`zh-Hans`、iPhoneOS，并包含相机与相册用途说明。
- [PR CI](https://github.com/whiteguo233/OpenBiliClaw-mobile/actions/runs/42408786633) 的分析与测试、Android Release APK、iOS 无签名构建全部通过。
- 新建独立 iPhone 17 Pro Max / iOS 26.5 模拟器，运行既有 `backend_qr_ui_test.dart`，实际通过生产主页 → 连接设置 → URL 内扫码 / 粘贴图标 → 取消粘贴 → 扫码页右下角「选择图片」可见 → 返回。driver 退出 0，含编译约 196.2 秒，App 内测试约 20 秒。保存并逐张检查 3 张 1320×2868 原始截图；它们是同源码 Debug 模拟器的导航验证，不是分发签名包的真机识码验证。
- 原审核后端真实 GET `/api/ping`、`/api/recommendations`、`/api/profile-summary` 和 `/api/saved/favorite` 均返回 200；这些为本机实际请求，不能证明 Apple 远端或新设备首次入网成功。
- 公开隐私与支持页已在 `gh-pages` 的 `5e0271e` 同步，说明扫码相机和系统选图的本地数据处理；[Pages 部署](https://github.com/whiteguo233/OpenBiliClaw-mobile/actions/runs/42408719010) 成功，两个公开 URL 实际 GET 200，旧的“不请求相机权限”声明已移除。

既有完整扫码验收范围见 [扫码连接](../backend-connection-qr.md#完整扫码复测入口2026-11-05)；iOS 模拟器不支持图片分析，本轮未将 UI 导航记为截图解码、真机光学扫描或跨公网验收。

## 2026-11-10 分发签名与上传

早先的自动导出因 `No Accounts` 和分发描述文件证书不匹配失败。2026-11-10 为同一个 iOS App ID 生成了与现有 Apple Distribution 身份匹配的 App Store 分发描述文件。Xcode 手动指定该描述文件后导出成功。对实际 IPA 解包检查了版本、相机与相册用途说明、ARM64、嵌套签名及分发权限。

Apple 官方命令行验证成功，App Store Connect 记录上传时间为 2026-11-10 22:27:47（北京时间）。上传包为 44,718,957 字节，SHA-256 为 `6dc927631d9fc6ad2c57f64c1fbab94b05761e0710ba5dc83963a9244b23cc0f`，交付 ID 为 `77f91e7b-70b7-4d68-859a-f21908302b67`。Apple 返回 `VALID_BINARY` 和 `APP_STORE_ELIGIBLE`。

App Store Connect 已保存扫码更新说明和 build 2013。构建按包内 TLS 与 WireGuard 标准算法填写出口合规问卷，现有 iOS 发行设置中法国为「未供应」。Apple 清除出口合规缺项后，版本通过「添加以供审核」检查，状态为「可供审核」。原审核后端的连接密钥已过期，需更新限于该审核后端的连接并验证首次入网，才能最终提交。

本机未签名归档保存在 `~/Library/Developer/Xcode/Archives/2026-11-08/OpenBiliClaw-iOS-1.0.2-2013-Unsigned.xcarchive`。本轮日志、元数据、TestFlight 核对、UI 截图及校验清单保存在同目录的 `OpenBiliClaw-iOS-1.0.2-evidence/`；这些材料不提交到公共仓库。证书、描述文件、审核凭据和签名输出均保存在仓库外。

## 中文更新说明

新增扫码连接后端：在连接设置的后端 URL 旁点击扫码图标，扫描电脑 Web 或插件的连接二维码，自动保存地址并重连。

扫码页支持从系统相册选择二维码截图，图片仅在设备本地识别，相机不可用时也可使用。

支持局域网、Tailscale 和公网连接地址，保留端口和反向代理路径，并改进连接检测与相机切后台后的恢复。
