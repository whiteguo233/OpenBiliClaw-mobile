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
- 🖼️ **封面图 B 站 CDN 直连**（原生端跳过服务端代理，省两跳；web 端因 CORS 限制仍走代理）
- 封面图 / 已保存视图请求头会话管理优化
- API 返回数据处理调整
- 推荐页、画像页、历史记录支持「回到顶部」悬浮按钮
- 支持 Android / iOS / Web / Linux / macOS / Windows
- GitHub Actions 双端 CI 与 Release：签名 APK/AAB、供用户自签名的 unsigned IPA、符号文件、校验和和构建来源证明

## 构建与发版

- Pull Request 和 `main` 会自动执行格式检查、静态分析、测试及 Android/iOS 构建验证。
- 推送与 `pubspec.yaml` 版本一致的 `vX.Y.Z` 标签，会并行构建 Android 和 iOS 正式产物并创建 GitHub Release。
- Android 正式产物由项目 release keystore 签名；iOS 发布未签名 IPA，由用户使用自己的 Apple 账号和证书重签，仓库不保存 Apple 凭据。

完整配置和发版步骤见 [双端 Release 发版指南](.github/RELEASE.md)。

## 测试

```bash
flutter test                                   # 单元/模型测试（无需后端）
flutter test test_e2e/                         # API + LLM 端到端：需后端 8420 且 LLM 已配置
flutter test integration_test/app_e2e_test.dart -d macos   # 真实 App 端到端（含 AI 对话）
```

- `test/`：纯单元/模型测试，默认 `flutter test` 执行，无需后端。
- `test_e2e/e2e_backend_test.dart`：真实请求后端验证内容历史、保存反馈事件、收藏交叉切换、自动同步配置、健康与 embedding 就绪。
- `test_e2e/e2e_llm_test.dart`：验证 LLM 驱动的画像素描、惊喜推荐理由、AI 对话回复、待聊确认、活动流汇总。
- `integration_test/app_e2e_test.dart`：在 macOS 上真实启动 App，断言四个 tab 加载真实数据、画像页展示 LLM 人格素描、对话发送后收到商汤真实回复。

## 版本状态

🧪 **新特性版（未经长期实测）**：在此前网络优化前版之上新增 B 站封面直连等改动，
作者尚未长期实测。建议合并前重点验证弱网 / 防盗链场景下的图片加载表现。

## 环境与后端配置

- Flutter 3.x
- 自建 OpenBiliClaw 后端（LLM 可配商汤日日新等 OpenAI 兼容服务）
- Web/iOS/macOS 默认连接 `127.0.0.1:8420`；Android 模拟器默认连接
  `10.0.2.2:8420`，Android 真机或远程部署在设置页填服务器局域网 IP。

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
