# OpenBiliClaw — Flutter 移动客户端（全量版）

OpenBiliClaw 的 Flutter 移动客户端（B 站第三方客户端），连接自建的
[OpenBiliClaw](https://github.com/whiteguo233/OpenBiliClaw) 后端服务（提供 B 站数据 + AI 能力）。

## 使用逻辑

App 采用「客户端 + 后端」架构，使用流程：

1. **配置后端连接**：右上角 ⚙️ 进入连接设置，填后端 IP/端口
   （Web/iOS/macOS 默认 `127.0.0.1:8420`；Android 模拟器默认
   `10.0.2.2:8420`，真机填电脑局域网 IP；远程部署填服务器 IP，后端开启密码门禁）。
   保存后会立即按新地址重连，可点「测试连接」验证。
2. **推荐页**：从后端拉取「为你推荐」视频流，支持下拉刷新；
   离线时提示「无法连接后端」。
3. **对话页**：与 AI 对话，告诉它你喜欢的 UP 主/内容类型，AI 据此调整推荐。
4. **画像页**：展示 AI 建立的用户兴趣画像；用得越多、画像越准、推荐越精准
   （初期提示「画像还在慢慢攒，先多看一阵」）。
5. **收藏页**：管理「稍后再看」和「我的收藏」。

> 一句话：连上后端 → 浏览积累数据 → AI 建立画像 → 对话微调偏好 → 获得越来越精准的推荐。

## 特性

- 推荐 / 稍后再看 / 收藏浏览 + AI 对话 / 用户画像
- 🖼️ **封面图 B 站 CDN 直连**（原生端跳过服务端代理，省两跳；web 端因 CORS 限制仍走代理）
- 封面图 / 已保存视图请求头会话管理优化
- API 返回数据处理调整
- 支持 Android / iOS / Web / Linux / macOS / Windows
- GitHub Actions 双端 CI 与 Release：签名 APK/AAB、供用户自签名的 unsigned IPA、符号文件、校验和和构建来源证明

## 构建与发版

- Pull Request 和 `main` 会自动执行格式检查、静态分析、测试及 Android/iOS 构建验证。
- 推送与 `pubspec.yaml` 版本一致的 `vX.Y.Z` 标签，会并行构建 Android 和 iOS 正式产物并创建 GitHub Release。
- Android 正式产物由项目 release keystore 签名；iOS 发布未签名 IPA，由用户使用自己的 Apple 账号和证书重签，仓库不保存 Apple 凭据。

完整配置和发版步骤见 [双端 Release 发版指南](.github/RELEASE.md)。

## 版本状态

🧪 **新特性版（未经长期实测）**：在此前网络优化前版之上新增 B 站封面直连等改动，
作者尚未长期实测。建议合并前重点验证弱网 / 防盗链场景下的图片加载表现。

## 环境与后端配置

- Flutter 3.x
- 自建 OpenBiliClaw 后端
- Web/iOS/macOS 默认连接 `127.0.0.1:8420`；Android 模拟器默认连接
  `10.0.2.2:8420`，Android 真机或远程部署在设置页填服务器局域网 IP。

## License

[MIT](LICENSE)
