import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tailscale/tailscale.dart';

import 'tailnet_service.dart';

TailnetService createTailnetService() => NativeTailnetService();

class NativeTailnetService extends TailnetService {
  static const _enableDiagnosticLogs = bool.fromEnvironment(
    'OBC_E2E_TAILSCALE_LOGS',
  );
  static const _platformChannel = MethodChannel(
    'com.openbiliclaw.app/tailnet_state_protection',
  );

  TailnetState _state = TailnetState.idle;
  String _statusMessage = '尚未连接';
  String? _ipAddress;
  Uri? _authUrl;
  bool _initialized = false;
  bool _attemptedAuthKey = false;
  StreamSubscription<NodeState>? _stateSubscription;
  StreamSubscription<TailscaleRuntimeError>? _errorSubscription;

  @override
  bool get supported => Platform.isAndroid || Platform.isIOS;

  @override
  TailnetState get state => supported ? _state : TailnetState.unsupported;

  @override
  String get statusMessage {
    if (supported) return _statusMessage;
    return '当前平台暂不支持内置 Tailscale';
  }

  @override
  String? get ipAddress => _ipAddress;

  @override
  Uri? get authUrl => _authUrl;

  @override
  http.Client? get httpClient =>
      _state == TailnetState.running ? Tailscale.instance.http.client : null;

  @override
  Future<void> initialize() async {
    if (!supported || _initialized) return;

    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final stateDirectory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}tailnet_state',
      );
      await stateDirectory.create(recursive: true);

      if (Platform.isIOS) {
        final protected = await _platformChannel.invokeMethod<bool>(
          'excludeFromBackup',
          {'path': stateDirectory.path},
        );
        if (protected != true) {
          throw StateError('无法将 Tailscale 身份目录排除在 iCloud 备份之外');
        }
      }

      Tailscale.init(
        stateDir: stateDirectory.path,
        appId: Platform.isIOS
            ? 'com.openbiliclaw.openbiliclawApp'
            : 'com.openbiliclaw.openbiliclaw_app',
        logLevel: _enableDiagnosticLogs
            ? TailscaleLogLevel.info
            : TailscaleLogLevel.silent,
      );
      _stateSubscription = Tailscale.instance.onStateChange.listen(
        _applyNodeState,
      );
      _errorSubscription = Tailscale.instance.onError.listen((error) {
        _setState(TailnetState.error, 'Tailscale 运行错误：$error');
      });
      _initialized = true;
      await _refreshStatus();
    } catch (error) {
      _setState(TailnetState.error, 'Tailscale 初始化失败：$error');
    }
  }

  @override
  Future<bool> connect({String authKey = ''}) async {
    await initialize();
    if (!_initialized) return false;

    _setState(TailnetState.connecting, '正在连接 tailnet…');
    try {
      final trimmedKey = authKey.trim();
      _attemptedAuthKey = trimmedKey.isNotEmpty;
      var status = await Tailscale.instance.up(
        hostname: 'openbiliclaw-mobile',
        authKey: trimmedKey.isEmpty ? null : trimmedKey,
        timeout: const Duration(seconds: 30),
      );
      if (status.state == NodeState.starting ||
          status.state == NodeState.noState) {
        status = await _waitForStartupResult(status);
      }
      if (trimmedKey.isNotEmpty && status.needsLogin) {
        status = await _waitForAuthKeyResult(status);
      }
      if (trimmedKey.isNotEmpty && status.needsLogin) {
        await Tailscale.instance.down();
        _attemptedAuthKey = false;
        status = await Tailscale.instance.up(
          hostname: 'openbiliclaw-mobile',
          timeout: const Duration(seconds: 30),
        );
      }
      if (status.needsLogin && status.authUrl == null) {
        status = await _waitForAuthUrl(status);
      }
      _applyStatus(status);
      if (status.isRunning) _attemptedAuthKey = false;
      return status.isRunning;
    } catch (error) {
      _setState(TailnetState.error, _friendlyError(error));
      return false;
    }
  }

  @override
  Future<bool> waitForConnection({
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!_initialized) return false;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final status = await Tailscale.instance.status();
        _applyStatus(status);
        if (status.isRunning) return true;
        if (status.state == NodeState.needsMachineAuth) return false;
      } catch (error) {
        _setState(TailnetState.error, _friendlyError(error));
        return false;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _setState(TailnetState.needsLogin, '网页登录未完成，请重新连接后继续');
    return false;
  }

  @override
  Future<void> disconnect() async {
    if (!_initialized) return;
    try {
      await Tailscale.instance.down();
      _setState(TailnetState.stopped, '已断开，设备身份仍保留');
    } catch (error) {
      _setState(TailnetState.error, '断开失败：$error');
    }
  }

  @override
  Future<void> logout() async {
    if (!_initialized) return;
    try {
      await Tailscale.instance.logout();
      await Tailscale.instance.forgetLocalIdentity();
      _ipAddress = null;
      _authUrl = null;
      _setState(TailnetState.idle, '设备身份已移除');
    } catch (error) {
      _setState(TailnetState.error, '移除设备身份失败：$error');
    }
  }

  Future<void> _refreshStatus() async {
    final status = await Tailscale.instance.status();
    _applyStatus(status);
  }

  Future<TailscaleStatus> _waitForAuthUrl(TailscaleStatus initial) async {
    var status = initial;
    for (var attempt = 0; attempt < 120; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      status = await Tailscale.instance.status();
      if (!status.needsLogin || status.authUrl != null) return status;
    }
    return status;
  }

  Future<TailscaleStatus> _waitForAuthKeyResult(TailscaleStatus initial) async {
    var status = initial;
    for (var attempt = 0; attempt < 60; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = await Tailscale.instance.status();
      if (status.isRunning ||
          status.state == NodeState.needsMachineAuth ||
          status.authUrl != null) {
        return status;
      }
    }
    return status;
  }

  Future<TailscaleStatus> _waitForStartupResult(TailscaleStatus initial) async {
    var status = initial;
    for (var attempt = 0; attempt < 60; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      status = await Tailscale.instance.status();
      if (status.state != NodeState.starting &&
          status.state != NodeState.noState) {
        return status;
      }
    }
    return status;
  }

  void _applyNodeState(NodeState state) {
    switch (state) {
      case NodeState.noState:
        _ipAddress = null;
        _setState(TailnetState.idle, '需要 Auth Key 或网页登录首次加入 tailnet');
        break;
      case NodeState.needsLogin:
        unawaited(_refreshStatus());
        _setState(TailnetState.needsLogin, _needsLoginMessage);
        break;
      case NodeState.needsMachineAuth:
        _setState(TailnetState.needsApproval, '设备正在等待 Tailscale 管理员批准');
        break;
      case NodeState.starting:
        _setState(TailnetState.connecting, '正在连接 tailnet…');
        break;
      case NodeState.running:
        unawaited(_refreshStatus());
        break;
      case NodeState.stopped:
        _setState(TailnetState.stopped, '已断开，可使用已保存的设备身份重连');
        break;
      case NodeState.unknown:
        _setState(TailnetState.error, 'Tailscale 返回未知状态，请稍后重试');
        break;
    }
  }

  void _applyStatus(TailscaleStatus status) {
    _ipAddress = status.ipv4;
    _authUrl = status.authUrl;
    switch (status.state) {
      case NodeState.noState:
        _authUrl = null;
        _setState(TailnetState.idle, '需要 Auth Key 或网页登录首次加入 tailnet');
        break;
      case NodeState.needsLogin:
        _setState(TailnetState.needsLogin, _needsLoginMessage);
        break;
      case NodeState.needsMachineAuth:
        _setState(TailnetState.needsApproval, '设备正在等待 Tailscale 管理员批准');
        break;
      case NodeState.starting:
        _setState(TailnetState.connecting, '正在连接 tailnet…');
        break;
      case NodeState.running:
        _authUrl = null;
        final suffix = _ipAddress == null ? '' : ' · $_ipAddress';
        _setState(TailnetState.running, '已连接$suffix');
        break;
      case NodeState.stopped:
        _setState(TailnetState.stopped, '已断开，可使用已保存的设备身份重连');
        break;
      case NodeState.unknown:
        _setState(TailnetState.error, 'Tailscale 返回未知状态，请稍后重试');
        break;
    }
  }

  void _setState(TailnetState state, String message) {
    _state = state;
    _statusMessage = message;
    notifyListeners();
  }

  String get _needsLoginMessage => _attemptedAuthKey
      ? 'Auth Key 未被接受，可改用网页登录或生成新的 Key'
      : '需要登录 Tailscale，请在浏览器中完成授权';

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('no persisted') || text.contains('auth')) {
      return '连接失败：请填写有效的 Tailscale Auth Key';
    }
    return 'Tailscale 连接失败：$text';
  }

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    super.dispose();
  }
}
