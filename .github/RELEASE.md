# 双端 Release 发版指南

仓库包含两条 GitHub Actions 工作流：

- `Mobile CI`：在 `main` 和 Pull Request 上执行格式检查、静态分析、测试、Android Release 构建和 iOS 无签名构建。
- `Release Android and iOS`：由 `vX.Y.Z` 标签或手动触发，生成签名 APK/AAB、未签名 IPA、符号文件、SHA-256 校验和及构建来源证明。

## 1. 版本规则

`pubspec.yaml` 必须使用 `X.Y.Z+BUILD` 格式，例如：

```yaml
version: 0.4.0+2
```

Release 标签必须与版本名一致，例如 `v0.4.0`。每次发版同时递增 `BUILD`，避免 Android/iOS 商店拒绝重复构建号。

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

用户下载 unsigned IPA 后，需要用自己的 Apple ID、开发证书和 provisioning profile，通过可信的本地重签工具完成签名。签名工具可能需要把默认 Bundle ID `com.openbiliclaw.openbiliclawApp` 改成用户账号下唯一的 Bundle ID。

自签名后的有效期、可安装设备和能力权限由用户自己的 Apple 账号与 provisioning profile 决定。不要把 Apple ID 密码或证书上传到本仓库。

面向下载用户的简版操作说明见 [`IOS_SELF_SIGNING.md`](IOS_SELF_SIGNING.md)，该文件也会随 iOS Release 产物一起上传。

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
