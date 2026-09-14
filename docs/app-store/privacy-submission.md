# App Privacy 与审核资料核对

这是填写 App Store Connect 前的事实核对表，不是已经提交的隐私声明。以正式版本、实际后端和 SDK 行为为准；“用户自行部署”不自动等于 Apple 定义下的“无数据收集”。

## 数据流

| 数据 | 当前代码证据 | 接收方或存储位置 | 填报前需确认 |
| --- | --- | --- | --- |
| 后端地址与连接方式 | `lib/api/client.dart` 的 `loadSettings` / `saveSettings` | 设备偏好与安全存储 | 后端地址可能在卸载重装后恢复；不承诺卸载即删除所有信息 |
| 后端会话 | `lib/api/client.dart` 的 `_captureSession` | 客户端偏好；发往所选后端 | 是否含用户标识、关联和留存方式 |
| 聊天及上下文 | `lib/api/chat_api.dart` | 所选后端，可能再发送给 AI 服务 | User Content 类别、关联性、接收方、留存及训练规则 |
| 浏览、反馈、兴趣画像 | events / recommend / profile API | 所选后端，可能再发送给 AI 服务 | Product Interaction、Browsing History 等适用类别及用途 |
| B 站 Cookie 与账号资料 | `lib/api/bilibili_api.dart`、WebView 会话服务 | 后端、设备网页会话和 B 站 | 账号标识、保存时间、撤销和删除方式 |
| Tailscale 节点与网络信息 | `lib/services/tailnet_service_native.dart` | 本地身份目录及 Tailscale 相关服务 | SDK 收集类型、是否关联身份、服务政策 |
| IP 地址与请求日志 | 网络访问必需，后端日志实现待核实 | 后端、内容平台及相关网络服务 | 日志实际内容、保留期限、是否用于定位或识别 |
| 商店付款 | 本应用无内购 SDK，采用商店付费下载 | Apple | 不把 App Store 处理支付误写为客户端直接收集银行卡 |

## 还需实现或验证

- 已增加可离线阅读的隐私政策及使用支持页，登录页和连接设置均可进入。已根据用户授权补充对外名称 White 和客服邮箱 `gsy_littlewhite@foxmail.com`；Apple 法定销售主体仍需在后台核对。
- AI 数据共享的明确告知与同意不能仅靠隐私政策替代。需结合实际后端确定模型接收方，并覆盖聊天、推荐及兴趣画像等可能向模型发送数据的路径；本次尚未宣称该流程已完成。
- 清除设备数据不等于删除后端数据。后端的聊天、画像、历史、日志及备份应有明确的访问和删除途径，不声明当前客户端不存在的“一键删除全部”能力。
- 核对平台内容使用权限及用户评论的举报、屏蔽和处理机制。UI 上的“不感兴趣”或弹幕关键词过滤不代表全部处理机制。
- 根据实际使用的 Tailscale 原生加密库填写出口合规，不自动标为无加密或豁免。
- 签名归档后检查 Xcode 隐私报告及 SDK 清单；不能仅凭存在 `PrivacyInfo.xcprivacy` 就认定合规。

## 审核说明英文草稿

OpenBiliClaw is a mobile client for an OpenBiliClaw backend. It provides content recommendations, saved items, an interest profile, and AI chat using the backend's configured services.

To connect, open connection settings, select Direct connection, enter the review server supplied in App Review Information, and save. Use the supplied backend credentials if prompted. The review server must remain available throughout review. The optional embedded Tailscale mode is used for this app's backend connection.

The app is a paid mobile client that connects to OpenBiliClaw running on the user’s own computer. The mobile client does not charge additional AI usage fees. AI features use the connected computer’s model configuration. Third-party platform account features require separate, working review instructions and appropriate content permissions.

Do not submit this draft until the server, credentials, the computer-side model billing scope, platform login instructions, privacy disclosures, and reviewer contact details have been verified. Credentials belong only in App Review Information, not in the repository or public support pages.

## 参考

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [出口合规](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
