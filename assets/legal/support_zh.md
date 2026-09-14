# 使用与支持

开发者：White  
客服邮箱：[gsy_littlewhite@foxmail.com](mailto:gsy_littlewhite@foxmail.com)

## 开始使用

OpenBiliClaw 是连接你自己电脑上 OpenBiliClaw 服务的移动客户端。请先在电脑上运行 OpenBiliClaw，再在手机的“连接设置”填写可访问的地址，保存并测试连接。后端开启密码门禁时，使用该后端的密码登录。

手机上的 127.0.0.1 指向手机本身。连接电脑上的后端时，应填写电脑的局域网地址，并确保两台设备可以互相访问。远程连接可使用 HTTPS 地址，或使用内置 Tailscale 连接同一网络中的后端。

后端部署说明见 [OpenBiliClaw 项目](https://github.com/whiteguo233/OpenBiliClaw)。

## 购买与使用

App Store 版本采用一次性付费下载，客户端不另行收取 AI 调用费用。使用时需要连接电脑端服务，电脑需保持运行且可从手机访问。AI 功能由所连接的电脑端服务及其模型配置提供。

## 功能说明

- 推荐：浏览内容，反馈喜欢或不感兴趣。
- 对话：与后端配置的 AI 助手交流内容偏好。
- 画像：查看后端根据使用情况积累的兴趣信息。
- 内容库：管理收藏、稍后再看和近期历史。

内容及 AI 服务的可用性取决于后端配置和第三方平台。第三方平台登录与权限由相应平台管理。

## 无法连接

确认后端正在运行，检查地址、协议和端口。iPhone 连接局域网后端时，请检查系统设置中的本地网络权限。使用 Tailscale 时，需要先完成登录并确认后端允许该设备访问。

## 播放与登录问题

部分视频需要有效的平台登录态或访问权限。可检查后端的 B 站登录状态，或使用播放页提供的网页入口。平台权限、内容下架或网络限制可能导致播放失败。

## 反馈与数据请求

技术问题可邮件联系 White：[gsy_littlewhite@foxmail.com](mailto:gsy_littlewhite@foxmail.com)，或提交到[问题反馈](https://github.com/whiteguo233/OpenBiliClaw-mobile/issues)。请提供 App 版本、系统版本、操作步骤和不包含个人信息的错误描述。

请勿公开密码、Cookie、Auth Key、个人服务器地址、聊天记录或身份证明。后端数据的导出或删除，请联系你所使用的后端运营者。

## 开源许可

客户端项目使用 MIT 许可证。源代码及许可见 [OpenBiliClaw-mobile](https://github.com/whiteguo233/OpenBiliClaw-mobile)。第三方组件适用各自的开源许可。
