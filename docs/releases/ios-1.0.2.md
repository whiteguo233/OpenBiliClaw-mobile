# iOS App Store 1.0.2（2026-11-08）

## 范围与来源

本次将已经合入移动端主线的扫码与连接改进提交到 App Store，沿用应用 OpenBiliClaw、Bundle ID `com.openbiliclaw.mobile`、App ID `6812025289` 和团队 `JX4KDJUY28`。基线为 `0b40c5b`；主工作区既有的未提交修改保持原状，不混入发布分支。

Apple 当前可分发版本在 2026-11-08 实际核实为 **1.0.1（2012）**，其更新仅为简体中文语言标识修复。GitHub 的 **v0.3.160** 已发布，不能将未签名 IPA 或 Android 发布当作 iOS 上传或提审完成。

本轮实际读取 TestFlight，仅列出 1.0.1（2012）及更旧的 1.0.0；新候选为 **1.0.2（2013）**，通过 Flutter `--build-name 1.0.2 --build-number 2013` 指定。GitHub 的 `pubspec.yaml` 版本和既有发布标签不因此重写。

功能范围包括后端 URL 输入框内的扫码图标、相机识码、系统选图识别二维码截图、合法地址校验、保存与重连、端口和反代路径保留，以及轻量连接检测和相机生命周期修复。安装包中的隐私与帮助说明同步补充选图数据流和实际入口位置。

## 验证与 Apple 状态

当前为**未签名候选归档完成，待分发签名与上传**，尚未提交新版审核。

- `flutter pub get --enforce-lockfile` 成功，依赖锁文件未变。
- `flutter analyze --no-pub` 无问题；格式检查 115 个文件、0 改动；完整 `flutter test --no-pub` **196 项通过**；`git diff --check` 通过。
- 候选源码固定为 `8cf9088`。`flutter build ipa --release --no-pub --no-codesign --build-name 1.0.2 --build-number 2013` 在 336.94 秒内生成归档，Flutter 应用配置校验通过。包内核实为 `com.openbiliclaw.mobile`、1.0.2（2013）、最低 iOS 15.0、`zh-Hans`、iPhoneOS，并包含相机与相册用途说明。
- [PR CI](https://github.com/whiteguo233/OpenBiliClaw-mobile/actions/runs/42408786633) 的分析与测试、Android Release APK、iOS 无签名构建全部通过。
- 新建独立 iPhone 17 Pro Max / iOS 26.5 模拟器，运行既有 `backend_qr_ui_test.dart`，实际通过生产主页 → 连接设置 → URL 内扫码 / 粘贴图标 → 取消粘贴 → 扫码页右下角「选择图片」可见 → 返回。driver 退出 0，含编译约 196.2 秒，App 内测试约 20 秒。保存并逐张检查 3 张 1320×2868 原始截图；它们是同源码 Debug 模拟器的导航验证，不是分发签名包的真机识码验证。
- 原审核后端真实 GET `/api/ping`、`/api/recommendations`、`/api/profile-summary` 和 `/api/saved/favorite` 均返回 200；这些为本机实际请求，不能证明 Apple 远端或新设备首次入网成功。
- 公开隐私与支持页已在 `gh-pages` 的 `5e0271e` 同步，说明扫码相机和系统选图的本地数据处理；[Pages 部署](https://github.com/whiteguo233/OpenBiliClaw-mobile/actions/runs/42408719010) 成功，两个公开 URL 实际 GET 200，旧的“不请求相机权限”声明已移除。

既有完整扫码验收范围见 [扫码连接](../backend-connection-qr.md#完整扫码复测入口2026-11-05)；iOS 模拟器不支持图片分析，本轮未将 UI 导航记为截图解码、真机光学扫描或跨公网验收。

## 签名与后续操作

本地有有效 Apple Distribution 身份，但它于 2026-11-06 签发，与本机旧 iOS Store 描述文件中的证书不同。Apple Developer 后台另有 `OpenBiliClaw App Store Local Distribution`、ID `AZW8UVWJUR`、2027-09-30 到期的 iOS Store 描述文件；仍需更新并核对其中证书，不能仅凭状态 Active 当作已匹配。

本轮标准 `xcodebuild -exportArchive -allowProvisioningUpdates` 的实际结果为 **退出 70**：`No Accounts`，以及描述文件不包含当前 Apple Distribution 证书。没有生成可上传的正式签名 IPA，不能将未签名归档或 Flutter 退出 0 当作上传成功。

Apple 页面可以间歇读取，已完成版本、TestFlight 与描述文件事实核对；Chrome AppleScript 后续多次返回连接无效，电脑仍锁屏，当前无法可靠完成描述文件更新或操作 Xcode 分发窗口。需解锁会话后继续更新描述文件、签名导出、上传并在 Apple 处理后选择 build 2013、补齐资料及最终提交审核。旧审核备注中的 Tailscale Key 有效期为 2026-10-24，本次不得原样复用；需刷新同一受限审核访问并实测，凭据只写入 Apple 审核信息及本机私有位置。

本机未签名归档保存在 `~/Library/Developer/Xcode/Archives/2026-11-08/OpenBiliClaw-iOS-1.0.2-2013-Unsigned.xcarchive`。本轮日志、元数据、TestFlight 核对、UI 截图及校验清单保存在同目录的 `OpenBiliClaw-iOS-1.0.2-evidence/`；这些材料不提交到公共仓库。证书、描述文件、审核凭据和签名输出均保存在仓库外。

## 中文更新说明

新增扫码连接后端：在连接设置的后端 URL 旁点击扫码图标，扫描电脑 Web 或插件的连接二维码，自动保存地址并重连。

扫码页支持从系统相册选择二维码截图，图片仅在设备本地识别，相机不可用时也可使用。

支持局域网、Tailscale 和公网连接地址，保留端口和反向代理路径，并改进连接检测与相机切后台后的恢复。
