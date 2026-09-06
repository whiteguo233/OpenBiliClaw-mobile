import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../api/utils.dart';
import '../models/recommendation.dart';
import '../theme/app_theme.dart';

class CoverImage extends StatelessWidget {
  final String url;
  final String sourcePlatform;
  final double width;
  final double height;
  final double borderRadius;

  const CoverImage({
    super.key,
    required this.url,
    this.sourcePlatform = '',
    this.width = double.infinity,
    this.height = 140,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: _placeholder(context, Icons.movie_outlined),
        ),
      );
    }
    // 有些平台返回协议相对 URL（//cdn...），客户端直接加载会失败，
    // 这里统一补上 https。
    final normalizedUrl = url.startsWith('//') ? 'https:$url' : url;
    final client = context.read<ApiClient>();
    final token = client.sessionToken;
    // 根据来源平台决定是否直连原图 CDN。小红书/网页等无法保证直连的
    // 图片仍走后端代理；其余平台先直连，失败再自动回退到后端。
    final normalizedPlatform = normalizeSourcePlatform(sourcePlatform);
    final canDirect =
        !kIsWeb && !client.usesTailscale && _canUseDirect(normalizedPlatform);
    final proxyUrl = kIsWeb
        ? proxyImageUrl(normalizedUrl, client.baseUrl, token: token)
        : proxyImageUrl(normalizedUrl, client.baseUrl);
    final headers = token.isEmpty ? null : {'Cookie': 'obc_session=$token'};
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: _LimitedImage(
        width: width,
        height: height,
        placeholder: _placeholder,
        child: client.usesTailscale
            ? _TailnetImage(
                client: client,
                imageUrl: proxyUrl,
                headers: headers,
                width: width,
                height: height,
                placeholder: _placeholder,
              )
            : canDirect
            ? _DirectFirstImage(
                directUrl: normalizedUrl,
                proxyUrl: proxyUrl,
                headers: headers,
                width: width,
                height: height,
                placeholder: _placeholder,
              )
            : CachedNetworkImage(
                imageUrl: proxyUrl,
                httpHeaders: headers,
                width: width,
                height: height,
                fit: BoxFit.cover,
                memCacheWidth: 640,
                filterQuality: FilterQuality.medium,
                fadeInDuration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                placeholder: (_, _) =>
                    _placeholder(context, Icons.image_outlined),
                errorWidget: (_, _, _) =>
                    _placeholder(context, Icons.broken_image_outlined),
              ),
      ),
    );
  }

  static bool _canUseDirect(String platform) {
    // 这些平台的原图 CDN 一般可直接访问；小红书/网页等未知来源走后端。
    return switch (platform) {
      'bilibili' ||
      'douyin' ||
      'weibo' ||
      'youtube' ||
      'twitter' ||
      'zhihu' ||
      'reddit' ||
      'bangumi' ||
      'linuxdo' ||
      'v2ex' => true,
      _ => false,
    };
  }

  Widget _placeholder(BuildContext context, IconData icon) {
    final palette = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.surfaceMuted, palette.lavenderSoft],
        ),
      ),
      child: Center(child: Icon(icon, size: 32, color: palette.lineStrong)),
    );
  }
}

/// Limits simultaneous cover image downloads so API/refresh requests keep
/// enough phone network/CPU headroom. This is a client-side complement to the
/// server-side Image Proxy split.
class _ImageLimiter {
  _ImageLimiter._();

  static final _ImageLimiter instance = _ImageLimiter._();

  static const int maxConcurrent = 4;
  int _active = 0;
  final List<Completer<void>> _waiters = [];

  Future<void> acquire() {
    if (_active < maxConcurrent) {
      _active += 1;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeAt(0);
      // The waiter takes this slot immediately.
      next.complete();
    } else if (_active > 0) {
      _active -= 1;
    }
  }
}

class _LimitedImage extends StatefulWidget {
  const _LimitedImage({
    required this.width,
    required this.height,
    required this.placeholder,
    required this.child,
  });

  final double width;
  final double height;
  final Widget Function(BuildContext, IconData) placeholder;
  final Widget child;

  @override
  State<_LimitedImage> createState() => _LimitedImageState();
}

class _LimitedImageState extends State<_LimitedImage> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _acquire();
  }

  Future<void> _acquire() async {
    await _ImageLimiter.instance.acquire();
    if (!mounted) {
      _ImageLimiter.instance.release();
      return;
    }
    setState(() => _ready = true);
  }

  @override
  void dispose() {
    if (_ready) {
      _ImageLimiter.instance.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.placeholder(context, Icons.image_outlined),
      );
    }
    return widget.child;
  }
}

class _DirectFirstImage extends StatefulWidget {
  const _DirectFirstImage({
    required this.directUrl,
    required this.proxyUrl,
    required this.headers,
    required this.width,
    required this.height,
    required this.placeholder,
  });

  final String directUrl;
  final String proxyUrl;
  final Map<String, String>? headers;
  final double width;
  final double height;
  final Widget Function(BuildContext, IconData) placeholder;

  @override
  State<_DirectFirstImage> createState() => _DirectFirstImageState();
}

class _DirectFirstImageState extends State<_DirectFirstImage> {
  bool _useDirect = true;

  @override
  void didUpdateWidget(covariant _DirectFirstImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.directUrl != widget.directUrl ||
        oldWidget.proxyUrl != widget.proxyUrl) {
      _useDirect = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: _useDirect ? widget.directUrl : widget.proxyUrl,
      httpHeaders: _useDirect ? null : widget.headers,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.cover,
      memCacheWidth: 640,
      filterQuality: FilterQuality.medium,
      fadeInDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      placeholder: (_, _) => widget.placeholder(context, Icons.image_outlined),
      errorWidget: (_, _, _) {
        if (_useDirect) {
          // Direct CDN failed; switch to the backend proxy on the next frame.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _useDirect = false);
          });
          return widget.placeholder(context, Icons.image_outlined);
        }
        return widget.placeholder(context, Icons.broken_image_outlined);
      },
    );
  }
}

class _TailnetImage extends StatefulWidget {
  const _TailnetImage({
    required this.client,
    required this.imageUrl,
    required this.headers,
    required this.width,
    required this.height,
    required this.placeholder,
  });

  final ApiClient client;
  final String imageUrl;
  final Map<String, String>? headers;
  final double width;
  final double height;
  final Widget Function(BuildContext, IconData) placeholder;

  @override
  State<_TailnetImage> createState() => _TailnetImageState();
}

class _TailnetImageState extends State<_TailnetImage> {
  /// Simple process-wide memory cache for tailnet cover bytes.
  /// Tailnet mode cannot use CachedNetworkImage's disk cache directly, so
  /// avoid re-fetching the same backend proxy image every time a widget is
  /// rebuilt or scrolled back into view.
  static final Map<String, Uint8List> _memoryCache = {};
  static const int _maxMemoryCacheEntries = 300;

  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TailnetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.client != widget.client) {
      _load();
    }
  }

  void _load() {
    final cached = _memoryCache[widget.imageUrl];
    if (cached != null) {
      _bytes = Future.value(cached);
      return;
    }
    _bytes = widget.client
        .getBytes(Uri.parse(widget.imageUrl), headers: widget.headers)
        .then((bytes) {
          if (_memoryCache.length >= _maxMemoryCacheEntries) {
            _memoryCache.remove(_memoryCache.keys.first);
          }
          _memoryCache[widget.imageUrl] = bytes;
          return bytes;
        });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.placeholder(context, Icons.broken_image_outlined);
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return widget.placeholder(context, Icons.image_outlined);
        }
        return Image.memory(
          bytes,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: 640,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              widget.placeholder(context, Icons.broken_image_outlined),
        );
      },
    );
  }
}
