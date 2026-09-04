# OpenBiliClaw B 站登录态与原生播放器协议

> 状态：供前后端联调使用。后端实现后，客户端 `BilibiliVideoPage` 可以从 WebView 方案平滑切换到原生播放器。
>
> 所有接口都挂在现有 `/api` 前缀下，鉴权沿用 OpenBiliClaw 后端的 `X-OBC-Auth` 与 `obc_session` 会话。

## 设计原则

1. **登录态尽量只放在后端**。
   移动端不持久化 B 站 Cookie；需要登录时通过二维码或 WebView 登录，把 Cookie 导入后端。
2. **原生播放器不直接调 B 站 API**。
   移动端只调 OpenBiliClaw 后端，由后端负责 WBI 签名、Cookie、Buvid、UA、防盗链等。
3. **后端可以同时支持“网页登录”和“二维码登录”**。
   网页登录适合在 App 内 WebView 里手动登录；二维码登录适合直接弹二维码让人扫。
4. **Cookie 返回给客户端仅用于当前播放请求，不做持久化存储**。
   后端也可以选择不放完整 Cookie，而是返回短时效的播放 URL/流地址。

---

## 1. 登录态接口

### 1.1 查询登录状态

```
GET /api/bilibili/auth/status
```

响应示例：

```json
{
  "ok": true,
  "platform": "bilibili",
  "status": "logged_in",
  "user": {
    "mid": 123456,
    "name": "昵称",
    "face": "https://i0.hdslb.com/...",
    "vip": false
  },
  "scopes": ["video", "danmaku", "comment", "fav", "later"],
  "expires_at": "2026-01-01T00:00:00Z"
}
```

`status` 枚举：

| 值 | 含义 |
| --- | --- |
| `anonymous` | 未登录 |
| `scanning` | 二维码已生成，等待扫码 |
| `scanned` | 已扫码，等待确认 |
| `pending` | 登录流程进行中 |
| `logged_in` | 已登录且可用 |
| `expired` | 登录态已过期 |
| `unsupported` | 后端暂不支持该平台 |

`scopes` 建议包含：

- `video`：拉取视频播放地址
- `danmaku`：拉取弹幕
- `comment`：评论相关操作
- `fav`：收藏夹操作
- `later`：稍后再看操作

---

### 1.2 发起二维码登录

```
POST /api/bilibili/auth/qrcode
```

请求体可以留空：

```json
{}
```

响应示例：

```json
{
  "ok": true,
  "qrcode_key": "a1b2c3...",
  "qrcode_url": "https://passport.bilibili.com/h5/qrcode/...",
  "expires_in": 180,
  "expires_at": "2026-01-01T00:03:00Z"
}
```

- `qrcode_url`：客户端可以直接显示为二维码图片内容。
- `qrcode_key`：轮询登录状态时使用。

---

### 1.3 轮询二维码登录状态

```
GET /api/bilibili/auth/qrcode/poll?key=a1b2c3...
```

响应示例：

```json
{
  "ok": true,
  "status": "confirmed",
  "user": {
    "mid": 123456,
    "name": "昵称",
    "face": "https://i0.hdslb.com/..."
  },
  "message": "登录成功"
}
```

`status` 枚举：

| 值 | 含义 |
| --- | --- |
| `pending` | 还没扫 |
| `scanned` | 已扫码，未确认 |
| `confirmed` | 确认登录，后端已保存会话 |
| `expired` | 二维码过期 |
| `failed` | 登录失败 |

客户端看到 `confirmed` 后应重新拉一次 `GET /api/bilibili/auth/status`。

---

### 1.4 WebView 登录后导入 Cookie

App 内置 WebView 登录 B 站后，可把当前 WebView Cookie 导出并导入后端。这样用户可以在 App 里用 B 站官方登录页直接登录。

```
POST /api/bilibili/auth/import
```

请求体：

```json
{
  "cookies": {
    "SESSDATA": "...",
    "bili_jct": "...",
    "DedeUserID": "...",
    "DedeUserID__ckMd5": "...",
    "sid": "..."
  },
  "user_agent": "Mozilla/5.0 (iPhone; ...) AppleWebKit/...",
  "buvid": "...",
  "source": "mobile_webview"
}
```

响应示例：

```json
{
  "ok": true,
  "status": "logged_in",
  "user": {
    "mid": 123456,
    "name": "昵称",
    "face": "https://i0.hdslb.com/..."
  }
}
```

---

### 1.5 清除登录态

```
DELETE /api/bilibili/auth/session
```

响应：

```json
{
  "ok": true
}
```

---

## 2. 原生播放器取流接口

移动端原生播放器需要“视频分 P、画质、音质、弹幕、字幕”，统一从后端拿。

### 2.1 获取播放信息

```
POST /api/bilibili/player/play-url
```

请求体：

```json
{
  "bvid": "BV1xx411c7mD",
  "cid": 12345,
  "qn": 80,
  "preferred_codec": "avc",
  "fnval": 4048,
  "fourk": 1
}
```

字段说明：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `bvid` | 是 | B 站视频 ID |
| `cid` | 否 | 分 P 的 cid；不传时后端返回全部 P，客户端可选 |
| `qn` | 否 | 期望画质，默认后端预设 |
| `preferred_codec` | 否 | `avc` / `hevc` / `av1`，默认 `avc` |
| `fnval` | 否 | 默认 `4048`（DASH+仅HLS等） |
| `fourk` | 否 | 是否允许 4K，默认 `1` |

响应示例（压平后的流地址）：

```json
{
  "ok": true,
  "bvid": "BV1xx411c7mD",
  "cid": 12345,
  "duration": 3601,
  "pages": [
    {
      "cid": 12345,
      "page": 1,
      "part": "P1 标题",
      "duration": 3601,
      "dimension": {
        "width": 1920,
        "height": 1080
      }
    }
  ],
  "qualities": [
    {
      "qn": 116,
      "label": "1080P 高帧率",
      "width": 1920,
      "height": 1080
    },
    {
      "qn": 80,
      "label": "1080P",
      "width": 1920,
      "height": 1080
    }
  ],
  "video": {
    "qn": 80,
    "label": "1080P",
    "codec": "avc",
    "url": "https://upos-sz-mirrorcos.bilivideo.com/...",
    "backup_urls": [
      "https://upos-sz-mirror.../..."
    ],
    "width": 1920,
    "height": 1080,
    "mime_type": "video/mp4"
  },
  "audio": {
    "qn": 30280,
    "codec": "fmp4",
    "url": "https://upos-sz-mirrorcos.bilivideo.com/...",
    "backup_urls": [],
    "bandwidth": 132000,
    "mime_type": "audio/mp4"
  },
  "subtitles": [
    {
      "lan": "zh-CN",
      "name": "中文（自动生成）",
      "url": "https://aisubtitle.hdslb.com/..."
    }
  ],
  "danmaku": {
    "url": "https://api.bilibili.com/x/v1/dm/list.so?oid=12345",
    "headers": {
      "referer": "https://www.bilibili.com",
      "user-agent": "Mozilla/5.0 ..."
    }
  },
  "headers": {
    "referer": "https://www.bilibili.com",
    "user-agent": "Mozilla/5.0 ...",
    "cookie": "SESSDATA=...; bili_jct=..."
  },
  "expires_at": "2026-01-01T00:10:00Z"
}
```

注意事项：

- `headers.cookie` 是可选项。
  - 如果 CDN 不需要 Cookie 就能播放，后端可以不返回。
  - 如果返回，客户端**只用于本次媒体请求，不落盘**。
- 如果后端不方便暴露 Cookie，可以返回一个 `x-obc-media-token`，由后端代理媒体流；协议后续可扩展。
- `danmaku.headers` 通常固定为 B 站 referer + UA，用于弹幕请求。
- `video.url` / `audio.url` 是选好画质后的流地址；如果客户端要自己切换画质，可以再调用一次并传不同 `qn`。

---

## 3. 建议后端实现顺序

1. `GET /api/bilibili/auth/status`
2. `POST /api/bilibili/auth/qrcode` + `GET /api/bilibili/auth/qrcode/poll`
3. `POST /api/bilibili/auth/import`
4. `DELETE /api/bilibili/auth/session`
5. `POST /api/bilibili/player/play-url`
6. 可选：`POST /api/bilibili/player/danmaku` 或直接返回弹幕 URL

---

## 4. 客户端使用流程（原生播放器）

1. 打开 B 站视频页时，先读 `GET /api/bilibili/auth/status`。
2. 如果 `status != logged_in`，提供“扫码登录”或“WebView 登录”。
3. 登录后调 `POST /api/bilibili/player/play-url` 获取流地址。
4. 用 `media_kit` 或等价播放器播放 `video.url` + `audio.url`。
5. 请求 `danmaku.url` 时带上 `danmaku.headers`。
6. 播放器自定义 UI 上提供画质切换、倍数、全屏、记忆播放等。
7. 退出页面或切换视频时，不持久化 Cookie，只保留后端会话。

---

## 5. 互动 / 评论 / 相关视频接口

| 接口 | 用途 |
| --- | --- |
| `GET /api/bilibili/video/relation?bvid=...` | 当前登录用户的点赞/投币/收藏/稍后状态 |
| `POST /api/bilibili/video/like` | 点赞/取消点赞 |
| `POST /api/bilibili/video/coin` | 投币 |
| `POST /api/bilibili/video/triple` | 一键三连 |
| `POST /api/bilibili/video/favorite` | 收藏/取消收藏 |
| `POST /api/bilibili/video/watch-later` | 加入/移出稍后再看 |
| `GET /api/bilibili/video/related?bvid=...` | 相关视频 |
| `GET /api/bilibili/video/comments?bvid=...&pn=1&limit=20` | 视频评论（分页，兜底路径，见下） |
| `GET /api/bilibili/video/comment-replies?bvid=...&root=<rpid>&pn=1&limit=10` | 某条评论的完整回复楼（兜底路径，见下） |

### 评论区：端上直连优先，后端兜底

`play-url` 响应的 `headers.cookie` 已经把后端的 B 站 Cookie 下发给播放器拉流用，因此客户端复用同一个 Cookie **直连** B 站官方评论接口，无需后端转发：

- `GET https://api.bilibili.com/x/web-interface/view?bvid=...` — 解析 `aid`（评论接口的 `oid`）
- `GET https://api.bilibili.com/x/v2/reply?type=1&oid=<aid>&sort=2&pn=1&ps=20` — 热评分页（无需 WBI 签名；匿名翻页被 B 站上游限制，必须带 Cookie）
- `GET https://api.bilibili.com/x/v2/reply/reply?type=1&oid=<aid>&root=<rpid>&pn=1&ps=10` — 完整回复楼

请求头带 `cookie` / `referer: https://www.bilibili.com` / `user-agent`。直连失败（风控、网络）时回退到上表的后端 `/api/bilibili/video/comments` 系列接口。客户端内部统一解析为：

```json
{
  "items": [
    {
      "rpid": 123,
      "mid": 456,
      "uname": "某用户",
      "avatar": "https://i0.hdslb.com/bfs/face/xxx.jpg",
      "message": "评论内容",
      "like_count": 10,
      "reply_count": 5,
      "replies": [{"rpid": 124, "mid": 789, "uname": "...", "message": "...", "like_count": 2}]
    }
  ],
  "total": 1234,
  "page": 1,
  "has_more": true
}
```

- `replies` 内嵌该评论的前几条回复；当 `reply_count > replies.length` 时，客户端按页拉取完整回复楼。
- `has_more = page * pageSize < total`，为 `true` 时客户端展示“加载更多评论”。
- 直连路径由 B 站原生响应解析（`member.uname` / `member.avatar` / `content.message` / `like` / `rcount` / `page.count`）；后端兜底路径按上表字段解析，头像字段兼容 `avatar` 或 `avatar_url`，旧版后端缺少的分页/回复/头像字段按缺省值兼容。

除评论外，其余互动接口都复用同一个后端 B 站 Cookie；移动端不持久化任何 B 站凭据，播放会话结束即丢弃。
