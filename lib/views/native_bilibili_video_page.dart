import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/bilibili_api.dart';
import '../api/bilibili_comment_api.dart';
import '../api/client.dart';
import '../models/bilibili_interaction.dart';
import '../models/bilibili_play.dart';
import '../widgets/cover_image.dart';
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

class _NativeBilibiliVideoPageState extends State<NativeBilibiliVideoPage>
    with SingleTickerProviderStateMixin {
  late final Player _player = Player();
  VideoController? _videoController;
  BilibiliApi? _api;
  BilibiliPlayResult? _result;
  bool _loading = true;
  String? _error;
  bool _loadStarted = false;
  int? _selectedQn;
  int? _selectedCid;
  List<DanmakuItem> _danmakuItems = const [];
  bool _danmakuEnabled = true;
  List<String> _danmakuBlockWords = const [];
  double _rate = 1.0;
  int _selectedSubtitle = -1;
  TapDownDetails? _doubleTapDetails;
  BilibiliVideoState? _videoState;
  List<BilibiliComment> _comments = const [];
  int _commentTotal = 0;
  int _commentNextPn = 1;
  bool _commentHasMore = false;
  bool _commentsLoadingMore = false;
  BilibiliCommentApi? _commentDirect;
  bool _directSessionTried = false;
  int? _commentAid;
  List<BilibiliRelatedVideo> _related = const [];
  String _videoDescription = '';
  bool _playerCompact = false;

  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

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

  Future<void> _loadInteractions() async {
    final api = _api;
    if (api == null) return;
    // Each channel is independent: a slow/failed comment fetch must not
    // prevent the like/favorite state from rendering.
    try {
      final state = await api.videoRelation(bvid: widget.bvid);
      if (mounted) setState(() => _videoState = state);
    } catch (_) {}
    try {
      final commentPage = await _fetchCommentPage(1);
      if (!mounted) return;
      setState(() {
        _comments = commentPage.items;
        _commentTotal = commentPage.total;
        _commentHasMore = commentPage.hasMore;
        _commentNextPn = commentPage.page + 1;
      });
    } catch (_) {}
    try {
      final related = await api.relatedVideos(bvid: widget.bvid);
      if (mounted) setState(() => _related = related);
    } catch (_) {}
    try {
      final direct = _commentDirect;
      if (direct != null) {
        final info = await direct.videoInfo(widget.bvid);
        final desc = info['desc']?.toString().trim() ?? '';
        if (desc.isNotEmpty && mounted) {
          setState(() => _videoDescription = desc);
        }
      }
    } catch (_) {}
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
    if (!_commentHasMore || _commentsLoadingMore) return;
    setState(() => _commentsLoadingMore = true);
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
      setState(() => _commentsLoadingMore = false);
      _showSnack('评论加载失败，请重试');
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
      setState(() => _videoState = next);
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
      final state = await api.videoRelation(bvid: widget.bvid);
      if (!mounted) return;
      setState(() => _videoState = state);
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
      setState(() => _videoState = next);
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
      setState(() => _videoState = next);
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
      setState(() => _videoState = state);
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

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool active = false,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: active ? const Color(0xFFFB7299) : Colors.white70,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active ? const Color(0xFFFB7299) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// PiliPlus-style separate video/audio URL joining. If the backend only
  /// returns one stream, it falls back to that single URL.
  static String _mediaUri(String videoUrl, String audioUrl) {
    if (audioUrl.isEmpty) return videoUrl;
    return 'edl://!no_chapters;'
        '%${videoUrl.length}%$videoUrl;'
        '!new_stream;!no_chapters;'
        '%${audioUrl.length}%$audioUrl';
  }

  Future<void> _openWebViewFallback() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BilibiliVideoPage(
          bvid: widget.bvid,
          title: widget.title,
          contentUrl: widget.contentUrl,
          coverUrl: widget.coverUrl,
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
      await _load();
    }
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
        const SnackBar(content: Text('未能拉起 B 站 App，可试试右上角“评论/完整页”')),
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
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      final subtitle = result.subtitles[index];
      if (subtitle.url.isEmpty) return;
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          subtitle.url,
          title: subtitle.name,
          language: subtitle.lan,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _selectedSubtitle = index);
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
          danmakuEnabled: _danmakuEnabled,
          loadComments: _fetchCommentPage,
          loadReplies: _fetchReplyPage,
          portrait: portrait,
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
      _loading = true;
      _error = null;
    });
    await _load();
  }

  Future<void> _switchPage(BilibiliPlayPage page) async {
    if (_loading || _selectedCid == page.cid) return;
    await _saveProgress();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _selectedCid = page.cid;
      _loading = true;
      _error = null;
    });
    await _load();
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

  Widget _playerOptionDropdown<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(width: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              dropdownColor: const Color(0xFF1B1B1B),
              borderRadius: BorderRadius.circular(10),
              icon: const Icon(
                Icons.arrow_drop_down_rounded,
                color: Colors.white70,
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _videoInfoBlock(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white70),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title.isNotEmpty ? widget.title : 'B站视频',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: '评论/完整页',
            onPressed: _openWebViewFallback,
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: '用B站App打开',
            onPressed: _openBilibiliApp,
            icon: const Icon(Icons.ondemand_video_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _error != null
          ? _errorPanel(context)
          : _playerBody(context, result!, theme),
    );
  }

  Widget _errorPanel(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white70,
              size: 44,
            ),
            const SizedBox(height: 12),
            const Text('原生播放器暂时无法拉取资源', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 6),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonal(onPressed: _load, child: const Text('重新加载')),
                FilledButton.tonal(
                  onPressed: _openLogin,
                  child: const Text('扫码登录'),
                ),
                FilledButton(
                  onPressed: _openWebViewFallback,
                  child: const Text('使用内置网页播放'),
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
    BilibiliPlayResult result,
    ThemeData theme,
  ) {
    final video = result.video;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPortrait =
            video != null && video.width > 0 && video.height > video.width;
        final useCompact = _playerCompact && isPortrait;
        // 展开态：竖屏视频仍要控制高度，避免一开始就把评论区挤出屏幕。
        final maxPlayerHeight = constraints.maxHeight * 0.6;
        final naturalHeight = constraints.maxWidth / _aspectRatio(video);
        final expandedHeight = naturalHeight > maxPlayerHeight
            ? maxPlayerHeight
            : naturalHeight;
        // 紧凑态：切换到 16:9 的迷你播放器高度，把更多空间留给下方内容。
        final compactHeight = constraints.maxWidth * 9 / 16;
        final aspectRatio = useCompact ? 16 / 9 : _aspectRatio(video);
        final playerHeight = useCompact ? compactHeight : expandedHeight;
        return Column(
          children: [
            SizedBox(
              width: constraints.maxWidth,
              height: playerHeight,
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _videoController == null
                          ? const ColoredBox(color: Colors.black)
                          : GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onDoubleTapDown: (details) {
                                _doubleTapDetails = details;
                              },
                              onDoubleTap: _handleDoubleTap,
                              onVerticalDragUpdate: (details) {
                                unawaited(_handleVolumeDrag(details.delta.dy));
                              },
                              // media_kit's default fullscreen button pushes
                              // its own fullscreen route IN ADDITION to
                              // `onEnterFullscreen`, stacking two fullscreen
                              // pages (exit needs two pops). Replace it with
                              // a button that only opens the custom route.
                              child: MaterialVideoControlsTheme(
                                normal: MaterialVideoControlsThemeData(
                                  bottomButtonBar: [
                                    const MaterialPositionIndicator(),
                                    const Spacer(),
                                    MaterialCustomButton(
                                      icon: const Icon(Icons.fullscreen),
                                      onPressed: () =>
                                          unawaited(_enterFullscreen()),
                                    ),
                                  ],
                                ),
                                fullscreen:
                                    const MaterialVideoControlsThemeData(),
                                child: Video(controller: _videoController!),
                              ),
                            ),
                      IgnorePointer(
                        child: DanmakuOverlay(
                          position: _player.stream.position,
                          playing: _player.stream.playing,
                          items: _danmakuItems,
                          enabled: _danmakuEnabled,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _actionButton(
                    icon: (_videoState?.like ?? false)
                        ? Icons.thumb_up_rounded
                        : Icons.thumb_up_outlined,
                    label: '点赞',
                    active: _videoState?.like ?? false,
                    onPressed: _toggleLike,
                  ),
                  _actionButton(
                    icon: Icons.monetization_on_outlined,
                    label: '投币',
                    onPressed: _toggleCoin,
                  ),
                  _actionButton(
                    icon: (_videoState?.favorite ?? false)
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    label: '收藏',
                    active: _videoState?.favorite ?? false,
                    onPressed: _toggleFavorite,
                  ),
                  _actionButton(
                    icon: (_videoState?.watchLater ?? false)
                        ? Icons.watch_later_rounded
                        : Icons.watch_later_outlined,
                    label: '稍后',
                    active: _videoState?.watchLater ?? false,
                    onPressed: _toggleWatchLater,
                  ),
                  _actionButton(
                    icon: Icons.auto_awesome_rounded,
                    label: '三连',
                    onPressed: _triple,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: Colors.white,
                    onTap: (_) {
                      if (!_playerCompact) {
                        setState(() => _playerCompact = true);
                      }
                    },
                    tabs: const [
                      Tab(text: '简介'),
                      Tab(text: '评论'),
                    ],
                  ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        final compact = notification.metrics.pixels > 80;
                        if (_playerCompact != compact) {
                          setState(() => _playerCompact = compact);
                        }
                        return false;
                      },
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          // ── Tab 1: 简介（视频信息 + 相关推荐）──
                          SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title.isNotEmpty
                                      ? widget.title
                                      : 'B站视频',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (_videoDescription.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _videoInfoBlock(
                                    context,
                                    icon: Icons.subject_rounded,
                                    label: '简介',
                                    child: _ExpandableText(
                                      text: _videoDescription,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  ),
                                ],
                                if (widget.recommendationReason.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _videoInfoBlock(
                                    context,
                                    icon: Icons.lightbulb_outline_rounded,
                                    label: '推荐理由',
                                    child: _ExpandableText(
                                      text: widget.recommendationReason,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (result.qualities.isNotEmpty)
                                      _playerOptionDropdown<int>(
                                        label: '清晰度',
                                        value:
                                            _selectedQualityQn(result) ??
                                            result.qualities.first.qn,
                                        items: [
                                          for (final quality
                                              in result.qualities)
                                            DropdownMenuItem<int>(
                                              value: quality.qn,
                                              child: Text(quality.label),
                                            ),
                                        ],
                                        onChanged: _loading
                                            ? null
                                            : (qn) {
                                                if (qn == null) return;
                                                final quality = result.qualities
                                                    .firstWhere(
                                                      (item) => item.qn == qn,
                                                    );
                                                unawaited(
                                                  _switchQuality(quality),
                                                );
                                              },
                                      ),
                                    _playerOptionDropdown<double>(
                                      label: '倍速',
                                      value: _rate,
                                      items: [
                                        for (final rate in const [
                                          0.5,
                                          1.0,
                                          1.25,
                                          1.5,
                                          2.0,
                                        ])
                                          DropdownMenuItem<double>(
                                            value: rate,
                                            child: Text(
                                              rate == 1.0 ? '1.0x' : '${rate}x',
                                            ),
                                          ),
                                      ],
                                      onChanged: _loading
                                          ? null
                                          : (rate) {
                                              if (rate == null) return;
                                              unawaited(_switchRate(rate));
                                            },
                                    ),
                                    if (result.subtitles.isNotEmpty)
                                      _playerOptionDropdown<int>(
                                        label: '字幕',
                                        value: _selectedSubtitle,
                                        items: [
                                          const DropdownMenuItem<int>(
                                            value: -1,
                                            child: Text('关闭'),
                                          ),
                                          for (
                                            var i = 0;
                                            i < result.subtitles.length;
                                            i++
                                          )
                                            DropdownMenuItem<int>(
                                              value: i,
                                              child: Text(
                                                result.subtitles[i].name,
                                              ),
                                            ),
                                        ],
                                        onChanged: _loading
                                            ? null
                                            : (index) {
                                                if (index == null) return;
                                                unawaited(
                                                  _selectSubtitle(index),
                                                );
                                              },
                                      ),
                                    ActionChip(
                                      label: Text(
                                        _danmakuEnabled ? '弹幕：开' : '弹幕：关',
                                      ),
                                      labelStyle: const TextStyle(fontSize: 11),
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: _danmakuEnabled
                                          ? Colors.white24
                                          : null,
                                      onPressed: _openDanmakuSettings,
                                    ),
                                  ],
                                ),
                                if (result.pages.length > 1) ...[
                                  const SizedBox(height: 10),
                                  Text('分P', style: theme.textTheme.labelLarge),
                                  const SizedBox(height: 6),
                                  ...result.pages.map(
                                    (page) => ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      onTap: _loading
                                          ? null
                                          : () => _switchPage(page),
                                      leading: CircleAvatar(
                                        radius: 14,
                                        child: Text('${page.page}'),
                                      ),
                                      title: Text(
                                        page.part,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (_related.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Text(
                                    '相关视频',
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ..._related
                                      .take(8)
                                      .map(
                                        (item) => ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: SizedBox(
                                            width: 90,
                                            height: 56,
                                            child: CoverImage(
                                              url: item.coverUrl,
                                              width: 90,
                                              height: 56,
                                              borderRadius: 8,
                                            ),
                                          ),
                                          title: Text(
                                            item.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                          subtitle: Text(
                                            '${item.upName} · ${item.view} 播放',
                                            style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11,
                                            ),
                                          ),
                                          onTap: () => _openRelated(item),
                                        ),
                                      ),
                                ],
                              ],
                            ),
                          ),
                          // ── Tab 2: 评论 ──
                          Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    24,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_comments.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.mode_comment_outlined,
                                              color: Colors.white70,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _commentTotal > 0
                                                  ? '评论 $_commentTotal'
                                                  : '评论',
                                              style: theme.textTheme.labelLarge
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        ..._comments.map(
                                          (comment) => _CommentTile(
                                            comment: comment,
                                            onOpenReplies: () =>
                                                _openCommentReplies(comment),
                                          ),
                                        ),
                                        if (_commentHasMore ||
                                            _commentsLoadingMore)
                                          Center(
                                            child: _commentsLoadingMore
                                                ? const Padding(
                                                    padding: EdgeInsets.all(10),
                                                    child: SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                Colors.white70,
                                                          ),
                                                    ),
                                                  )
                                                : TextButton(
                                                    onPressed:
                                                        _loadMoreComments,
                                                    child: const Text('加载更多评论'),
                                                  ),
                                          ),
                                      ] else ...[
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 48,
                                          ),
                                          child: Center(
                                            child: Text(
                                              '还没有评论',
                                              style: TextStyle(
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              _CommentComposer(
                                hint: '发一条友善的评论…',
                                onSubmit: (text) => _publishComment(text),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openRelated(BilibiliRelatedVideo item) async {
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
  }

  double _aspectRatio(BilibiliPlayMedia? video) {
    if (video != null && video.width > 0 && video.height > 0) {
      return video.width / video.height;
    }
    return 16 / 9;
  }

  Future<void> _openCommentReplies(BilibiliComment root) async {
    if (root.rpid == 0 || (_commentDirect == null && _api == null)) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1B1B),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CommentRepliesSheet(
          root: root,
          scrollController: scrollController,
          loadPage: (pn) => _fetchReplyPage(root.rpid, pn),
          onPost: (text, parent) =>
              _publishComment(text, root: root.rpid, parent: parent),
        ),
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
    required this.danmakuEnabled,
    required this.loadComments,
    required this.loadReplies,
    required this.portrait,
  });

  final VideoController controller;
  final Stream<Duration> position;
  final Stream<bool>? playing;
  final List<DanmakuItem> items;
  final bool danmakuEnabled;
  final _CommentPageLoader loadComments;
  final _ReplyPageLoader loadReplies;

  /// Portrait (竖屏) videos stay upright in fullscreen instead of being
  /// letterboxed inside a forced-landscape screen.
  final bool portrait;

  @override
  State<_DanmakuFullscreenPage> createState() => _DanmakuFullscreenPageState();
}

class _DanmakuFullscreenPageState extends State<_DanmakuFullscreenPage> {
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
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  Future<void> _openComments() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1B1B),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CommentsSheet(
          loadComments: widget.loadComments,
          loadReplies: widget.loadReplies,
          scrollController: scrollController,
        ),
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
          Video(controller: widget.controller, controls: NoVideoControls),
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
            child: IconButton(
              tooltip: '退出全屏',
              icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: IconButton(
              tooltip: '查看评论',
              icon: const Icon(
                Icons.mode_comment_outlined,
                color: Colors.white,
              ),
              onPressed: _openComments,
            ),
          ),
        ],
      ),
    );
  }
}

/// One comment card: author, message, like count and a preview of the reply
/// thread. Shared by the player page's comment section and the fullscreen
/// comments sheet.
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onOpenReplies});

  final BilibiliComment comment;
  final VoidCallback onOpenReplies;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentAvatar(url: comment.avatarUrl, name: comment.uname, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  comment.uname,
                  style: const TextStyle(
                    color: Color(0xFFFB7299),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comment.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '👍 ${comment.likeCount}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                if (comment.replies.isNotEmpty || comment.replyCount > 0) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final reply in comment.replies)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _CommentAvatar(
                                  url: reply.avatarUrl,
                                  name: reply.uname,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${reply.uname}: ',
                                          style: const TextStyle(
                                            color: Color(0xFFFB7299),
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        TextSpan(
                                          text: reply.message,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (comment.replyCount > comment.replies.length)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onOpenReplies,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '共 ${comment.replyCount} 条回复 >',
                                style: const TextStyle(
                                  color: Color(0xFF6D9EEB),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small circular avatar for comment authors and replies.
class _CommentAvatar extends StatelessWidget {
  const _CommentAvatar({required this.url, required this.name, this.size = 32});

  final String url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final normalized = url.startsWith('//') ? 'https:$url' : url;
    if (normalized.isEmpty) {
      final trimmedName = name.trim();
      final initial = trimmedName.isEmpty ? '?' : trimmedName.substring(0, 1);
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.white12,
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white70,
            fontSize: size * 0.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: CoverImage(
          url: normalized,
          width: size,
          height: size,
          borderRadius: size / 2,
        ),
      ),
    );
  }
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1B1B1B),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CommentRepliesSheet(
          root: root,
          scrollController: scrollController,
          loadPage: (pn) => widget.loadReplies(root.rpid, pn),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _total > 0 ? '评论 $_total' : '评论',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                )
              : ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    if (_comments.isEmpty && !_failed)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '暂无评论',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    for (final comment in _comments)
                      _CommentTile(
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
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                )
              : ListView(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _sheetComment(root, isRoot: true),
                    const Divider(color: Colors.white12, height: 20),
                    if (_replies.isEmpty && !_failed)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            '暂无回复',
                            style: TextStyle(
                              color: Colors.white54,
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
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _CommentComposer(
              hint: _replyTarget == null
                  ? '回复 @${widget.root.uname}…'
                  : '回复 @${_replyTarget!.uname}…',
              onSubmit: (text) => _postReply(text),
            ),
          ),
      ],
    );
  }

  Widget _sheetComment(BilibiliComment comment, {bool isRoot = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentAvatar(
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
                    color: const Color(0xFFFB7299),
                    fontSize: 12,
                    fontWeight: isRoot ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  comment.message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '👍 ${comment.likeCount}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (widget.onPost != null)
                      GestureDetector(
                        onTap: () => setState(() => _replyTarget = comment),
                        child: const Text(
                          '回复',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
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

/// Compact comment input with a send button and inline error text.
class _CommentComposer extends StatefulWidget {
  const _CommentComposer({required this.hint, required this.onSubmit});

  final String hint;

  /// Sends the text; returns an error message on failure or null on success.
  final Future<String?> Function(String text) onSubmit;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_busy,
                maxLength: 1000,
                maxLines: 1,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: widget.hint,
                  hintStyle: const TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white10,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    tooltip: '发送',
                    onPressed: _submit,
                    icon: const Icon(Icons.send_rounded, size: 18),
                  ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

/// 可展开/收起的文本块：默认最多显示 2 行，长文本可展开看全文。
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 2,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = painter.didExceedMaxLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : 2,
              overflow: _expanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
            ),
            if (overflow)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 14,
                        color: Colors.white70,
                      ),
                      Text(
                        _expanded ? '收起' : '展开',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
