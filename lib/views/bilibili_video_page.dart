import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/bilibili_api.dart';
import '../api/client.dart';
import '../services/bilibili_webview_session.dart';

/// In-app Bilibili video page.
///
/// This is the first concrete step toward a PiliPlus-style in-app Bilibili
/// experience: instead of handing every Bilibili card to the system's native
/// Bilibili app, the Flutter app opens its own page and embeds Bilibili's
/// mobile web player. It keeps the player, danmaku and comment surface inside
/// OpenBiliClaw, while the existing native launch flow remains the fallback
/// for non-Bilibili platforms and for devices where WebView is unavailable.
///
/// The backend already owns the Bilibili login session, so this page injects
/// the backend cookie into the WebView before the first request. The embedded
/// web player, danmaku and comments then use the same logged-in account
/// instead of falling back to an anonymous Bilibili session.
class BilibiliVideoPage extends StatefulWidget {
  const BilibiliVideoPage({
    super.key,
    required this.bvid,
    this.title = '',
    this.contentUrl = '',
    this.coverUrl = '',
    this.sessionCookie = '',
  });

  final String bvid;
  final String title;
  final String contentUrl;
  final String coverUrl;

  /// 可选：直接复用 `play-url` 下发的 Cookie 头，省掉一次 auth/export 请求。
  final String sessionCookie;

  @override
  State<BilibiliVideoPage> createState() => _BilibiliVideoPageState();
}

class _BilibiliVideoPageState extends State<BilibiliVideoPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;
  bool _sessionInjected = false;
  String? _currentUrl;
  Completer<void>? _bootstrapCompleter;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;
            // 引导页只是用来取得 B 站 origin 写 Cookie，不驱动页面 UI。
            if (_bootstrapCompleter != null) return;
            setState(() {
              _loading = progress < 100;
              _failed = false;
            });
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _loading = true;
              _failed = false;
            });
          },
          onPageFinished: (url) {
            final completer = _bootstrapCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.complete();
              return;
            }
            // 引导页的迟到回调不覆盖目标页状态。
            if (url == kBilibiliCookieBootstrapUrl) return;
            if (!mounted) return;
            setState(() {
              _currentUrl = url;
              _loading = false;
            });
          },
          onWebResourceError: (error) {
            // Some subresource failures are transient; only surface an error
            // when the main document fails to load.
            if (error.isForMainFrame != true) return;
            final completer = _bootstrapCompleter;
            if (completer != null && !completer.isCompleted) {
              completer.completeError(error);
              return;
            }
            if (!mounted) return;
            setState(() {
              _loading = false;
              _failed = true;
            });
          },
          onNavigationRequest: (request) {
            // Stay inside Bilibili's web surface. Block custom schemes
            // (bilibili://, android-app://, etc.) so the embedded page does
            // not hand the user back to the native Bilibili app.
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'http' || uri.scheme == 'https') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      );

    // webview_flutter_wkwebview 尚未在 macOS 上实现 setOpaque，
    // 调用 setBackgroundColor 会直接抛 UnimplementedError。
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      _controller.setBackgroundColor(Colors.black);
    }

    _loadWithBackendSession();
  }

  /// 先把后端已有的 B 站登录态注入 WebView，再发起首个请求。
  ///
  /// 优先复用调用方传来的 `play-url` Cookie；没有时再向后端 `auth/export`
  /// 取一次。后端不可用或未登录时安静地退回匿名网页，不阻塞打开页面。
  Future<void> _loadWithBackendSession() async {
    var cookieHeader = widget.sessionCookie.trim();
    if (cookieHeader.isEmpty) {
      try {
        final api = BilibiliApi(context.read<ApiClient>());
        final session = await api.exportSession(timeoutSeconds: 3);
        cookieHeader = session.cookie;
      } catch (_) {
        // 后端未实现或未配置 B 站登录态时继续匿名加载。
      }
    }
    if (cookieHeader.isNotEmpty) {
      await _injectBackendSession(cookieHeader);
    }
    if (!mounted) return;
    await _loadUrl(_initialUrl());
  }

  /// Android 与 iOS/macOS 的 Cookie 写入路径不同：
  ///
  /// - Android 的 `WebViewCookieManager.setCookie` 会对 Cookie 值再做一次
  ///   `Uri.encodeComponent`，SESSDATA 里的 `%2A`/`%2C` 会被二次编码，登录态
  ///   会失效。这里先在 B 站同源引导页里执行 `document.cookie`，写入原始值。
  /// - iOS/macOS 走 WKHTTPCookieStore，原生 API 不会改动值，直接写域名 Cookie。
  Future<void> _injectBackendSession(String cookieHeader) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final script = buildBilibiliCookieScript(cookieHeader);
        if (script.isEmpty) return;
        if (!await _loadBootstrapPage()) return;
        final current = await _controller.currentUrl();
        final host = current == null ? '' : (Uri.tryParse(current)?.host ?? '');
        if (host != 'bilibili.com' && !host.endsWith('.bilibili.com')) {
          return;
        }
        await WebViewCookieManager().clearCookies();
        await _controller.runJavaScript(script);
      } else {
        final written = await injectBilibiliCookies(cookieHeader: cookieHeader);
        if (written <= 0) return;
      }
      if (mounted) setState(() => _sessionInjected = true);
    } catch (_) {
      // 注入失败时安静地退回匿名网页，不影响页面本身打开。
    }
  }

  /// 加载一个极小的 B 站同源页面，等待它完成后再写 Cookie。
  Future<bool> _loadBootstrapPage() async {
    final completer = Completer<void>();
    _bootstrapCompleter = completer;
    try {
      await _controller.loadRequest(Uri.parse(kBilibiliCookieBootstrapUrl));
      await completer.future.timeout(const Duration(seconds: 8));
      return true;
    } catch (_) {
      return false;
    } finally {
      _bootstrapCompleter = null;
    }
  }

  Future<void> _loadUrl(String url) async {
    if (!mounted) return;
    setState(() {
      _currentUrl = url;
      _loading = true;
      _failed = false;
    });
    await _controller.loadRequest(Uri.parse(url));
  }

  String _initialUrl() {
    final contentUrl = widget.contentUrl.trim();
    if (contentUrl.isNotEmpty) {
      final uri = Uri.tryParse(contentUrl);
      if (uri != null &&
          const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
        final host = uri.host.toLowerCase();
        if (host == 'bilibili.com' ||
            host.endsWith('.bilibili.com') ||
            host == 'b23.tv' ||
            host.endsWith('.b23.tv')) {
          return contentUrl;
        }
      }
    }
    final bvid = widget.bvid.trim();
    if (bvid.isNotEmpty) {
      return 'https://www.bilibili.com/video/$bvid';
    }
    return contentUrl.isNotEmpty ? contentUrl : 'https://www.bilibili.com';
  }

  Future<void> _exportCookies() async {
    final client = context.read<ApiClient>();
    final manager = WebViewCookieManager();
    final cookies = await manager.getCookies(
      domain: Uri.parse('https://www.bilibili.com'),
    );
    final cookieMap = <String, String>{
      for (final cookie in cookies) cookie.name: cookie.value,
    };
    if (cookieMap.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有取到 B 站 Cookie')));
      return;
    }
    final api = BilibiliApi(client);
    try {
      final info = await api.importSession(cookies: cookieMap);
      if (!mounted) return;
      if (info.isLoggedIn) {
        setState(() => _sessionInjected = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            info.isLoggedIn
                ? '已同步到后端，当前登录：${info.user?.name ?? 'B站用户'}'
                : 'Cookie 已提交，但后端校验未通过',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('同步失败：$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title.trim().isNotEmpty ? widget.title : 'B站视频',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '登录后同步 Cookie 到后端',
            onPressed: _exportCookies,
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: '用浏览器打开',
            onPressed: () => _launchExternal(
              _currentUrl ?? _initialUrl(),
              externalApplication: true,
            ),
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
          IconButton(
            tooltip: '用B站App打开',
            onPressed: () => _launchExternal(
              'bilibili://video/${widget.bvid.trim()}',
              externalApplication: true,
            ),
            icon: const Icon(Icons.ondemand_video_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_failed) _errorPanel(context, 'B站页面加载失败，可以试试右上角用浏览器打开。'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          color: Colors.black,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _sessionInjected
                      ? '已带上 B 站登录态 · 播放/评论使用后端会话'
                      : '已停留在 OpenBiliClaw 内置页面',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorPanel(BuildContext context, String message) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white70,
              size: 44,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _failed = false;
                  _loading = true;
                });
                _controller.reload();
              },
              child: const Text('重新加载'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchExternal(
    String url, {
    bool externalApplication = false,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(
      uri,
      mode: externalApplication
          ? LaunchMode.externalApplication
          : LaunchMode.inAppBrowserView,
    )) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开外部链接')));
    }
  }
}
