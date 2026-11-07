# 双端 Release 发版指南

仓库包含两条 GitHub Actions 工作流：

- `Mobile CI`：在 `main` 和 Pull Request 上执行格式检查、静态分析、测试、Android Release 构建和 iOS 无签名构建。
- `Release Android and iOS`：由 `vX.Y.Z` 标签或手动触发，生成签名 APK/AAB、未签名 IPA、符号文件、SHA-256 校验和及构建来源证明。

## 1. 版本规则

`pubspec.yaml` 必须使用 `X.Y.Z+BUILD` 格式，例如：

```yaml
version: 0.4.0+2
```

Release 标签必须与版本名一致，例如 `v0.4.0`。Android 的基础 versionCode 来自 `BUILD`；Flutter 的 split-per-ABI APK 会额外加上 ABI 偏移（例如本次 ARM64 APK 为 `2010 + 2000 = 4010`），AAB 使用基础值。安装器用实际 versionCode 判断能否覆盖安装，因此 **每次发版的 `BUILD` 必须严格大于上一个已发布版本的 `BUILD`**，不能只递增 `X.Y.Z` 而把构建号回退。CI 会校验当前 `BUILD` 是否比最近一个 `vX.Y.Z` 标签里的构建号更大，发现回退会直接拒绝发版。

推荐使用连续递增大整数作为构建号，并在每次发版时同时提升 `X.Y.Z`，例如：

```yaml
# 上一个已发布版本：0.3.153+2003
version: 0.3.154+2004
```

## 2. Android 签名配置

在仓库的 **Settings → Secrets and variables → Actions → Secrets** 中配置：

| 名称 | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | JKS/keystore 文件的单行 Base64 |
| `ANDROID_KEY_ALIAS` | Key alias |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_STORE_PASSWORD` | Keystore password |

生成 Base64 并直接写入 GitHub Secret：

```bash
base64 < openbiliclaw-release.jks | tr -d '\n' | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
gh secret set ANDROID_STORE_PASSWORD
```

正式 Release 会强制要求上述配置，不允许退回 debug 签名。本地开发仍可通过 `android/key.properties` 使用传统签名配置。

本仓库的正式 keystore 由维护者离线保管，GitHub 只保存加密 Secret。keystore 一旦丢失，后续 APK 将无法以原签名覆盖安装，必须同时做好离线备份。

## 3. iOS 用户自签名

仓库不保存 Apple 证书，也不要求配置任何 iOS Secret。GitHub Actions 会构建：

- `OpenBiliClaw-iOS-unsigned-vX.Y.Z.ipa`：未签名 IPA，不能直接安装。
- `OpenBiliClaw-iOS-dSYM-vX.Y.Z.zip`：原生崩溃符号。
- `OpenBiliClaw-iOS-Flutter-symbols-vX.Y.Z.zip`：Dart 混淆符号。

用户下载 unsigned IPA 后，需要用自己的 Apple ID、开发证书和 provisioning profile，通过可信的本地重签工具完成签名。签名工具可能需要把默认 Bundle ID `com.openbiliclaw.mobile` 改成用户账号下唯一的 Bundle ID。

自签名后的有效期、可安装设备和能力权限由用户自己的 Apple 账号与 provisioning profile 决定。不要把 Apple ID 密码或证书上传到本仓库。

面向下载用户的简版操作说明见 [`IOS_SELF_SIGNING.md`](IOS_SELF_SIGNING.md)，该文件也会随 iOS Release 产物一起上传。

## App Store 分发标识与版本

OpenBiliClaw 的正式 Bundle ID 为 `com.openbiliclaw.mobile`，App Store Connect App ID 为 `6812025289`。Runner 各构建配置及 `lib/services/tailnet_service_native.dart` 的 iOS `appId` 必须一致；不要使用另一个应用 Bilibili Next 的标识。

GitHub Release 的未签名 IPA 面向自行签名用户。提交 App Store 必须另外使用对应团队的分发签名归档、上传，并在 App Store Connect 选中构建和提交审核。GitHub 发布成功不代表 Apple 上传或送审成功。Apple 的营销版本可按当前商店记录通过 `--build-name` 指定，但构建号必须保持递增；正式归档前核实商店当前版本、最新构建号与审核状态。

本次版本为 `0.3.160+2010`，执行状态与验证范围见 [发布记录](../docs/releases/v0.3.160.md)。证书、账户凭据、审核后端凭据和签名输出应保存在仓库外。

App Store 1.0.2 的独立分发执行与实际构建号见 [iOS 发布记录](../docs/releases/ios-1.0.2.md)。正式归档通过 `--build-name 1.0.2` 和核实后的递增 `--build-number` 指定 Apple 版本；不得使用低于现有商店 2012 的旧候选归档构建号。

## 4. 发版

推荐通过标签发版：

```bash
git switch main
git pull --ff-only
git tag -a v0.4.0 -m "OpenBiliClaw v0.4.0"
git push origin v0.4.0
```

也可在 **Actions → Release Android and iOS → Run workflow** 从 `main` 手动运行。手动输入的标签仍必须与 `pubspec.yaml` 一致：

- `publish_release=false`（默认）：只验证双端正式构建，产物保留在 Actions Artifacts，不创建标签或 Release。
- `publish_release=true`：构建成功后创建 GitHub Release。

Release 只有在质量检查、Android 签名构建和 iOS 未签名构建全部成功后才会创建。若在仓库的 `github-release` Environment 中配置 required reviewers，还可以增加发布前人工审批。

## 5. 产物

- Android：ARMv7 APK、ARM64 APK、AAB、Dart 混淆符号。
- iOS：供用户自签名的 unsigned IPA、dSYM、Dart 混淆符号。
- 通用：`SHA256SUMS.txt` 和 GitHub artifact attestation。

证书、密码、keystore 和 provisioning profile 均不会写入仓库或 Release 产物。
