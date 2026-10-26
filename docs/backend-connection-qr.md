# 后端扫码连接

连接流程：电脑 Web / 插件「手机版」→ 选择局域网、Tailscale 或公网地址 → App 连接设置「扫码连接」→ 自动保存并重连。二维码也可用手机相机打开 Mobile Web。

| 二维码 | App 保存的后端 | 连接方式 |
| --- | --- | --- |
| `http://192.168.1.7:8420/m/` | `http://192.168.1.7:8420` | 直接连接，同一局域网 |
| `http://100.100.1.2:19090/m/` | `http://100.100.1.2:19090` | 直接连接，手机系统 Tailscale 已启用 |
| `http://100.100.1.3:8421/m/?obc_connection=tailscale` | `http://100.100.1.3:8421` | App 内置 Tailscale，同一 tailnet |
| `https://obc.example.com/prefix/m/` | `https://obc.example.com/prefix` | 直接连接，保留 HTTPS 与代理路径 |

解析入口 `BackendConnectionLink.parse()`：只接受 HTTP(S)，拒绝回环、通配监听地址与 URL 用户名密码，移除 `/m/`、`/web/`、`/api/` 入口后缀及查询 / fragment，保留其他路径前缀和端口；`obc_connection=tailscale` 明确选择 App 内嵌连接，普通系统 Tailscale 地址保持直接连接。参数不包含登录凭据。旧版电脑二维码的普通 `/m/` 链接也能导入。

`SettingsView` 使用同一解析器处理相机和粘贴链接，再通过既有 `ApiClient.saveSettings()` 持久化、清理旧后端会话并重启推荐轮询。扫码应用内节点时先复用现有 Tailnet 连接 / 网页登录流程；成功后自动保存，入网失败时保留已填地址和原客户端设置。已有后端密码门禁继续生效；扫码不等于已通过业务登录校验。

相机页 `BackendScanView` 仅在 Android / iOS 展示入口，使用 `mobile_scanner` 7.4.2 在设备本地识别 QR，切到后台停止相机，返回后恢复；离开页面释放控制器。iOS 增加 `NSCameraUsageDescription`，Android 声明 CAMERA 且相机硬件非必需。拒绝权限、没有相机或其他平台可用「粘贴连接链接」，手动地址入口继续保留。插件用默认随包 Android MLKit，不要求手机首次下载识别模型。

数据流：

```text
desktop Web / extension HTTP(S) QR → device camera → local QR decoder
                                            ↓
paste link ─────────────────────→ BackendConnectionLink.parse
  → ApiClient.saveSettings (direct / embedded Tailscale) → polling reconnect
  → existing backend authentication
```

验证：`flutter analyze`、`flutter test`；新增 `backend_connection_link_test.dart` 覆盖地址与非法输入，`settings_qr_connection_test.dart` 覆盖扫描回执 → 保存 → 重连 → 重启恢复；原有 `settings_backend_url_test.dart` 继续验证手动输入。相机实拍和真实跨设备 Tailnet 连通性需要设备验收，不能由 widget mock 替代。后端 / 插件需使用配套新版本，源代码分支完成不代表商店或安装包已更新。

官方组件说明：[mobile_scanner](https://pub.dev/packages/mobile_scanner)。

## 本次验证（2026-10-26）

- `flutter analyze`：通过；`flutter test`：179 项通过。
- 扫码连接 7 项通过，含取消、无效扫码、首次 Tailnet 入网和登录未完成时保留旧后端；原有手动配置回归继续通过。
- iOS simulator / Android debug 原生构建通过；相机 purpose string 已在编译后的 iOS `Info.plist` 中确认。
- `flutter test integration_test/backend_qr_decode_test.dart -d macos`：原生解码测试通过。固定 PNG 来自后端 / 插件实际 JS QR 编码器，覆盖五类链接和 v5 / v10。该测试不打开相机；`mobile_scanner` 明确不支持 iOS 模拟器图片分析，应使用 macOS、Android 或 iOS 真机。
- 未执行手机相机实拍和真实跨设备 / tailnet 网络验收；未发布新商店或安装包版本。

## 连接设置预览

下图为 390×844 Widget 渲染预览（2026-10-27，测试地址），使用实际设置页与应用浅色主题、本机字体。临时截图测试通过后已移除；不作为真机相机或跨设备网络验收。

![连接设置中的扫码与粘贴入口](images/connection-settings-qr.png)
