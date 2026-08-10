# 双端 Release 发版指南

仓库包含两条 GitHub Actions 工作流：

- `Mobile CI`：在 `main` 和 Pull Request 上执行格式检查、静态分析、测试、Android Release 构建和 iOS 无签名构建。
- `Release Android and iOS`：由 `vX.Y.Z` 标签或手动触发，生成签名 APK、AAB、IPA、符号文件、SHA-256 校验和及构建来源证明，并发布 GitHub Release。

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

## 3. iOS 签名配置

准备与 `com.openbiliclaw.openbiliclawApp` 匹配的 Apple Distribution `.p12` 证书和 provisioning profile。在 Actions Secrets 中配置：

| 名称 | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | `.p12` 文件的单行 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 文件的单行 Base64 |

在 **Actions → Variables** 中配置：

| 名称 | 内容 |
| --- | --- |
| `IOS_TEAM_ID` | Apple Developer Team ID |
| `IOS_EXPORT_METHOD` | 默认为 `release-testing`；也支持 `app-store-connect` 或 `enterprise` |

```bash
base64 < OpenBiliClaw_Distribution.p12 | tr -d '\n' | gh secret set IOS_CERTIFICATE_P12_BASE64
gh secret set IOS_CERTIFICATE_PASSWORD
base64 < OpenBiliClaw.mobileprovision | tr -d '\n' | gh secret set IOS_PROVISIONING_PROFILE_BASE64
gh variable set IOS_TEAM_ID --body 'YOUR_TEAM_ID'
gh variable set IOS_EXPORT_METHOD --body 'release-testing'
```

`release-testing` 生成的 IPA 只能安装到 provisioning profile 已登记的设备；公开分发通常应通过 TestFlight/App Store。`app-store-connect` 产物适合后续上传 App Store Connect，并不能作为任意设备可直接安装的 IPA。

## 4. 发版

推荐通过标签发版：

```bash
git switch main
git pull --ff-only
git tag -a v0.4.0 -m "OpenBiliClaw v0.4.0"
git push origin v0.4.0
```

也可在 **Actions → Release Android and iOS → Run workflow** 从 `main` 手动运行。手动输入的标签仍必须与 `pubspec.yaml` 一致。

Release 只有在质量检查、Android 签名构建和 iOS 签名构建全部成功后才会创建。若在仓库的 `github-release` Environment 中配置 required reviewers，还可以增加发布前人工审批。

## 5. 产物

- Android：ARMv7 APK、ARM64 APK、AAB、Dart 混淆符号。
- iOS：签名 IPA、dSYM、Dart 混淆符号。
- 通用：`SHA256SUMS.txt` 和 GitHub artifact attestation。

证书、密码、keystore、provisioning profile 和临时签名配置均不会写入仓库或 Release 产物。
