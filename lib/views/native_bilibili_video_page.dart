import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:volume_controller/volume_controller.dart';

import '../api/bilibili_api.dart';
import '../api/bilibili_comment_api.dart';
import '../api/client.dart';
import '../api/utils.dart';
import '../models/bilibili_interaction.dart';
import '../models/bilibili_play.dart';
import '../services/bilibili_space_launcher.dart';
import '../theme/app_theme.dart';
import '../widgets/bilibili_comment_widgets.dart';
import '../widgets/bilibili_video_introduction.dart';
import '../widgets/bilibili_video_layout.dart';
import '../widgets/danmaku_overlay.dart';
import 'bilibili_login_view.dart';
import 'bilibili_video_page.dart';

/// Native Bilibili video player page.
///
/// It uses the backend `/api/bilibili/player/play-url` protocol to get the
/// resolved stream URLs and headers, then plays them through `media_kit`.
/// If the backend is not ready or the request fails, the UI offers a fallback
/// to the existing in-app WebView page.
class NativeBilibiliVideoPage extends StatefulWidget {
  const NativeBilibiliVideoPage({
    super.key,
    required this.bvid,
    this.title = '',
    this.contentUrl = '',
    this.coverUrl = '',
    this.recommendationReason = '',
  });

  final String bvid;
  final String title;
  final String contentUrl;
  final String coverUrl;
  final String recommendationReason;

  @override
  State<NativeBilibiliVideoPage> createState() =>
      _NativeBilibiliVideoPageState();
}

class _NativeBilibiliVideoPageState extends State<NativeBilibiliVideoPage> {
  late final Player _player = Player();
  VideoController? _videoController;
  BilibiliApi? _api;
  BilibiliPlayResult? _result;
  bool _loading = true;
  bool _switchingStream = false;
  String? _error;
  bool _loadStarted = false;
  int? _selectedQn;
  int? _selectedCid;
  List<DanmakuItem> _danmakuItems = const [];
  bool _danmakuEnabled = true;
  List<String> _danmakuBlockWords = const [];
  double _rate = 1.0;
  int _selectedSubtitle = -1;
  List<_BilibiliSubtitle> _subtitles = const [];
  TapDownDetails? _doubleTapDetails;
  BilibiliVideoState? _videoState;
  List<BilibiliComment> _comments = const [];
  int _commentTotal = 0;
  int _commentNextPn = 1;
  bool _commentHasMore = false;
  bool _commentsLoadingMore = false;
  bool _commentsLoading = true;
  bool _commentsFailed = false;
  bool _commentsMoreFailed = false;
  BilibiliCommentApi? _commentDirect;
  bool _directSessionTried = false;
  int? _commentAid;
  List<BilibiliRelatedVideo> _related = const [];
  String _videoDescription = '';
  String _videoTitle = '';
  int? _viewCount;
  int? _danmakuCount;
  int _publishedAt = 0;
  bool _relatedLoading = true;
  bool _relatedFailed = false;
  String? _interactionBusy;
  BilibiliUpInfo? _up;
  bool _upCardLoaded = false;
  bool _upCardUnsupported = false;
  bool _followStateUnconfirmed = false;
  bool _followBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= BilibiliApi(context.read<ApiClient>());
    if (!_loadStarted) {
      _loadStarted = true;
      unawaited(_loadDanmakuSettings());
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    unawaited(_saveProgress());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _saveProgress() async {
    final result = _result;
    if (result == null) return;
    final position = _player.state.position.inMilliseconds;
    if (position <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'bilibili_progress_${widget.bvid}_${result.cid}',
      position,
    );
  }

  Future<void> _load() async {
    try {
      final api = _api;
      if (api == null) return;
      final result = await api.playUrl(
        bvid: widget.bvid,
        cid: _selectedCid,
        qn: _selectedQn,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _selectedCid = result.cid;
        _loading = false;
        _error = null;
        // The play-url response carries the backend's Bilibili cookie for
        // stream playback; reuse it to read comments directly from
        // api.bilibili.com instead of proxying through the backend.
        final cookie = _headerValue(result.headers, 'cookie');
        _commentDirect = cookie.isNotEmpty
            ? BilibiliCommentApi(
                cookie: cookie,
                userAgent: _headerValue(result.headers, 'user-agent'),
              )
            : null;
        _commentAid = null;
        if (_selectedQn == null ||
            !result.qualities.any((quality) => quality.qn == _selectedQn)) {
          final actualQn = result.video?.qn;
          _selectedQn =
              actualQn != null &&
                  result.qualities.any((quality) => quality.qn == actualQn)
              ? actualQn
              : (result.qualities.isNotEmpty
                    ? result.qualities.first.qn
                    : null);
        }
      });
      unawaited(_loadDanmaku(result));
      unawaited(_loadSubtitles(result));
      unawaited(_loadVideoInfo());
      unawaited(_loadInteractions());
      await _openPlayer(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openPlayer(BilibiliPlayResult result) async {
    final video = result.video;
    final audio = result.audio;
    if (video == null || video.url.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '后端没有返回可播放的视频流';
      });
      return;
    }
    final uri = _mediaUri(video.url, audio?.url ?? '');
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(
      'bilibili_progress_${widget.bvid}_${result.cid}',
    );
    final start = saved != null && saved > 0
        ? Duration(milliseconds: saved)
        : null;
    _videoController = VideoController(_player);
    await _player.open(
      Media(
        uri,
        httpHeaders: result.headers.isEmpty ? null : result.headers,
        start: start,
      ),
      play: true,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadDanmakuSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('bilibili_danmaku_enabled');
    final blockWords = prefs.getStringList('bilibili_danmaku_block_words');
    if (!mounted) return;
    setState(() {
      _danmakuEnabled = enabled ?? true;
      _danmakuBlockWords = blockWords ?? const [];
    });
  }

  Future<void> _loadDanmaku(BilibiliPlayResult result) async {
    final danmaku = result.danmaku;
    if (!danmaku.exists) return;
    try {
      final response = await http.get(
        Uri.parse(danmaku.url),
        headers: danmaku.headers,
      );
      if (response.statusCode != 200) return;
      final body = utf8.decode(
        inflateDanmakuBytes(response.bodyBytes),
        allowMalformed: true,
      );
      final pattern = RegExp(r'<d p="([^"]+)">([^<]*)</d>');
      final items = <DanmakuItem>[];
      for (final match in pattern.allMatches(body)) {
        final params = match.group(1)?.split(',') ?? const <String>[];
        if (params.isEmpty) continue;
        final seconds = double.tryParse(params.first) ?? 0;
        final text = match.group(2) ?? '';
        final normalized = text.trim();
        if (normalized.isEmpty) continue;
        if (_danmakuBlockWords.any(normalized.contains)) continue;
        items.add(
          DanmakuItem(
            time: Duration(milliseconds: (seconds * 1000).round()),
            text: text,
            color: _danmakuColor(params),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _danmakuItems = items);
    } catch (_) {
      // Danmaku is optional; playback should not depend on it.
    }
  }

  Color _danmakuColor(List<String> params) {
    if (params.length <= 3) return Colors.white;
    final value = int.tryParse(params[3]) ?? 0;
    if (value == 0) return Colors.white;
    return Color(0xFF000000 | (value & 0xFFFFFF));
  }

  /// Loads the video metadata that powers the intro tab, and kicks off the UP
  /// card enrichment as soon as the owner is known. Runs independently from
  /// the interaction channels so a slow comment list cannot delay the creator
  /// row / description.
  Future<void> _loadVideoInfo() async {
    final api = _api;
    if (api == null) return;
    Map<String, dynamic>? info;
    try {
      info = await api.videoInfo(bvid: widget.bvid);
    } catch (_) {
      final direct = _commentDirect;
      if (direct != null) {
        try {
          info = await direct.videoInfo(widget.bvid);
        } catch (_) {
          // Fall through: the page still plays without intro metadata.
        }
      }
    }
    if (info == null || !mounted) return;
    final desc = info['desc']?.toString().trim() ?? '';
    final rawOwner = info['owner'];
    final owner = rawOwner is Map
        ? BilibiliUpInfo.fromVideoOwner(Map<String, dynamic>.from(rawOwner))
        : null;
    final stat = info['stat'];
    int? statNumber(String key) =>
        stat is Map ? int.tryParse('${stat[key] ?? ''}') : null;
    final replyTotal = stat is Map
        ? int.tryParse((stat['reply'] ?? '').toString()) ?? 0
        : 0;
    final likeTotal = stat is Map
        ? int.tryParse((stat['like'] ?? '').toString()) ?? 0
        : 0;
    final coinTotal = stat is Map
        ? int.tryParse((stat['coin'] ?? '').toString()) ?? 0
        : 0;
    final favoriteTotal = stat is Map
        ? int.tryParse((stat['favorite'] ?? '').toString()) ?? 0
        : 0;
    setState(() {
      _videoTitle = decodeHtml(info!['title']?.toString().trim() ?? '');
      _viewCount = statNumber('view');
      _danmakuCount = statNumber('danmaku');
      _publishedAt = int.tryParse('${info['pubdate'] ?? ''}') ?? 0;
      if (owner != null && owner.hasIdentity) _up = owner;
      if (replyTotal > 0 && _commentTotal <= 0) {
        _commentTotal = replyTotal;
      }
      final current = _videoState ?? const BilibiliVideoState();
      _videoState = current.copyWith(
        likeCount: likeTotal,
        coinCount: coinTotal,
        favoriteCount: favoriteTotal,
      );
      if (desc.isNotEmpty) _videoDescription = desc;
    });
    if (owner != null && owner.mid > 0) {
      unawaited(_loadUpCard(owner.mid));
    }
  }

  /// Enriches the video owner with the follow state and fan count. While the
  /// card request is in flight the button shows a spinner. A 404 means the
  /// backend predates the follow protocol, so the button is hidden; other
  /// failures keep it visible in the unknown "follow" state because Bilibili's
  /// duplicate-follow response (22014) is treated as success by the backend,
  /// making a first tap safe even when the local snapshot is stale.
  Future<void> _loadUpCard(int mid) async {
    final api = _api;
    if (api == null || mid <= 0) return;
    try {
      final card = await api.userCard(mid: mid);
      if (!mounted) return;
      setState(() {
        final current = _up;
        _up = current == null ? card : current.merge(card);
        _upCardLoaded = true;
        _upCardUnsupported = false;
        _followStateUnconfirmed = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _upCardLoaded = false;
        if (error.statusCode == 404) {
          _upCardUnsupported = true;
          _followStateUnconfirmed = false;
        } else {
          _followStateUnconfirmed = true;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _upCardLoaded = false;
        _followStateUnconfirmed = true;
      });
    }
  }

  Future<void> _loadInteractions() async {
    await Future.wait([_loadVideoRelation(), _loadComments(), _loadRelated()]);
  }

  Future<void> _loadVideoRelation() async {
    final api = _api;
    if (api == null) return;
    // Each channel is independent: a slow/failed comment fetch must not
    // prevent the like/favorite state from rendering.
    try {
      final state = await api.videoRelation(bvid: widget.bvid);
      if (mounted) {
        setState(() {
          final current = _videoState ?? const BilibiliVideoState();
          _videoState = current.copyWith(
            like: state.like,
            coin: state.coin,
            favorite: state.favorite,
            watchLater: state.watchLater,
          );
        });
      }
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsFailed = false;
      _commentsMoreFailed = false;
    });
    try {
      final commentPage = await _fetchCommentPage(1);
      if (!mounted) return;
      setState(() {
        _comments = commentPage.items;
        _commentTotal = commentPage.total;
        _commentHasMore = commentPage.hasMore;
        _commentNextPn = commentPage.page + 1;
        _commentsLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _commentsLoading = false;
          _commentsFailed = true;
        });
      }
    }
  }

  Future<void> _loadRelated() async {
    final api = _api;
    if (api == null) return;
    setState(() {
      _relatedLoading = true;
      _relatedFailed = false;
    });
    try {
      final related = await api.relatedVideos(bvid: widget.bvid);
      if (mounted) {
        setState(() {
          _related = related;
          _relatedLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _relatedLoading = false;
          _relatedFailed = true;
        });
      }
    }
  }

  /// 先尝试复用 `play-url` 下发的 Cookie；如果没有，再向后端单独导出一次
  /// B 站 Cookie。两者都失败时回退到后端代理。结果只在当前页面内存中维护，
  /// 不写入 SharedPreferences。
  Future<void> _ensureDirectSession() async {
    final api = _api;
    if (api == null || _commentDirect != null || _directSessionTried) return;
    _directSessionTried = true;
    try {
      final session = await api.exportSession();
      if (!mounted || session.cookie.isEmpty) return;
      _commentDirect = BilibiliCommentApi.fromSession(session);
    } catch (_) {
      // 后端未实现 auth/export 时不需要报错，直接走原有代理/play-url 路径。
    }
  }

  /// Comment pages come from api.bilibili.com directly when the play-url
  /// response handed us a cookie (or auth/export did); otherwise fall back
  /// to the backend proxy.
  Future<BilibiliCommentPage> _fetchCommentPage(int pn) async {
    await _ensureDirectSession();
    final direct = _commentDirect;
    if (direct != null) {
      try {
        final aid = _commentAid ??= await direct.resolveAid(widget.bvid);
        if (aid > 0) {
          return await direct.videoComments(aid: aid, pn: pn);
        }
      } catch (_) {
        // Fall through to the backend proxy below.
      }
    }
    final api = _api;
    if (api == null) return const BilibiliCommentPage();
    return api.videoComments(bvid: widget.bvid, pn: pn);
  }

  Future<BilibiliCommentPage> _fetchReplyPage(int root, int pn) async {
    await _ensureDirectSession();
    final direct = _commentDirect;
    if (direct != null) {
      try {
        final aid = _commentAid ??= await direct.resolveAid(widget.bvid);
        if (aid > 0) {
          return await direct.commentReplies(aid: aid, root: root, pn: pn);
        }
      } catch (_) {
        // Fall through to the backend proxy below.
      }
    }
    final api = _api;
    if (api == null) return const BilibiliCommentPage();
    return api.commentReplies(bvid: widget.bvid, root: root, pn: pn);
  }

  static String _headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return '';
  }

  Future<void> _loadMoreComments() async {
    if (!_commentHasMore || _commentsLoadingMore || _commentsLoading) return;
    setState(() {
      _commentsLoadingMore = true;
      _commentsMoreFailed = false;
    });
    try {
      final page = await _fetchCommentPage(_commentNextPn);
      if (!mounted) return;
      setState(() {
        _comments = _mergeComments(_comments, page.items);
        _commentTotal = page.total;
        _commentHasMore = page.hasMore;
        _commentNextPn = page.page + 1;
        _commentsLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentsLoadingMore = false;
        _commentsMoreFailed = true;
      });
    }
  }

  /// Appends [next] to [current] skipping duplicates, so a backend that
  /// ignores the `pn` parameter cannot make the list repeat itself.
  static List<BilibiliComment> _mergeComments(
    List<BilibiliComment> current,
    List<BilibiliComment> next,
  ) {
    final seen = current.map(_commentKey).toSet();
    return [
      ...current,
      ...next.where((comment) => seen.add(_commentKey(comment))),
    ];
  }

  static String _commentKey(BilibiliComment comment) => comment.rpid != 0
      ? 'r${comment.rpid}'
      : 'm${comment.mid}:${comment.message.hashCode}';

  Future<void> _toggleLike() async {
    final api = _api;
    if (api == null) return;
    var state = _videoState;
    if (state == null) {
      try {
        state = await api.videoRelation(bvid: widget.bvid);
        if (mounted) setState(() => _videoState = state);
      } catch (error) {
        if (mounted) _showSnack('获取互动状态失败：$error');
        return;
      }
    }
    try {
      final next = await api.likeVideo(widget.bvid, like: !state.like);
      if (!mounted) return;
      setState(() {
        final current = _videoState ?? state ?? const BilibiliVideoState();
        final changed = next.like != current.like;
        _videoState = current.copyWith(
          like: next.like,
          coin: next.coin,
          favorite: next.favorite,
          watchLater: next.watchLater,
          likeCount: current.likeCount > 0
              ? current.likeCount + (changed ? (next.like ? 1 : -1) : 0)
              : current.likeCount,
        );
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack('点赞失败：$error');
    }
  }

  Future<void> _toggleCoin() async {
    final api = _api;
    if (api == null) return;
    try {
      await api.coinVideo(widget.bvid, multiply: 1);
      if (!mounted) return;
      setState(() {
        final current = _videoState ?? const BilibiliVideoState();
        _videoState = current.copyWith(
          coin: current.coin + 1,
          coinCount: current.coinCount > 0
              ? current.coinCount + 1
              : current.coinCount,
        );
      });
      _showSnack('投币成功');
    } catch (error) {
      if (!mounted) return;
      _showSnack('投币失败：$error');
    }
  }

  Future<void> _toggleFavorite() async {
    final api = _api;
    if (api == null) return;
    var state = _videoState;
    if (state == null) {
      try {
        state = await api.videoRelation(bvid: widget.bvid);
        if (mounted) setState(() => _videoState = state);
      } catch (error) {
        if (mounted) _showSnack('获取互动状态失败：$error');
        return;
      }
    }
    try {
      final next = await api.favoriteVideo(
        widget.bvid,
        favorite: !state.favorite,
      );
      if (!mounted) return;
      setState(() {
        final current = _videoState ?? state ?? const BilibiliVideoState();
        final changed = next.favorite != current.favorite;
        _videoState = current.copyWith(
          like: next.like,
          coin: next.coin,
          favorite: next.favorite,
          watchLater: next.watchLater,
          favoriteCount: current.favoriteCount > 0
              ? current.favoriteCount + (changed ? (next.favorite ? 1 : -1) : 0)
              : current.favoriteCount,
        );
      });
      _showSnack(next.favorite ? '已收藏' : '已取消收藏');
    } catch (error) {
      if (!mounted) return;
      _showSnack('收藏失败：$error');
    }
  }

  Future<void> _toggleWatchLater() async {
    final api = _api;
    if (api == null) return;
    var state = _videoState;
    if (state == null) {
      try {
        state = await api.videoRelation(bvid: widget.bvid);
        if (mounted) setState(() => _videoState = state);
      } catch (error) {
        if (mounted) _showSnack('获取互动状态失败：$error');
        return;
      }
    }
    try {
      final next = await api.watchLaterVideo(
        widget.bvid,
        add: !state.watchLater,
      );
      if (!mounted) return;
      setState(() {
        final current = _videoState ?? state ?? const BilibiliVideoState();
        _videoState = current.copyWith(
          like: next.like,
          coin: next.coin,
          favorite: next.favorite,
          watchLater: next.watchLater,
        );
      });
      _showSnack(next.watchLater ? '已加入稍后再看' : '已移出稍后再看');
    } catch (error) {
      if (!mounted) return;
      _showSnack('稍后再看失败：$error');
    }
  }

  Future<void> _triple() async {
    final api = _api;
    if (api == null) return;
    try {
      final state = await api.tripleVideo(widget.bvid);
      if (!mounted) return;
      setState(() {
        final current = _videoState ?? const BilibiliVideoState();
        _videoState = current.copyWith(
          like: state.like,
          coin: state.coin,
          favorite: state.favorite,
          watchLater: state.watchLater,
          likeCount: current.likeCount > 0
              ? current.likeCount + 1
              : current.likeCount,
          coinCount: current.coinCount > 0
              ? current.coinCount + 1
              : current.coinCount,
          favoriteCount: current.favoriteCount > 0
              ? current.favoriteCount + 1
              : current.favoriteCount,
        );
      });
      _showSnack('三连成功');
    } catch (error) {
      if (!mounted) return;
      _showSnack('三连失败：$error');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _displayTitle => _videoTitle.isNotEmpty
      ? _videoTitle
      : (widget.title.isNotEmpty ? widget.title : 'B站视频');

  static String _shortCount(int value) => formatBilibiliCount(value);

  Future<void> _runInteraction(
    String action,
    Future<void> Function() run,
  ) async {
    if (_interactionBusy != null) return;
    setState(() => _interactionBusy = action);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _interactionBusy = null);
    }
  }

  List<Widget> _videoActions() => [
    BilibiliVideoAction(
      key: const ValueKey('bilibili-like'),
      icon: (_videoState?.like ?? false)
          ? Icons.thumb_up_rounded
          : Icons.thumb_up_outlined,
      label: '点赞',
      count: _videoState?.likeCount,
      active: _videoState?.like ?? false,
      busy: _interactionBusy == 'like' || _interactionBusy == 'triple',
      onTap: () => _runInteraction('like', _toggleLike),
      onLongPress: () => _runInteraction('triple', _triple),
    ),
    BilibiliVideoAction(
      key: const ValueKey('bilibili-coin'),
      icon: Icons.monetization_on_outlined,
      label: '投币',
      count: _videoState?.coinCount,
      active: (_videoState?.coin ?? 0) > 0,
      busy: _interactionBusy == 'coin',
      onTap: () => _runInteraction('coin', _toggleCoin),
    ),
    BilibiliVideoAction(
      key: const ValueKey('bilibili-favorite'),
      icon: (_videoState?.favorite ?? false)
          ? Icons.star_rounded
          : Icons.star_border_rounded,
      label: '收藏',
      count: _videoState?.favoriteCount,
      active: _videoState?.favorite ?? false,
      busy: _interactionBusy == 'favorite',
      onTap: () => _runInteraction('favorite', _toggleFavorite),
    ),
    BilibiliVideoAction(
      icon: Icons.reply_rounded,
      label: '分享',
      onTap: _shareVideo,
    ),
  ];

  Future<void> _shareVideo() async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: _displayTitle,
          text:
              '$_displayTitle\n${widget.contentUrl.isNotEmpty ? widget.contentUrl : 'https://www.bilibili.com/video/${widget.bvid}'}',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted) _showSnack('暂时无法分享，请稍后重试');
    }
  }

  Future<void> _showMoreActions() async {
    final theme = bilibiliVideoTheme(Theme.of(context));
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) => Theme(
        data: theme,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in <(String, IconData, String)>[
                  (
                    'later',
                    Icons.watch_later_outlined,
                    (_videoState?.watchLater ?? false) ? '移出稍后再看' : '稍后再看',
                  ),
                  ('triple', Icons.auto_awesome_outlined, '一键三连'),
                  ('settings', Icons.settings_outlined, '播放设置'),
                  ('web', Icons.language_rounded, '网页版播放'),
                  ('app', Icons.ondemand_video_rounded, '用B站App打开'),
                ])
                  ListTile(
                    leading: Icon(item.$2),
                    title: Text(item.$3),
                    onTap: () => Navigator.pop(context, item.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'later':
        await _runInteraction('later', _toggleWatchLater);
      case 'triple':
        await _runInteraction('triple', _triple);
      case 'settings':
        await _openPlayerSettings();
      case 'web':
        await _openWebViewFallback();
      case 'app':
        await _openBilibiliApp();
    }
  }

  Future<void> _toggleDanmaku() async {
    final enabled = !_danmakuEnabled;
    setState(() => _danmakuEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bilibili_danmaku_enabled', enabled);
  }

  Widget _upBar(BilibiliUpInfo up) {
    final colors = bilibiliVideoTheme(Theme.of(context)).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => unawaited(_openUpSpace(up)),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    BilibiliAvatar(url: up.avatarUrl, name: up.name, size: 40),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            up.name.isNotEmpty ? up.name : 'UP主',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            up.fans > 0 ? '${_shortCount(up.fans)}粉丝' : 'UP主',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_upCardUnsupported) ...[
            const SizedBox(width: 12),
            _followButton(up),
          ],
        ],
      ),
    );
  }

  Widget _followButton(BilibiliUpInfo up) {
    final colors = bilibiliVideoTheme(Theme.of(context)).colorScheme;
    final busy = _followBusy || (!_upCardLoaded && !_followStateUnconfirmed);
    final child = busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          )
        : Text(
            up.following ? '已关注' : '关注',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
    );
    if (up.following) {
      return OutlinedButton(
        onPressed: busy ? null : () => unawaited(_toggleFollow()),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.onSurfaceVariant,
          side: BorderSide(color: colors.outlineVariant),
          shape: shape,
          minimumSize: const Size(80, 36),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: busy ? null : () => unawaited(_toggleFollow()),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: const Color(0xFF401022),
        shape: shape,
        minimumSize: const Size(80, 36),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!busy) ...[
            const Icon(Icons.add_rounded, size: 16),
            const SizedBox(width: 3),
          ],
          child,
        ],
      ),
    );
  }

  static String _mediaUri(String videoUrl, String audioUrl) {
    if (audioUrl.isEmpty) return videoUrl;
    return 'edl://!no_chapters;'
        '%${videoUrl.length}%$videoUrl;'
        '!new_stream;!no_chapters;'
        '%${audioUrl.length}%$audioUrl';
  }

  /// Opens the UP 主 space through the native Bilibili app when possible,
  /// otherwise through the canonical web space page.
  Future<void> _openUpSpace(BilibiliUpInfo up) async {
    if (up.mid <= 0) return;
    final opened = await BilibiliSpaceLauncher.open(mid: '${up.mid}');
    if (!opened && mounted) _showSnack('无法打开 UP 主空间，请稍后重试');
  }

  Future<bool> _confirmUnfollow(String name) async {
    final label = name.trim().isEmpty ? '这位 UP 主' : name.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('取消关注'),
        content: Text('确定不再关注 $label 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('取消关注'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Follows or unfollows the video owner through the backend. Unfollowing
  /// asks for confirmation first so a single tap cannot silently drop an UP
  /// the user has followed for a long time.
  Future<void> _toggleFollow() async {
    final api = _api;
    final up = _up;
    if (api == null || up == null || up.mid <= 0 || _followBusy) return;
    if (_upCardUnsupported) {
      _showSnack('当前后端版本暂不支持关注，请先升级后端');
      return;
    }
    if (!_upCardLoaded && !_followStateUnconfirmed) return;
    if (up.following && !await _confirmUnfollow(up.name)) return;
    if (!mounted) return;
    final nextFollowing = !up.following;
    setState(() => _followBusy = true);
    try {
      final updated = await api.followUser(mid: up.mid, follow: nextFollowing);
      if (!mounted) return;
      setState(() {
        final current = _up ?? up;
        _up = current.merge(updated);
        _followBusy = false;
        _upCardLoaded = true;
        _upCardUnsupported = false;
        _followStateUnconfirmed = false;
      });
      _showSnack(nextFollowing ? '已关注' : '已取消关注');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      if (error.statusCode == 401) {
        _showFollowLoginPrompt();
      } else if (error.statusCode == 404) {
        setState(() {
          _upCardLoaded = false;
          _upCardUnsupported = true;
          _followStateUnconfirmed = false;
        });
        _showSnack('当前后端版本暂不支持关注，请先升级后端');
      } else {
        _showSnack('关注失败（HTTP ${error.statusCode}）');
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _followBusy = false);
      _showSnack('关注失败：$error');
    }
  }

  void _showFollowLoginPrompt() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('B 站登录态已失效，请先重新登录'),
        action: SnackBarAction(
          label: '去登录',
          onPressed: () => unawaited(_openLogin()),
        ),
      ),
    );
  }

  Future<void> _openWebViewFallback() async {
    final result = _result;
    final cookie = result == null ? '' : _headerValue(result.headers, 'cookie');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BilibiliVideoPage(
          bvid: widget.bvid,
          title: widget.title,
          contentUrl: widget.contentUrl,
          coverUrl: widget.coverUrl,
          sessionCookie: cookie,
        ),
      ),
    );
  }

  Future<void> _openLogin() async {
    final loggedIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const BilibiliLoginView()));
    if (loggedIn == true && mounted) {
      // 登录成功后重新拉取 play-url，并允许再次尝试 auth/export。
      _commentDirect = null;
      _commentAid = null;
      _directSessionTried = false;
      setState(() {
        _upCardLoaded = false;
        _upCardUnsupported = false;
        _followStateUnconfirmed = false;
        _followBusy = false;
      });
      await _load();
    }
  }

  Future<void> _openPlayerSettings() async {
    final result = _result;
    if (result == null) return;
    var selectedQn = _selectedQualityQn(result);
    var rate = _rate;
    var subtitleIndex = _selectedSubtitle;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('播放设置', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (result.qualities.isNotEmpty) ...[
                DropdownButtonFormField<int>(
                  initialValue: selectedQn,
                  decoration: const InputDecoration(
                    labelText: '清晰度',
                    isDense: true,
                  ),
                  items: [
                    for (final quality in result.qualities)
                      DropdownMenuItem<int>(
                        value: quality.qn,
                        child: Text(quality.label),
                      ),
                  ],
                  onChanged: (qn) {
                    if (qn == null) return;
                    selectedQn = qn;
                    unawaited(
                      _switchQuality(
                        result.qualities.firstWhere((item) => item.qn == qn),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
              DropdownButtonFormField<double>(
                initialValue: rate,
                decoration: const InputDecoration(
                  labelText: '倍速',
                  isDense: true,
                ),
                items: [
                  for (final item in const [0.5, 1.0, 1.25, 1.5, 2.0])
                    DropdownMenuItem<double>(
                      value: item,
                      child: Text(item == 1.0 ? '1.0x' : '${item}x'),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  rate = value;
                  unawaited(_switchRate(value));
                },
              ),
              if (result.subtitles.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: subtitleIndex,
                  decoration: const InputDecoration(
                    labelText: '字幕',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int>(value: -1, child: Text('关闭')),
                    for (var i = 0; i < result.subtitles.length; i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(result.subtitles[i].name),
                      ),
                  ],
                  onChanged: (index) {
                    if (index == null) return;
                    subtitleIndex = index;
                    unawaited(_selectSubtitle(index));
                  },
                ),
              ],
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('弹幕设置'),
                subtitle: Text(_danmakuEnabled ? '当前：开启' : '当前：关闭'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_openDanmakuSettings());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDanmakuSettings() async {
    var enabled = _danmakuEnabled;
    final blockWords = List<String>.from(_danmakuBlockWords);
    final controller = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('弹幕设置', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('显示弹幕'),
                value: enabled,
                onChanged: (value) => setSheetState(() => enabled = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: '屏蔽词',
                        hintText: '输入后回车添加',
                        isDense: true,
                      ),
                      onSubmitted: (value) {
                        final text = value.trim();
                        if (text.isNotEmpty && !blockWords.contains(text)) {
                          setSheetState(() => blockWords.add(text));
                          controller.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '添加屏蔽词',
                    onPressed: () {
                      final text = controller.text.trim();
                      if (text.isNotEmpty && !blockWords.contains(text)) {
                        setSheetState(() => blockWords.add(text));
                        controller.clear();
                      }
                    },
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              if (blockWords.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: blockWords
                      .map(
                        (word) => Chip(
                          label: Text(word),
                          onDeleted: () =>
                              setSheetState(() => blockWords.remove(word)),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: const Text('保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    controller.dispose();
    if (saved != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bilibili_danmaku_enabled', enabled);
    await prefs.setStringList('bilibili_danmaku_block_words', blockWords);
    if (!mounted) return;
    setState(() {
      _danmakuEnabled = enabled;
      _danmakuBlockWords = List.unmodifiable(blockWords);
    });
    final result = _result;
    if (result != null) {
      unawaited(_loadDanmaku(result));
    }
  }

  /// 通过 B 站官方 `bilibili://` scheme 直接唤起已安装的 B 站 App。
  Future<void> _openBilibiliApp() async {
    final bvid = widget.bvid.trim();
    if (bvid.isEmpty) return;
    final uri = Uri.tryParse('bilibili://video/$bvid');
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未能拉起 B 站 App，可试试右上角“网页版播放”')),
      );
    }
  }

  Future<void> _switchRate(double rate) async {
    if (_loading) return;
    await _player.setRate(rate);
    if (!mounted) return;
    setState(() => _rate = rate);
  }

  Future<void> _selectSubtitle(int index) async {
    final result = _result;
    if (result == null) return;
    if (index == _selectedSubtitle) return;
    if (index < 0) {
      if (!mounted) return;
      setState(() {
        _selectedSubtitle = -1;
        _subtitles = const [];
      });
      return;
    }
    final subtitle = result.subtitles[index];
    if (subtitle.url.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _selectedSubtitle = index;
      _subtitles = const [];
    });
    await _loadSubtitles(result);
  }

  Future<void> _loadSubtitles(BilibiliPlayResult result) async {
    if (_selectedSubtitle < 0 || _selectedSubtitle >= result.subtitles.length) {
      if (mounted) {
        setState(() => _subtitles = const []);
      }
      return;
    }
    final subtitle = result.subtitles[_selectedSubtitle];
    if (subtitle.url.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(subtitle.url));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final rawBody = decoded is Map ? decoded['body'] : null;
      final items = <_BilibiliSubtitle>[];
      if (rawBody is List) {
        for (final item in rawBody) {
          if (item is! Map) continue;
          final from = double.tryParse((item['from'] ?? '').toString()) ?? 0;
          final to = double.tryParse((item['to'] ?? '').toString()) ?? 0;
          final content = (item['content'] ?? '').toString().trim();
          if (content.isEmpty) continue;
          items.add(_BilibiliSubtitle(from: from, to: to, content: content));
        }
      }
      if (!mounted) return;
      setState(() => _subtitles = List.unmodifiable(items));
    } catch (_) {
      if (!mounted) return;
      setState(() => _subtitles = const []);
    }
  }

  _BilibiliSubtitle? _findSubtitle(int milliseconds) {
    for (final subtitle in _subtitles) {
      if (milliseconds >= (subtitle.from * 1000).round() &&
          milliseconds <= (subtitle.to * 1000).round()) {
        return subtitle;
      }
    }
    return null;
  }

  Future<void> _handleDoubleTap() async {
    final details = _doubleTapDetails;
    if (details == null) return;
    final width = MediaQuery.sizeOf(context).width;
    final dx = details.localPosition.dx;
    final position = _player.state.position;
    if (dx < width / 3) {
      await _player.seek(position - const Duration(seconds: 10));
      _showSnack('快退 10 秒');
    } else if (dx > width * 2 / 3) {
      await _player.seek(position + const Duration(seconds: 10));
      _showSnack('快进 10 秒');
    } else {
      await _player.playOrPause();
    }
  }

  Future<void> _handleVolumeDrag(double deltaY) async {
    final current = _player.state.volume;
    final next = (current - deltaY / 100).clamp(0.0, 1.0);
    await _player.setVolume(next);
  }

  /// Custom fullscreen route so the danmaku overlay stays visible in
  /// fullscreen (media_kit's native fullscreen only shows the video texture).
  Future<void> _enterFullscreen() async {
    final controller = _videoController;
    if (controller == null) return;
    final video = _result?.video;
    final portrait =
        video != null && video.width > 0 && video.height > video.width;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DanmakuFullscreenPage(
          controller: controller,
          position: _player.stream.position,
          playing: _player.stream.playing,
          items: _danmakuItems,
          subtitles: _subtitles,
          danmakuEnabled: _danmakuEnabled,
          loadComments: _fetchCommentPage,
          loadReplies: _fetchReplyPage,
          portrait: portrait,
          videoState: _videoState,
          onLike: _toggleLike,
          onCoin: _toggleCoin,
          onFavorite: _toggleFavorite,
          onTriple: _triple,
          shareUrl: widget.contentUrl.isNotEmpty
              ? widget.contentUrl
              : 'https://www.bilibili.com/video/${widget.bvid}',
        ),
      ),
    );
  }

  Future<void> _switchQuality(BilibiliQuality quality) async {
    if (_loading || _selectedQn == quality.qn) return;
    await _saveProgress();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _selectedQn = quality.qn;
      _switchingStream = true;
      _error = null;
    });
    try {
      final api = _api;
      if (api == null) return;
      final result = await api.playUrl(
        bvid: widget.bvid,
        cid: _selectedCid,
        qn: _selectedQn,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _switchingStream = false;
        if (_selectedQn == null ||
            !result.qualities.any((quality) => quality.qn == _selectedQn)) {
          final actualQn = result.video?.qn;
          _selectedQn =
              actualQn != null &&
                  result.qualities.any((quality) => quality.qn == actualQn)
              ? actualQn
              : (result.qualities.isNotEmpty
                    ? result.qualities.first.qn
                    : null);
        }
      });
      await _openPlayer(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _switchingStream = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _switchPage(BilibiliPlayPage page) async {
    if (_loading || _switchingStream || _selectedCid == page.cid) return;
    await _saveProgress();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _selectedCid = page.cid;
      _switchingStream = true;
      _error = null;
    });
    try {
      await _load();
    } finally {
      if (mounted) setState(() => _switchingStream = false);
    }
  }

  /// Chooses the quality to show in the compact dropdown. Keeps the user's
  /// explicit selection when it still exists in the current play response,
  /// otherwise falls back to the stream's actual qn or the first option.
  int? _selectedQualityQn(BilibiliPlayResult result) {
    if (result.qualities.isEmpty) return null;
    if (_selectedQn != null &&
        result.qualities.any((quality) => quality.qn == _selectedQn)) {
      return _selectedQn;
    }
    final actualQn = result.video?.qn;
    if (actualQn != null && result.qualities.any((q) => q.qn == actualQn)) {
      return actualQn;
    }
    return result.qualities.first.qn;
  }

  @override
  Widget build(BuildContext context) {
    final theme = bilibiliVideoTheme(Theme.of(context));
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.black,
          systemNavigationBarColor: theme.colorScheme.surface,
          systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            bottom: false,
            child: Material(
              color: theme.colorScheme.surface,
              child: Builder(
                builder: (context) {
                  if (_loading || _error != null) {
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: _error != null
                              ? _errorPanel(context)
                              : const Center(
                                  child: CircularProgressIndicator(),
                                ),
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          child: IconButton(
                            tooltip: '返回',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  return _playerBody(
                    context,
                    _result!,
                    keyboardVisible: keyboardVisible,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorPanel(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_outlined,
              color: colors.onSurfaceVariant,
              size: 44,
            ),
            const SizedBox(height: 16),
            const Text('视频暂时无法播放', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    unawaited(_load());
                  },
                  child: const Text('重新加载'),
                ),
                FilledButton.tonal(
                  onPressed: _openLogin,
                  child: const Text('登录 B 站'),
                ),
                FilledButton(
                  onPressed: _openWebViewFallback,
                  child: const Text('网页版播放'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerBody(
    BuildContext context,
    BilibiliPlayResult result, {
    required bool keyboardVisible,
  }) {
    return BilibiliVideoLayout(
      aspectRatio: _aspectRatio(result.video),
      keyboardVisible: keyboardVisible,
      commentTotal: _commentTotal,
      danmakuEnabled: _danmakuEnabled,
      onToggleDanmaku: _toggleDanmaku,
      onDanmakuSettings: _openDanmakuSettings,
      player: _playerSurface(),
      introduction: BilibiliVideoIntroduction(
        title: _displayTitle,
        bvid: widget.bvid,
        creator: _up == null ? null : _upBar(_up!),
        description: _videoDescription,
        viewCount: _viewCount,
        danmakuCount: _danmakuCount,
        publishedAt: _publishedAt,
        recommendationReason: widget.recommendationReason,
        actions: _videoActions(),
        pages: result.pages,
        selectedCid: _selectedCid ?? result.cid,
        switchingPage: _loading || _switchingStream,
        onSelectPage: (page) => unawaited(_switchPage(page)),
        related: _related,
        relatedLoading: _relatedLoading,
        relatedFailed: _relatedFailed,
        onRetryRelated: _loadRelated,
        onOpenRelated: (item) => unawaited(_openRelated(item)),
      ),
      comments: _commentsBody(context),
    );
  }

  Widget _playerSurface() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_videoController != null)
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onDoubleTapDown: (details) => _doubleTapDetails = details,
            onDoubleTap: _handleDoubleTap,
            onVerticalDragUpdate: (details) =>
                unawaited(_handleVolumeDrag(details.delta.dy)),
            child: MaterialVideoControlsTheme(
              normal: MaterialVideoControlsThemeData(
                bottomButtonBar: [
                  const Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MaterialPositionIndicator(),
                    ),
                  ),
                  MaterialCustomButton(
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () => unawaited(_openPlayerSettings()),
                  ),
                  // Use only our route so fullscreen keeps danmaku and exits with one pop.
                  MaterialCustomButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                    onPressed: () => unawaited(_enterFullscreen()),
                  ),
                ],
              ),
              fullscreen: const MaterialVideoControlsThemeData(),
              child: Video(controller: _videoController!),
            ),
          ),
        if (_switchingStream || _videoController == null)
          const Center(child: CircularProgressIndicator(color: Colors.white70)),
        IgnorePointer(
          child: DanmakuOverlay(
            position: _player.stream.position,
            playing: _player.stream.playing,
            items: _danmakuItems,
            enabled: _danmakuEnabled,
          ),
        ),
        if (_selectedSubtitle >= 0 && _subtitles.isNotEmpty)
          Positioned(
            left: 16,
            right: 16,
            bottom: 56,
            child: IgnorePointer(
              child: StreamBuilder<Duration>(
                stream: _player.stream.position,
                builder: (context, snapshot) {
                  final item = _findSubtitle(
                    (snapshot.data ?? Duration.zero).inMilliseconds,
                  );
                  if (item == null) return const SizedBox.shrink();
                  return Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      color: Colors.black.withValues(alpha: 0.65),
                      child: Text(
                        item.content,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          height: 1.3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: '返回',
                  color: Colors.white,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                ),
                IconButton(
                  tooltip: '更多',
                  color: Colors.white,
                  onPressed: _showMoreActions,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _commentsBody(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification.depth == 0 &&
                  notification.metrics.axis == Axis.vertical &&
                  notification.metrics.extentAfter < 240 &&
                  !_commentsMoreFailed) {
                unawaited(_loadMoreComments());
              }
              return false;
            },
            child: CustomScrollView(
              key: const PageStorageKey('bilibili-comments'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        Text(
                          '全部评论${_commentTotal > 0 ? '  $_commentTotal' : ''}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '按热度',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_commentsLoading && _comments.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_commentsFailed && _comments.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: TextButton(
                        onPressed: _loadComments,
                        child: const Text('评论加载失败，点击重试'),
                      ),
                    ),
                  )
                else if (_comments.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Text(
                        '还没有评论，来说两句吧',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: _comments.length,
                      itemBuilder: (context, index) => BilibiliCommentTile(
                        comment: _comments[index],
                        onOpenReplies: () =>
                            _openCommentReplies(_comments[index]),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: _commentsLoadingMore
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : _commentHasMore
                            ? TextButton(
                                onPressed: _loadMoreComments,
                                child: Text(
                                  _commentsMoreFailed ? '加载失败，点击重试' : '加载更多评论',
                                ),
                              )
                            : Text(
                                '已经到底啦',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: BilibiliCommentComposer(
              hint: '发一条友善的评论…',
              onSubmit: (text) => _publishComment(text),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openRelated(BilibiliRelatedVideo item) async {
    final wasPlaying = _player.state.playing;
    await _player.pause();
    if (!mounted) return;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NativeBilibiliVideoPage(
            bvid: item.bvid,
            title: item.title,
            contentUrl: 'https://www.bilibili.com/video/${item.bvid}',
            coverUrl: item.coverUrl,
          ),
        ),
      );
    } finally {
      if (mounted && wasPlaying) await _player.play();
    }
  }

  double _aspectRatio(BilibiliPlayMedia? video) {
    if (video != null && video.width > 0 && video.height > 0) {
      return video.width / video.height;
    }
    return 16 / 9;
  }

  Future<void> _openCommentReplies(BilibiliComment root) async {
    if (root.rpid == 0 || (_commentDirect == null && _api == null)) return;
    await _showCommentSheet(
      context,
      (context, scrollController) => _CommentRepliesSheet(
        root: root,
        scrollController: scrollController,
        loadPage: (pn) => _fetchReplyPage(root.rpid, pn),
        onPost: (text, parent) =>
            _publishComment(text, root: root.rpid, parent: parent),
      ),
    );
  }

  /// Publishes a comment (top-level when [root] is null, otherwise a reply in
  /// the thread) via the backend. Returns an error message on failure, or
  /// null on success; top-level success refreshes the comment page.
  /// rpid of the last successfully published top-level comment (or reply).
  /// Exposed for the real-environment E2E to clean up after itself, since
  /// Bilibili's list endpoints do not surface freshly published comments.
  int? lastPostedRpid;

  Future<String?> _publishComment(String text, {int? root, int? parent}) async {
    final api = _api;
    if (api == null) return '后端未就绪';
    try {
      final result = await api.postComment(
        bvid: widget.bvid,
        message: text,
        root: root,
        parent: parent,
      );
      lastPostedRpid = int.tryParse('${result['rpid'] ?? ''}');
      if (!mounted) return null;
      if (root == null) {
        final page = await _fetchCommentPage(1);
        if (!mounted) return null;
        setState(() {
          _comments = page.items;
          _commentTotal = page.total;
          _commentHasMore = page.hasMore;
          _commentNextPn = page.page + 1;
        });
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('评论已发布')));
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 401) return '请先登录 B 站账号';
      return '评论发布失败：${e.message}';
    } catch (_) {
      return '评论发布失败，请稍后重试';
    }
  }
}

/// Bilibili's danmaku endpoint returns a deflate-compressed body without a
/// Content-Encoding header, so the HTTP client cannot auto-decompress it.
/// Returns the bytes unchanged when they already look like XML.
List<int> inflateDanmakuBytes(List<int> bytes) {
  if (bytes.isEmpty || bytes[0] == 0x3C) return bytes; // already XML
  for (final raw in const [true, false]) {
    try {
      final decoded = ZLibDecoder(raw: raw).convert(bytes);
      if (decoded.isNotEmpty && decoded[0] == 0x3C) return decoded;
    } catch (_) {
      // Try the next decoder, then give up and return the original bytes.
    }
  }
  return bytes;
}

Future<void> _showCommentSheet(
  BuildContext context,
  Widget Function(BuildContext, ScrollController) builder,
) {
  final theme = bilibiliVideoTheme(Theme.of(context));
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: theme.colorScheme.surface,
    builder: (context) => Theme(
      data: theme,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            expand: false,
            builder: builder,
          ),
        ),
      ),
    ),
  );
}

/// Fetches one 1-based page of top-level comments.
typedef _CommentPageLoader = Future<BilibiliCommentPage> Function(int pn);

/// Fetches one 1-based page of the reply thread under [root].
typedef _ReplyPageLoader =
    Future<BilibiliCommentPage> Function(int root, int pn);

/// Fullscreen playback route that keeps the danmaku overlay visible.
class _DanmakuFullscreenPage extends StatefulWidget {
  const _DanmakuFullscreenPage({
    required this.controller,
    required this.position,
    required this.playing,
    required this.items,
    required this.subtitles,
    required this.danmakuEnabled,
    required this.loadComments,
    required this.loadReplies,
    required this.portrait,
    required this.videoState,
    required this.onLike,
    required this.onCoin,
    required this.onFavorite,
    required this.onTriple,
    required this.shareUrl,
  });

  final VideoController controller;
  final Stream<Duration> position;
  final Stream<bool>? playing;
  final List<DanmakuItem> items;
  final List<_BilibiliSubtitle> subtitles;
  final bool danmakuEnabled;
  final _CommentPageLoader loadComments;
  final _ReplyPageLoader loadReplies;

  /// Portrait (竖屏) videos stay upright in fullscreen instead of being
  /// letterboxed inside a forced-landscape screen.
  final bool portrait;
  final BilibiliVideoState? videoState;
  final VoidCallback onLike;
  final VoidCallback onCoin;
  final VoidCallback onFavorite;
  final VoidCallback onTriple;
  final String shareUrl;

  @override
  State<_DanmakuFullscreenPage> createState() => _DanmakuFullscreenPageState();
}

class _DanmakuFullscreenPageState extends State<_DanmakuFullscreenPage> {
  late bool _playing = widget.controller.player.state.playing;
  bool _showPlaybackIcon = false;
  bool _controlsVisible = true;
  Timer? _iconTimer;
  Timer? _controlsTimer;
  double _brightness = 1.0;
  double _volume = 0.5;
  bool _adjustActive = false;
  bool _adjustIsVolume = false;
  double _adjustStartValue = 0.0;
  double _adjustStartDy = 0.0;
  String? _adjustHint;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(
      widget.portrait
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
    _startControlsTimer();
    unawaited(_loadSystemValues());
  }

  Future<void> _loadSystemValues() async {
    try {
      final brightness = await ScreenBrightness().application;
      if (mounted) {
        setState(() => _brightness = brightness);
      }
    } catch (_) {}
    try {
      final volume = await VolumeController.instance.getVolume();
      if (mounted) {
        setState(() => _volume = volume.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _iconTimer?.cancel();
    _controlsTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _startControlsTimer();
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _startAdjust(DragStartDetails details) {
    final size = MediaQuery.sizeOf(context);
    final isLeft = details.globalPosition.dx < size.width / 2;
    _adjustActive = true;
    _adjustIsVolume = !isLeft;
    _adjustStartValue = isLeft ? _brightness : _volume;
    _adjustStartDy = details.globalPosition.dy;
    _adjustHint = isLeft ? '亮度' : '音量';
    _showControls();
    if (mounted) setState(() {});
  }

  void _updateAdjust(DragUpdateDetails details) {
    if (!_adjustActive) return;
    final size = MediaQuery.sizeOf(context);
    final dyDelta = details.globalPosition.dy - _adjustStartDy;
    final delta = -dyDelta / size.height * 1.5;
    final value = (_adjustStartValue + delta).clamp(0.0, 1.0);
    if (_adjustIsVolume) {
      _volume = value;
      VolumeController.instance.setVolume(value);
    } else {
      _brightness = value;
      ScreenBrightness().setApplicationScreenBrightness(value);
    }
    if (mounted) setState(() {});
  }

  void _endAdjust(DragEndDetails details) {
    _adjustActive = false;
    _adjustHint = null;
    if (mounted) setState(() {});
  }

  String _formatFullscreenDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _seekFraction(double value) async {
    final duration = widget.controller.player.state.duration;
    if (duration.inMilliseconds <= 0) return;
    await widget.controller.player.seek(
      Duration(milliseconds: (duration.inMilliseconds * value).round()),
    );
    if (mounted) _showControls();
  }

  Future<void> _togglePlayback() async {
    await widget.controller.player.playOrPause();
    if (!mounted) return;
    setState(() {
      _playing = !_playing;
      _showPlaybackIcon = true;
    });
    _showControls();
    _iconTimer?.cancel();
    _iconTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showPlaybackIcon = false);
    });
  }

  Future<void> _share() async {
    await SharePlus.instance.share(
      ShareParams(
        title: '分享 B 站视频',
        text: widget.shareUrl,
        subject: widget.shareUrl,
      ),
    );
  }

  _BilibiliSubtitle? _currentSubtitle(Duration position) {
    final milliseconds = position.inMilliseconds;
    for (final subtitle in widget.subtitles) {
      if (milliseconds >= (subtitle.from * 1000).round() &&
          milliseconds <= (subtitle.to * 1000).round()) {
        return subtitle;
      }
    }
    return null;
  }

  Future<void> _openComments() async {
    await _showCommentSheet(
      context,
      (context, scrollController) => _CommentsSheet(
        loadComments: widget.loadComments,
        loadReplies: widget.loadReplies,
        scrollController: scrollController,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            onVerticalDragStart: _startAdjust,
            onVerticalDragUpdate: _updateAdjust,
            onVerticalDragEnd: _endAdjust,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(controller: widget.controller, controls: NoVideoControls),
                if (_showPlaybackIcon)
                  Center(
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 72,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                if (_adjustActive && _adjustHint != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _adjustIsVolume
                                ? Icons.volume_up_rounded
                                : Icons.brightness_6_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$_adjustHint ${((_adjustIsVolume ? _volume : _brightness) * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IgnorePointer(
            child: DanmakuOverlay(
              position: widget.position,
              playing: widget.playing,
              items: widget.items,
              enabled: widget.danmakuEnabled,
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: IconButton(
                  tooltip: '退出全屏',
                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: IconButton(
                  tooltip: '查看评论',
                  icon: const Icon(
                    Icons.mode_comment_outlined,
                    color: Colors.white,
                  ),
                  onPressed: _openComments,
                ),
              ),
            ),
          ),
          if (widget.subtitles.isNotEmpty)
            Positioned(
              left: 14,
              right: 14,
              bottom: 76,
              child: IgnorePointer(
                child: StreamBuilder<Duration>(
                  stream: widget.position,
                  builder: (context, snapshot) {
                    final subtitle = _currentSubtitle(
                      snapshot.data ?? Duration.zero,
                    );
                    if (subtitle == null) return const SizedBox.shrink();
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          subtitle.content,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(blurRadius: 4, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: _playing ? '暂停' : '播放',
                              onPressed: () => _togglePlayback(),
                              icon: Icon(
                                _playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white,
                              ),
                            ),
                            Expanded(
                              child: StreamBuilder<Duration>(
                                stream:
                                    widget.controller.player.stream.duration,
                                builder: (context, durationSnapshot) {
                                  final duration =
                                      durationSnapshot.data ?? Duration.zero;
                                  return StreamBuilder<Duration>(
                                    stream: widget.position,
                                    builder: (context, positionSnapshot) {
                                      final position =
                                          positionSnapshot.data ??
                                          Duration.zero;
                                      final progress =
                                          duration.inMilliseconds > 0
                                          ? (position.inMilliseconds /
                                                    duration.inMilliseconds)
                                                .clamp(0.0, 1.0)
                                          : 0.0;
                                      return SliderTheme(
                                        data: const SliderThemeData(
                                          trackHeight: 2,
                                          thumbShape: RoundSliderThumbShape(
                                            enabledThumbRadius: 5,
                                          ),
                                          overlayShape: RoundSliderOverlayShape(
                                            overlayRadius: 12,
                                          ),
                                          activeTrackColor: Color(0xFFFB7299),
                                          inactiveTrackColor: Colors.white24,
                                          thumbColor: Color(0xFFFB7299),
                                        ),
                                        child: Slider(
                                          value: progress,
                                          onChanged: (value) =>
                                              _seekFraction(value),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: StreamBuilder<Duration>(
                                stream: widget.position,
                                builder: (context, snapshot) {
                                  final position =
                                      snapshot.data ?? Duration.zero;
                                  final duration =
                                      widget.controller.player.state.duration;
                                  return Text(
                                    '${_formatFullscreenDuration(position)} / ${_formatFullscreenDuration(duration)}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _FullscreenActionButton(
                              icon: (widget.videoState?.like ?? false)
                                  ? Icons.thumb_up_rounded
                                  : Icons.thumb_up_outlined,
                              label: '点赞',
                              active: widget.videoState?.like ?? false,
                              count: widget.videoState?.likeCount ?? 0,
                              onTap: widget.onLike,
                            ),
                            _FullscreenActionButton(
                              icon: Icons.monetization_on_outlined,
                              label: '投币',
                              count: widget.videoState?.coinCount ?? 0,
                              onTap: widget.onCoin,
                            ),
                            _FullscreenActionButton(
                              icon: (widget.videoState?.favorite ?? false)
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              label: '收藏',
                              active: widget.videoState?.favorite ?? false,
                              count: widget.videoState?.favoriteCount ?? 0,
                              onTap: widget.onFavorite,
                            ),
                            _FullscreenActionButton(
                              icon: Icons.auto_awesome_rounded,
                              label: '三连',
                              onTap: widget.onTriple,
                            ),
                            _FullscreenActionButton(
                              icon: Icons.share_outlined,
                              label: '分享',
                              onTap: _share,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _compactCount(int value) {
  if (value >= 100000000) {
    return '${(value / 100000000).toStringAsFixed(value % 100000000 == 0 ? 0 : 1)}亿';
  }
  if (value >= 10000) {
    return '${(value / 10000).toStringAsFixed(value % 10000 == 0 ? 0 : 1)}万';
  }
  return '$value';
}

class _FullscreenActionButton extends StatelessWidget {
  const _FullscreenActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.count = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFFFB7299) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              count > 0 ? '${_compactCount(count)} $label' : label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BilibiliSubtitle {
  const _BilibiliSubtitle({
    required this.from,
    required this.to,
    required this.content,
  });

  final double from;
  final double to;
  final String content;
}

/// Bottom sheet listing top-level comments, paginated through the same
/// comment loader as the player page. Used from the fullscreen player, where
/// the page's own comment section is not reachable.
class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.loadComments,
    required this.loadReplies,
    required this.scrollController,
  });

  final _CommentPageLoader loadComments;
  final _ReplyPageLoader loadReplies;
  final ScrollController scrollController;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  List<BilibiliComment> _comments = const [];
  int _total = 0;
  int _nextPn = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loadingMore) return;
    setState(() {
      if (!_loading) _loadingMore = true;
      _failed = false;
    });
    try {
      final page = await widget.loadComments(_nextPn);
      if (!mounted) return;
      setState(() {
        _comments = _NativeBilibiliVideoPageState._mergeComments(
          _comments,
          page.items,
        );
        _total = page.total;
        _hasMore = page.hasMore;
        _nextPn = page.page + 1;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failed = true;
      });
    }
  }

  Future<void> _openReplies(BilibiliComment root) async {
    if (root.rpid == 0) return;
    await _showCommentSheet(
      context,
      (context, scrollController) => _CommentRepliesSheet(
        root: root,
        scrollController: scrollController,
        loadPage: (pn) => widget.loadReplies(root.rpid, pn),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _total > 0 ? '评论 $_total' : '评论',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: Icon(Icons.close, color: colors.onSurfaceVariant),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (_comments.isEmpty && !_failed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '暂无评论',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    for (final comment in _comments)
                      BilibiliCommentTile(
                        comment: comment,
                        onOpenReplies: () => _openReplies(comment),
                      ),
                    if (_failed)
                      Center(
                        child: TextButton(
                          onPressed: _load,
                          child: const Text('加载失败，点击重试'),
                        ),
                      )
                    else if (_hasMore || _loadingMore)
                      Center(
                        child: _loadingMore
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: _load,
                                child: const Text('加载更多评论'),
                              ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Bottom sheet that shows the full reply thread of a top-level comment,
/// paginated through the page's reply loader.
class _CommentRepliesSheet extends StatefulWidget {
  const _CommentRepliesSheet({
    required this.root,
    required this.scrollController,
    required this.loadPage,
    this.onPost,
  });

  final BilibiliComment root;
  final ScrollController scrollController;

  /// Fetches one 1-based page of the reply thread.
  final Future<BilibiliCommentPage> Function(int pn) loadPage;

  /// Publishes a reply; [parent] is the rpid being answered (root rpid when
  /// answering the root comment). Returns an error message or null. When
  /// null the sheet stays read-only (fullscreen comments).
  final Future<String?> Function(String text, int parent)? onPost;

  @override
  State<_CommentRepliesSheet> createState() => _CommentRepliesSheetState();
}

class _CommentRepliesSheetState extends State<_CommentRepliesSheet> {
  List<BilibiliComment> _replies = const [];
  int _total = 0;
  int _nextPn = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  bool _failed = false;
  BilibiliComment? _replyTarget;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _reloadFirstPage() async {
    setState(() {
      _replies = const [];
      _nextPn = 1;
      _loading = true;
      _failed = false;
    });
    await _load();
  }

  Future<String?> _postReply(String text, {int? parent}) async {
    final target = _replyTarget;
    final effectiveParent = parent ?? target?.rpid ?? widget.root.rpid;
    final error = await widget.onPost!(text, effectiveParent);
    if (!mounted) return error;
    if (error != null) return error;
    setState(() => _replyTarget = null);
    await _reloadFirstPage();
    return null;
  }

  Future<void> _load() async {
    if (_loadingMore) return;
    setState(() {
      if (!_loading) _loadingMore = true;
      _failed = false;
    });
    try {
      final page = await widget.loadPage(_nextPn);
      if (!mounted) return;
      setState(() {
        final seen = _replies.map(_replyKey).toSet();
        _replies = [
          ..._replies,
          ...page.items.where((reply) => seen.add(_replyKey(reply))),
        ];
        _total = page.total;
        _hasMore = page.hasMore;
        _nextPn = page.page + 1;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _failed = true;
      });
    }
  }

  static String _replyKey(BilibiliComment reply) => reply.rpid != 0
      ? 'r${reply.rpid}'
      : 'm${reply.mid}:${reply.message.hashCode}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final root = widget.root;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _total > 0 ? '回复 $_total' : '回复',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: Icon(Icons.close, color: colors.onSurfaceVariant),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _sheetComment(root, isRoot: true),
                    Divider(color: colors.outlineVariant, height: 20),
                    if (_replies.isEmpty && !_failed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '暂无回复',
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    for (final reply in _replies) _sheetComment(reply),
                    if (_failed)
                      Center(
                        child: TextButton(
                          onPressed: _load,
                          child: const Text('加载失败，点击重试'),
                        ),
                      )
                    else if (_hasMore || _loadingMore)
                      Center(
                        child: _loadingMore
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : TextButton(
                                onPressed: _load,
                                child: const Text('加载更多回复'),
                              ),
                      ),
                  ],
                ),
        ),
        if (widget.onPost != null)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: BilibiliCommentComposer(
                hint: _replyTarget == null
                    ? '回复 @${widget.root.uname}…'
                    : '回复 @${_replyTarget!.uname}…',
                onSubmit: (text) => _postReply(text),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sheetComment(BilibiliComment comment, {bool isRoot = false}) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BilibiliAvatar(
            url: comment.avatarUrl,
            name: comment.uname,
            size: isRoot ? 38 : 30,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.uname,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: isRoot ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comment.message,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${comment.likeCount} 赞',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (widget.onPost != null)
                      TextButton(
                        onPressed: () => setState(() => _replyTarget = comment),
                        child: Text(
                          '回复',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
