import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

/// 一个极小的 B 站同源页面。Android 端为了绕开 webview_flutter 对 Cookie 值
/// 的二次 `Uri.encodeComponent`（会把 SESSDATA 里的 `%2A`/`%2C` 变成 `%252A`），
/// 先加载这个页面，再用 `document.cookie` 写入原始值。
const String kBilibiliCookieBootstrapUrl =
    'https://www.bilibili.com/robots.txt';

/// B 站登录态 Cookie 的作用域。
const String kBilibiliCookieDomain = '.bilibili.com';

/// 解析 `SESSDATA=x; bili_jct=y` 形式的 Cookie 头。
///
/// 只保留有名字和值的键值对；Cookie 值里可能出现 `=`，所以按第一个 `=` 拆分。
Map<String, String> parseCookieHeader(String header) {
  final cookies = <String, String>{};
  for (final part in header.split(';')) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    final index = trimmed.indexOf('=');
    if (index <= 0) continue;
    final name = trimmed.substring(0, index).trim();
    final value = trimmed.substring(index + 1).trim();
    if (name.isEmpty || value.isEmpty) continue;
    cookies[name] = value;
  }
  return cookies;
}

/// 构造在 B 站同源页面里用 `document.cookie` 写入登录态的 JavaScript。
///
/// 与 [injectBilibiliCookies] 不同，JS 路径不会对值做任何 URL 编码，
/// SESSDATA 里的 `%2A` / `%2C` 会原样保存。返回空串表示没有可写入的 Cookie。
String buildBilibiliCookieScript(String cookieHeader) {
  final cookies = parseCookieHeader(cookieHeader);
  if (cookies.isEmpty) return '';
  final buffer = StringBuffer();
  for (final entry in cookies.entries) {
    final cookie = jsonEncode(
      '${entry.key}=${entry.value}; domain=$kBilibiliCookieDomain; path=/; secure',
    );
    buffer.write('try{document.cookie=$cookie;}catch(e){}');
  }
  return buffer.toString();
}

/// 把后端导出的 B 站 Cookie 注入 iOS/macOS 的 WKHTTPCookieStore。
///
/// Apple 平台的原生 API 不会改动 Cookie 值，直接写 `.bilibili.com` 即可覆盖
/// `api.bilibili.com` 等子域。返回实际写入的 Cookie 条数；0 表示 Cookie 头为空
/// 或没有可解析的键值对。[setCookie] 仅用于测试注入。
Future<int> injectBilibiliCookies({
  required String cookieHeader,
  Future<void> Function(WebViewCookie cookie)? setCookie,
}) async {
  final cookies = parseCookieHeader(cookieHeader);
  if (cookies.isEmpty) return 0;
  final setter = setCookie ?? WebViewCookieManager().setCookie;
  var written = 0;
  for (final entry in cookies.entries) {
    try {
      await setter(
        WebViewCookie(
          name: entry.key,
          value: entry.value,
          domain: kBilibiliCookieDomain,
          path: '/',
        ),
      );
      written++;
    } catch (_) {
      // 单条写入失败不影响其它 Cookie。
    }
  }
  return written;
}
