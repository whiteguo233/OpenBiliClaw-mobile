/// B 站登录态状态。对应后端 `/api/bilibili/auth/status` 的 `status` 字段。
enum BilibiliAuthState {
  anonymous('anonymous'),
  scanning('scanning'),
  scanned('scanned'),
  pending('pending'),
  loggedIn('logged_in'),
  expired('expired'),
  unsupported('unsupported');

  const BilibiliAuthState(this.apiValue);
  final String apiValue;

  static BilibiliAuthState parse(String value) {
    for (final state in values) {
      if (state.apiValue == value) return state;
    }
    return BilibiliAuthState.unsupported;
  }
}

/// 二维码登录轮询状态。
enum BilibiliQrStatus {
  pending('pending'),
  scanned('scanned'),
  confirmed('confirmed'),
  expired('expired'),
  failed('failed');

  const BilibiliQrStatus(this.apiValue);
  final String apiValue;

  static BilibiliQrStatus parse(String value) {
    for (final status in values) {
      if (status.apiValue == value) return status;
    }
    return BilibiliQrStatus.failed;
  }
}

class BilibiliUser {
  final int mid;
  final String name;
  final String face;
  final bool vip;

  const BilibiliUser({
    this.mid = 0,
    this.name = '',
    this.face = '',
    this.vip = false,
  });

  factory BilibiliUser.fromJson(Map<String, dynamic> json) => BilibiliUser(
    mid: _int(json['mid']),
    name: _text(json['name'] ?? json['uname']),
    face: _text(json['face']),
    vip: json['vip'] == true,
  );
}

class BilibiliAuthInfo {
  final BilibiliAuthState state;
  final BilibiliUser? user;
  final List<String> scopes;
  final String expiresAt;

  const BilibiliAuthInfo({
    this.state = BilibiliAuthState.anonymous,
    this.user,
    this.scopes = const [],
    this.expiresAt = '',
  });

  factory BilibiliAuthInfo.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return BilibiliAuthInfo(
      state: BilibiliAuthState.parse(_text(json['status'])),
      user: rawUser is Map
          ? BilibiliUser.fromJson(Map<String, dynamic>.from(rawUser))
          : null,
      scopes: _strings(json['scopes']),
      expiresAt: _text(json['expires_at']),
    );
  }

  bool get isLoggedIn => state == BilibiliAuthState.loggedIn;
}

/// 后端导出的 B 站会话 Cookie。
///
/// 移动端只把这份 Cookie 保存在内存中，用于当前播放会话内的 B 站直连
/// （评论 / 视频详情等不需要 WBI 签名的接口）；不落盘、不持久化。
class BilibiliCookieSession {
  final String cookie;
  final String userAgent;
  final String buvid;
  final String expiresAt;
  final BilibiliUser? user;

  const BilibiliCookieSession({
    this.cookie = '',
    this.userAgent = '',
    this.buvid = '',
    this.expiresAt = '',
    this.user,
  });

  factory BilibiliCookieSession.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return BilibiliCookieSession(
      cookie: _cookieString(json),
      userAgent: _text(json['user_agent'] ?? json['userAgent']),
      buvid: _text(json['buvid']),
      expiresAt: _text(json['expires_at'] ?? json['expiresAt']),
      user: rawUser is Map
          ? BilibiliUser.fromJson(Map<String, dynamic>.from(rawUser))
          : null,
    );
  }

  bool get isLoggedIn => cookie.isNotEmpty;
}

class BilibiliQrLogin {
  final String qrcodeKey;
  final String qrcodeUrl;
  final int expiresIn;
  final String expiresAt;

  const BilibiliQrLogin({
    this.qrcodeKey = '',
    this.qrcodeUrl = '',
    this.expiresIn = 0,
    this.expiresAt = '',
  });

  factory BilibiliQrLogin.fromJson(Map<String, dynamic> json) =>
      BilibiliQrLogin(
        qrcodeKey: _text(json['qrcode_key']),
        qrcodeUrl: _text(json['qrcode_url']),
        expiresIn: _int(json['expires_in']),
        expiresAt: _text(json['expires_at']),
      );
}

class BilibiliQrPoll {
  final BilibiliQrStatus status;
  final BilibiliUser? user;
  final String message;

  const BilibiliQrPoll({
    this.status = BilibiliQrStatus.pending,
    this.user,
    this.message = '',
  });

  factory BilibiliQrPoll.fromJson(Map<String, dynamic> json) {
    final rawUser = json['user'];
    return BilibiliQrPoll(
      status: BilibiliQrStatus.parse(_text(json['status'])),
      user: rawUser is Map
          ? BilibiliUser.fromJson(Map<String, dynamic>.from(rawUser))
          : null,
      message: _text(json['message']),
    );
  }
}

String _cookieString(Map<String, dynamic> json) {
  final rawCookie = json['cookie'];
  if (rawCookie is String && rawCookie.trim().isNotEmpty) {
    return rawCookie.trim();
  }
  final rawCookies = json['cookies'];
  if (rawCookies is Map) {
    final pairs = rawCookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .where((pair) => pair.isNotEmpty)
        .toList();
    if (pairs.isNotEmpty) return pairs.join('; ');
  }
  return '';
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
