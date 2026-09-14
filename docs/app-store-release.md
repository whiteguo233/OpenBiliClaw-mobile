# App Store 首次发布准备

更新日期：2026-09-14。当前尚未上传 App Store Connect，也未提交审核。

## 本次付费发布决定与阻塞项

- 用户已收到开发者申请通过邮件；需要重新登录 App Store Connect 核实团队和权限。
- 发布方式：一次性付费下载，用户已确认中国大陆价格为人民币 ¥1，发行范围包含中国大陆。
- 对外开发者名称为 White；用户已授权公开客服邮箱 `gsy_littlewhite@foxmail.com`。客户端连接用户自己电脑上的 OpenBiliClaw，手机端不另收 AI 调用费用。电脑端原有模型账号与费用范围正作最后核对，不承诺 ¥1 包含无限云端 AI 服务。
- Apple 公布的人民币价格表最低为 ¥1，未列出 ¥0.99。用户已接受 ¥1，待登录后台后设置；当前尚未保存任何商店价格或发行范围。[Apple 价格表，第 2 页](https://www.apple.com/newsroom/pdfs/App-Store-Pricing-Update.pdf)
- 用户确认拟以上海个人主体办理，无实名域名、无开发者统一业务后端；已按源码核实用户自有后端架构，先向上海确认受理方式，不把购买域名或云服务器作为默认前置条件。
- 用户确认尚未办理 App ICP 备案。中国大陆正式发行前需要完成适用的备案和资质资料；付费开发者会员不替代 App 备案。[App 信息](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- 付费销售需要账户持有人接受 Paid Apps Agreement，并完成适用的银行和税务资料。当前尚未核实后台状态。协议接受和法定税务声明需要用户审阅确认，不代填未知身份或税务信息。[付费协议](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements)、[收款条件](https://developer.apple.com/help/app-store-connect/getting-paid/overview-of-receiving-payments)
- 2026-09-14 基于提交 `6eb0472`、版本 `0.3.157+2007` 加入本次发布准备修改；`flutter analyze` 无问题，最终 `flutter test` 全部 108 项通过。新增文档页通过 iPhone 17 Pro 模拟器集成测试，4 张浅色/深色 QA 截图已人工检查；组件测试另覆盖小屏、横屏、iPad 尺寸及 3.2 倍字体。
- `flutter build ipa --release --no-codesign` 已在本次修改后重新完成归档，产物为 `build/ios/archive/Runner.xcarchive`（约 309.8 MB）。版本、构建号、最低系统和 Bundle ID 验证通过；默认启动图警告已消失。归档未签名，未导出可上传的 IPA。该归档早于后续 White、公开客服邮箱和电脑端使用说明的文案更新；正式上传前须重新打包最新文案。
- 已补充随包分发、无需连接后端的隐私政策和使用支持页，在登录页与设置页提供入口；已补充 White 与授权公开邮箱；公开托管地址待确定。已用现有 App 图标替换默认启动占位图。
- [商店中文资料](app-store/metadata.zh-Hans.md)、[隐私申报核对与审核说明](app-store/privacy-submission.md)、[备案技术资料](app-store/filing-preparation.md)已准备成本地草稿；其中 Apple 法定主体、审核后端、凭据和未核实的数据处理事实均保留待确认，尚未提交到 Apple。
- AI 数据共享同意、审核可访问后端、正式签名、商店截图及大陆备案仍待完成。会员激活本身不意味着具备送审条件。

## 2026-09-13 已验证的构建

| 项目 | 当前结果 |
| --- | --- |
| 版本 | `0.3.156+2006` |
| Bundle ID | `com.openbiliclaw.openbiliclawApp`，尚未确认在开发者团队下可注册 |
| 工具链 | Flutter 3.47.2 / Xcode 26.5 / iPhoneOS 26.5 SDK |
| 最低系统 | iOS 15.0 |
| 静态检查 | `flutter analyze` 通过 |
| 单元和组件测试 | `flutter test`：90 项通过 |
| 真机架构构建 | `flutter build ios --release --no-codesign` 通过，约 65.6 MB |
| 本地产物 | `build/ios/iphoneos/Runner.app`（未签名，不可直接上传或安装） |
| 签名现状 | 本机有 Apple Development 身份；项目未配置 DEVELOPMENT_TEAM，付费会员资格待确认 |

验证包含工作区当时已有的未提交修改。此次未重新做真机、实际后端或 iPad 验收。
现有 GitHub Release 的 unsigned IPA 流程可继续保留；App Store 需要独立的分发签名流程。

## 上传前需要补齐

1. **开发者账号和应用记录**：确认有效的 Apple Developer Program 会员、团队和 App Store Connect 权限；在该团队注册 Bundle ID 并创建应用。Bundle ID 如果需要变更，还须同步检查 `lib/services/tailnet_service_native.dart` 的 iOS `appId`。
2. **隐私信息**：App 内政策与入口已加入，正文位于 `assets/legal/privacy_zh.md`。继续核对后台配置的 AI 服务、保存期限和删除途径，并发布公开可访问的政策 URL。提交的 App Privacy 答案需覆盖实际后端和 SDK 行为，不能直接填“无数据收集”。
3. **AI 数据共享**：核查个人数据发送给后端配置的第三方 AI 前是否已有明确说明和同意机制；当前客户端未发现专门的 AI 数据共享同意入口。需要结合后端实现确定接收方和范围。
4. **审核后端**：默认 `127.0.0.1:8420` 无法让审核人员访问你的电脑。提供独立、稳定、审核期间可访问的测试后端及登录步骤；推荐使用 HTTPS。不能把个人后端密码、B 站 Cookie 或 Tailscale Auth Key 写进代码或文档。审核凭据只填入 App Store Connect 的审核信息。
5. **内容和交互**：核实第三方平台条款允许当前内容展示、取流和账号操作；准备必要的授权材料。检查评论等用户内容的举报、屏蔽和处理机制，现有弹幕关键词屏蔽不能代表这些要求已满足。
6. **内置 Tailscale**：据当前实现，它只承载本 App 请求。准确说明这一点，核实相关审核分类；不能因此直接断言 VPN 条款一定适用或一定不适用。按实际内置加密实现回答出口合规问题，尚未确定豁免前不要机械添加 `ITSAppUsesNonExemptEncryption=false`。
7. **商店资料**：确定名称、类别、价格、发行地区、版权主体、支持 URL、隐私 URL、审核联系人和年龄分级；用准备提交的实际界面制作 iPhone/iPad 所需截图。若包含中国大陆，按 App Store Connect 要求核实 ICP 备案及适用资质。
8. **归档检查**：本次包已包含 Flutter、shared_preferences 等依赖的隐私清单，但这不等于整个应用已满足隐私要求。签名归档后使用 Xcode 验证和隐私报告继续核对，尤其是 Tailscale 等内置原生代码。

Apple 要求审核可访问全部功能、公开隐私政策、适当处理用户内容及第三方服务权限；具体适用性需要结合最终功能。[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

加密和地区资料分别参考 [出口合规说明](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance) 和 [App 信息](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)。

## 首发商店文案草稿

以下为草稿，不包含尚未确定的运营主体、服务承诺或平台授权声明。

**名称**：OpenBiliClaw

**副标题**：连接你的内容推荐与兴趣助手

**描述**：

OpenBiliClaw 是连接自建 OpenBiliClaw 后端的内容发现客户端。浏览个性化推荐，整理收藏和稍后再看，通过 AI 对话表达兴趣，查看逐渐积累的兴趣画像。

- 浏览推荐内容，反馈喜欢或不感兴趣。
- 管理收藏、稍后再看和近期内容历史。
- 与后端配置的 AI 助手对话，调整内容偏好。
- 通过消息收件箱查看兴趣探测和认知更新。
- 支持浅色与深色外观，以及系统字体大小设置。

使用前需要配置可访问的 OpenBiliClaw 后端；AI 和内容服务取决于后端配置及相关平台的可用性。应用提供第三方内容访问功能，不代表获得相关平台官方背书。

**购买说明**：本应用采用一次性付费下载，客户端不另行收取 AI 调用费用。使用时连接你自己电脑上运行的 OpenBiliClaw 服务；电脑需保持运行且可从手机访问。AI 功能由电脑端服务及其模型配置提供。

**关键词草稿**：内容发现,推荐,兴趣,收藏,稍后再看,AI助手

## 审核说明草稿

在 App Store Connect 补齐实际后端地址、审核凭据和联系方式后，再使用这段说明。

> OpenBiliClaw is a client for a separately hosted OpenBiliClaw backend. Open connection settings using the gear icon, select Direct connection, and enter the review server supplied in App Review Information. Save the settings and sign in using the supplied backend credentials if prompted. The main tabs provide recommendations, AI chat, an interest profile, and saved content. The optional embedded Tailscale connection carries this app's backend requests. Review access should be tested using the supplied server before submission. Third-party content and account features require separate verification and review instructions where applicable.

## 账号就绪后的实际发布流程

1. 在 Xcode Settings → Accounts 登录自己的开发者账号，不在聊天或仓库中提供密码。
2. 打开 `ios/Runner.xcworkspace`，为 Runner 的 Signing & Capabilities 选择正确的 Team，确认正式 Bundle ID。
3. 在 App Store Connect 创建对应应用，确认版本和构建号未被占用。如已占用，使用新的构建号。
4. 完成上述功能和资料后，生成正式归档：

   ```bash
   flutter pub get
   flutter analyze
   flutter test
   flutter build ipa --release --export-method app-store
   ```

   也可从 Xcode Product → Archive 归档，在 Organizer 中选择 Validate App，再通过 Distribute App 上传 App Store Connect。具体按钮名称以当前 Xcode 为准。不要重签本次未签名 `.app` 来替代正式归档。
5. 等待构建处理完成并回答加密问题；通过 TestFlight 验证真实 iPhone/iPad 上的后端连接、登录、播放和主要功能。
6. 填齐商店及审核资料，选择验证通过的构建并提交审核。若希望审核后自行决定上线时间，选择手动发布。提交审核不等于已经上架。

上传流程参考 [Apple 提交说明](https://developer.apple.com/app-store/submitting/)。
