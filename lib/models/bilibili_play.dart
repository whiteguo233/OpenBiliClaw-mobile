/// One playable page inside a Bilibili multi-part video.
class BilibiliPlayPage {
  final int cid;
  final int page;
  final String part;
  final int duration;
  final int width;
  final int height;

  const BilibiliPlayPage({
    this.cid = 0,
    this.page = 0,
    this.part = '',
    this.duration = 0,
    this.width = 0,
    this.height = 0,
  });

  factory BilibiliPlayPage.fromJson(Map<String, dynamic> json) {
    final dimension = json['dimension'];
    final dimensionMap = dimension is Map
        ? Map<String, dynamic>.from(dimension)
        : const <String, dynamic>{};
    return BilibiliPlayPage(
      cid: _int(json['cid']),
      page: _int(json['page']),
      part: _text(json['part']),
      duration: _int(json['duration']),
      width: _int(dimensionMap['width']),
      height: _int(dimensionMap['height']),
    );
  }
}

/// One selectable video/audio quality.
class BilibiliQuality {
  final int qn;
  final String label;
  final int width;
  final int height;

  const BilibiliQuality({
    this.qn = 0,
    this.label = '',
    this.width = 0,
    this.height = 0,
  });

  factory BilibiliQuality.fromJson(Map<String, dynamic> json) =>
      BilibiliQuality(
        qn: _int(json['qn'] ?? json['id']),
        label: _text(json['label'] ?? json['quality']),
        width: _int(json['width']),
        height: _int(json['height']),
      );
}

/// A resolved network media stream (video or audio).
class BilibiliPlayMedia {
  final int qn;
  final String label;
  final String codec;
  final String url;
  final List<String> backupUrls;
  final int width;
  final int height;
  final int bandwidth;
  final String mimeType;

  const BilibiliPlayMedia({
    this.qn = 0,
    this.label = '',
    this.codec = '',
    this.url = '',
    this.backupUrls = const [],
    this.width = 0,
    this.height = 0,
    this.bandwidth = 0,
    this.mimeType = '',
  });

  factory BilibiliPlayMedia.fromJson(Map<String, dynamic> json) =>
      BilibiliPlayMedia(
        qn: _int(json['qn'] ?? json['id']),
        label: _text(json['label']),
        codec: _text(json['codec']),
        url: _text(json['url'] ?? json['base_url']),
        backupUrls: _strings(json['backup_urls'] ?? json['backupUrl']),
        width: _int(json['width']),
        height: _int(json['height']),
        bandwidth: _int(json['bandwidth']),
        mimeType: _text(json['mime_type'] ?? json['mimeType']),
      );
}

class BilibiliDanmaku {
  final String url;
  final Map<String, String> headers;

  const BilibiliDanmaku({this.url = '', this.headers = const {}});

  factory BilibiliDanmaku.fromJson(Map<String, dynamic> json) =>
      BilibiliDanmaku(
        url: _text(json['url']),
        headers: _stringMap(json['headers']),
      );

  bool get exists => url.isNotEmpty;
}

class BilibiliSubtitle {
  final String lan;
  final String name;
  final String url;

  const BilibiliSubtitle({this.lan = '', this.name = '', this.url = ''});

  factory BilibiliSubtitle.fromJson(Map<String, dynamic> json) =>
      BilibiliSubtitle(
        lan: _text(json['lan']),
        name: _text(json['name']),
        url: _text(json['url']),
      );
}

class BilibiliPlayResult {
  final String bvid;
  final int cid;
  final int duration;
  final List<BilibiliPlayPage> pages;
  final List<BilibiliQuality> qualities;
  final BilibiliPlayMedia? video;
  final BilibiliPlayMedia? audio;
  final List<BilibiliSubtitle> subtitles;
  final BilibiliDanmaku danmaku;
  final Map<String, String> headers;
  final String expiresAt;

  const BilibiliPlayResult({
    this.bvid = '',
    this.cid = 0,
    this.duration = 0,
    this.pages = const [],
    this.qualities = const [],
    this.video,
    this.audio,
    this.subtitles = const [],
    this.danmaku = const BilibiliDanmaku(),
    this.headers = const {},
    this.expiresAt = '',
  });

  factory BilibiliPlayResult.fromJson(Map<String, dynamic> json) {
    final rawPages = json['pages'];
    final rawQualities = json['qualities'] ?? json['support_formats'];
    final rawVideo = json['video'];
    final rawAudio = json['audio'];
    final rawSubtitles = json['subtitles'] ?? json['subtitle'];
    final rawDanmaku = json['danmaku'];
    return BilibiliPlayResult(
      bvid: _text(json['bvid']),
      cid: _int(json['cid']),
      duration: _int(json['duration']),
      pages: _list(rawPages)
          .whereType<Map>()
          .map(
            (item) =>
                BilibiliPlayPage.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      qualities: _list(rawQualities)
          .whereType<Map>()
          .map(
            (item) => BilibiliQuality.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      video: rawVideo is Map
          ? BilibiliPlayMedia.fromJson(Map<String, dynamic>.from(rawVideo))
          : null,
      audio: rawAudio is Map
          ? BilibiliPlayMedia.fromJson(Map<String, dynamic>.from(rawAudio))
          : null,
      subtitles: _list(rawSubtitles)
          .whereType<Map>()
          .map(
            (item) =>
                BilibiliSubtitle.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(),
      danmaku: rawDanmaku is Map
          ? BilibiliDanmaku.fromJson(Map<String, dynamic>.from(rawDanmaku))
          : const BilibiliDanmaku(),
      headers: _stringMap(json['headers']),
      expiresAt: _text(json['expires_at']),
    );
  }
}

String _text(dynamic value) => value?.toString().trim() ?? '';

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(_text(value)) ?? 0;
}

List<String> _strings(dynamic value) {
  if (value is List) return value.map((e) => _text(e)).toList();
  return const [];
}

List<dynamic> _list(dynamic value) => value is List ? value : const [];

Map<String, String> _stringMap(dynamic value) {
  if (value is Map) {
    return value.map((key, val) => MapEntry(_text(key), _text(val)));
  }
  return const {};
}
