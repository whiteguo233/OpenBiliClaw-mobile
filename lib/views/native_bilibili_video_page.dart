import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/bilibili_api.dart';
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
  });

  final String bvid;
  final String title;
  final String contentUrl;
  final String coverUrl;

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
  String? _error;
  bool _loadStarted = false;
  int? _selectedQn;
  int? _selectedCid;
  List<DanmakuItem> _danmakuItems = const [];
  double _rate = 1.0;
  int _selectedSubtitle = -1;
  TapDownDetails? _doubleTapDetails;
  BilibiliVideoState? _videoState;
  List<BilibiliComment> _comments = const [];
  List<BilibiliRelatedVideo> _related = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= BilibiliApi(context.read<ApiClient>());
    if (!_loadStarted) {
      _loadStarted = true;
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

  Future<void> _loadDanmaku(BilibiliPlayResult result) async {
    final danmaku = result.danmaku;
    if (!danmaku.exists) return;
    try {
      final response = await http.get(
        Uri.parse(danmaku.url),
        headers: danmaku.headers,
      );
      if (response.statusCode != 200) return;
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final pattern = RegExp(r'<d p="([^"]+)">([^<]*)</d>');
      final items = <DanmakuItem>[];
      for (final match in pattern.allMatches(body)) {
        final params = match.group(1)?.split(',') ?? const <String>[];
        if (params.isEmpty) continue;
        final seconds = double.tryParse(params.first) ?? 0;
        final text = match.group(2) ?? '';
        if (text.trim().isEmpty) continue;
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
    try {
      final results = await Future.wait([
        api.videoRelation(bvid: widget.bvid),
        api.videoComments(bvid: widget.bvid),
        api.relatedVideos(bvid: widget.bvid),
      ]);
      if (!mounted) return;
      setState(() {
        _videoState = results[0] as BilibiliVideoState;
        _comments = results[1] as List<BilibiliComment>;
        _related = results[2] as List<BilibiliRelatedVideo>;
      });
    } catch (_) {
      // Interactions/comments/related are optional enhancements.
    }
  }

  Future<void> _toggleLike() async {
    final api = _api;
    final state = _videoState;
    if (api == null || state == null) return;
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
    final state = _videoState;
    if (api == null || state == null) return;
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
    final state = _videoState;
    if (api == null || state == null) return;
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
      await _load();
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.parse(
      widget.contentUrl.isNotEmpty
          ? widget.contentUrl
          : 'https://www.bilibili.com/video/${widget.bvid}',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开外部链接')));
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
            tooltip: '用浏览器打开',
            onPressed: _openExternal,
            icon: const Icon(Icons.open_in_browser_rounded),
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
    return Column(
      children: [
        AspectRatio(
          aspectRatio: _aspectRatio(video),
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
                      child: Video(controller: _videoController!),
                    ),
              IgnorePointer(
                child: DanmakuOverlay(
                  position: _player.stream.position,
                  items: _danmakuItems,
                ),
              ),
            ],
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title.isNotEmpty ? widget.title : 'B站视频',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: result.qualities
                      .map(
                        (quality) => ActionChip(
                          label: Text(quality.label),
                          labelStyle: const TextStyle(fontSize: 11),
                          visualDensity: VisualDensity.compact,
                          onPressed: _loading
                              ? null
                              : () => _switchQuality(quality),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final rate in const [0.5, 1.0, 1.25, 1.5, 2.0])
                      ActionChip(
                        label: Text(rate == 1.0 ? '1.0x' : '${rate}x'),
                        labelStyle: const TextStyle(fontSize: 11),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _rate == rate ? Colors.white24 : null,
                        onPressed: _loading ? null : () => _switchRate(rate),
                      ),
                  ],
                ),
                if (result.subtitles.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        label: const Text('字幕'),
                        labelStyle: const TextStyle(fontSize: 11),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _selectedSubtitle == -1
                            ? Colors.white24
                            : null,
                        onPressed: _loading ? null : () => _selectSubtitle(-1),
                      ),
                      for (var i = 0; i < result.subtitles.length; i++)
                        ActionChip(
                          label: Text(result.subtitles[i].name),
                          labelStyle: const TextStyle(fontSize: 11),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: _selectedSubtitle == i
                              ? Colors.white24
                              : null,
                          onPressed: _loading ? null : () => _selectSubtitle(i),
                        ),
                    ],
                  ),
                ],
                if (result.pages.length > 1) ...[
                  const SizedBox(height: 10),
                  Text('分P', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  ...result.pages.map(
                    (page) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: _loading ? null : () => _switchPage(page),
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text('${page.page}'),
                      ),
                      title: Text(
                        page.part,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
                if (_comments.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.mode_comment_outlined,
                        color: Colors.white70,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '评论',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ..._comments
                      .take(10)
                      .map(
                        (comment) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
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
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
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
        ),
      ],
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
}
