# OpenBiliClaw — Flutter 移动客户端（全量版）

OpenBiliClaw 的 Flutter 移动客户端（多平台内容推荐与认知客户端），连接自建的
[OpenBiliClaw](https://github.com/whiteguo233/OpenBiliClaw) 后端服务（提供 B 站数据 + AI 能力）。

## 使用逻辑

App 采用「客户端 + 后端」架构，使用流程：

1. **配置后端连接**：右上角 ⚙️ 进入连接设置，选择直接连接或内置 Tailscale，再填后端 IP/端口
   （Web/iOS/macOS 默认 `127.0.0.1:8420`；Android 模拟器默认
   `10.0.2.2:8420`，真机填电脑局域网 IP；远程部署填服务器 IP，后端开启密码门禁）。
   保存后会立即按新地址重连，可点「测试连接」验证。
2. **推荐页**：从后端拉取「为你推荐」视频流，支持下拉刷新；
   离线时提示「无法连接后端」。
3. **对话页**：与 AI 对话，告诉它你喜欢的 UP 主/内容类型，AI 据此调整推荐。
4. **画像页**：展示 AI 建立的用户兴趣画像；用得越多、画像越准、推荐越精准
   （初期提示「画像还在慢慢攒，先多看一阵」）。
5. **收藏页**：管理「稍后再看」和「我的收藏」（可反馈、可交叉切换），以及近 30 天的内容历史（点开过 / 出现过没点开 / 最近移除，可恢复）。
6. **消息收件箱**：点顶部铃铛，处理兴趣探测、避雷探针、认知更新和待聊确认。

> 一句话：连上后端 → 浏览积累数据 → AI 建立画像 → 对话微调偏好 → 获得越来越精准的推荐。

## 特性

- 推荐 / 稍后再看 / 收藏 / 近 30 天内容历史 + AI 对话 / 用户画像
- 内容库三 tab：稍后再看、我的收藏、**历史记录**（主动点开过 / 出现过没点开 / 最近移除，支持分页与「重新收藏 / 重新加入稍后」恢复，对齐插件端与 Web 端）
- 已保存卡片支持「喜欢 / 不感兴趣 / 聊一聊」反馈与**收藏 ↔ 稍后再看交叉切换**（对齐 Web/插件）
- 统一**消息收件箱**（铃铛）：兴趣探测、避雷探针（含「多聊聊」）、认知更新通知、待聊确认（对齐移动 Web）
- 设置页含「保存时自动同步到对应平台」开关（对齐移动 Web 的保存与同步设置）
- Delight 惊喜推荐：动作区对齐 Web/插件（看看 / 喜欢 / 稍后再看 / 收藏 / 不感兴趣 / 聊一聊）
- 🖼️ **封面图统一代理与缓存**（Web/iOS/Android 均通过后端加载，规避 CORS、移动网络防盗链及 DNS/TLS 差异）
- 封面图 / 已保存视图请求头会话管理优化
- API 返回数据处理调整
- 推荐页、画像页、历史记录支持「回到顶部」悬浮按钮
- Android 使用 Material 3 导航，iOS 使用 Cupertino Tab Bar；支持跟随系统的浅色/深色主题、Dynamic Type/大字体、横屏与安全区
- Bilibili 卡片点击后默认进入 App 内原生播放器（基于 media_kit 移植自 PiliPlus 的思路）；登录态/取流走后端 `/api/bilibili/player/play-url` 协议，后端未就绪时可一键回退内置 WebView
- 原生播放器支持弹幕、字幕、倍速、画质/分 P 切换、记忆播放、双击快进/快退、滑动调音量；WebView 登录后可一键同步 Cookie 到后端
- 原生播放页支持点赞、投币、收藏、稍后再看、三连、原生评论列表和相关视频推荐
- B 站登录态与原生播放器取流协议见 [docs/bilibili-login-and-player-protocol.md](docs/bilibili-login-and-player-protocol.md)
- 支持 Bilibili、抖音、小红书、YouTube、X、知乎、Reddit、微博、Linux.do、V2EX 等来源识别；非 Bilibili 内容优先唤起已安装的原生 App，失败时回落到规范化网页地址
- 支持 Android / iOS / Web / Linux / macOS / Windows
- Android / iOS 可使用内置 Tailscale，仅让本 App 的后端请求进入 tailnet，无需开放公网端口或安装系统级 VPN
- GitHub Actions 双端 CI 与 Release：签名 APK/AAB、供用户自签名的 unsigned IPA、符号文件、校验和和构建来源证明

## 构建与发版

内置 Tailscale 原生资产需要 Go 1.26.5+（`GOTOOLCHAIN=auto`）以及对应平台工具链；
Android 最低版本为 API 31，iOS 最低版本为 15.0。Android ARM、ARM64 与 x86/x64
均支持内置 Tailscale。CI 已配置 Go 工具链。

- Pull Request 和 `main` 会自动执行格式检查、静态分析、测试及 Android/iOS 构建验证。
- 推送与 `pubspec.yaml` 版本一致的 `vX.Y.Z` 标签，会并行构建 Android 和 iOS 正式产物并创建 GitHub Release。
- Android 正式产物由项目 release keystore 签名；iOS 发布未签名 IPA，由用户使用自己的 Apple 账号和证书重签，仓库不保存 Apple 凭据。

完整配置和发版步骤见 [双端 Release 发版指南](.github/RELEASE.md)。

## 测试

```bash
flutter test                                   # 单元/模型测试（无需后端）
flutter test test_e2e/                         # API + LLM 端到端：需后端 8420 且 LLM 已配置
flutter test integration_test/app_e2e_test.dart -d <device-id>   # 真实 App 端到端（含 AI 对话）
```

- `test/`：纯单元/模型测试，默认 `flutter test` 执行，无需后端。
- `test_e2e/e2e_backend_test.dart`：真实请求后端验证内容历史、保存反馈事件、收藏交叉切换、自动同步配置、健康与 embedding 就绪。
- `test_e2e/e2e_llm_test.dart`：验证 LLM 驱动的画像素描、惊喜推荐理由、AI 对话回复、待聊确认、活动流汇总。
- `integration_test/app_e2e_test.dart`：在 Android/iOS 设备或模拟器上真实启动 App，断言四个 tab 加载真实数据、画像页展示 LLM 人格素描、对话发送后收到商汤真实回复。

## 验证状态

当前版本已通过真实本地后端、商汤日日新真实回复、Android 15 模拟器和 iOS 26.5
模拟器的四主流程端到端验收，并通过 Android APK/AAB 与 unsigned iOS release 构建。
长期运行、弱网、防盗链和各内容平台原生 App 唤起仍建议在对应真机上持续观察。

## 环境与后端配置

- Flutter 3.x
- 自建 OpenBiliClaw 后端（LLM 可配商汤日日新等 OpenAI 兼容服务）
- Web/iOS/macOS 默认连接 `127.0.0.1:8420`；Android 模拟器默认连接
  `10.0.2.2:8420`，Android 真机或远程部署在设置页填服务器局域网 IP。

### 通过内置 Tailscale 连接

1. 在后端服务器安装 Tailscale、加入同一个 tailnet，并确保后端的 `8420` 端口可从
   tailnet 访问；建议用 Tailscale ACL 只授权 OpenBiliClaw 客户端访问该端口。
2. 首次连接时可以在系统浏览器登录 Tailscale，或在管理后台创建一次性/短期 Auth Key。
   不要把可复用 Key 写入源码、配置文件或发布包。
3. App 的「连接设置」选择「内置 Tailscale」，填写服务器 MagicDNS 名称（或 `100.x.x.x` 地址）
   和端口；Auth Key 可留空，此时 App 会打开系统浏览器完成登录授权。

首次注册后，App 会把节点身份保存在应用私有且排除云备份的目录中，之后可无 Key 自动重连；
「移除设备」会清除本地身份。此模式目前仅覆盖 App 的 HTTP API 请求，实时 WebSocket 会自动回退为轮询；
Web、Linux、macOS 和 Windows 继续使用直接连接。

后端 LLM 切换示例（`config.toml`，商汤日日新走 OpenAI 兼容模式）：

```toml
[llm]
default_provider = "openai_compatible"

[llm.openai_compatible]
api_key = "你的商汤 Key"
model = "deepseek-v4-flash"          # 或账号可用的商汤模型
base_url = "https://token.sensenova.cn/v1/"
```

可选：本地 Ollama 语义去重（推荐池去重 / 疲劳控制，`/api/health` 的 `embedding_ready` 会变 true）：

```toml
[llm.embedding]
provider = "ollama"
model = "nomic-embed-text"           # 或 bge-m3
base_url = "http://127.0.0.1:11434"
output_dimensionality = 768          # 需匹配 embedding 模型实际维度
```

## License

[MIT](LICENSE)
