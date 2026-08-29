import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/client.dart';
import '../api/config_api.dart';
import '../providers/recommend_provider.dart';
import '../services/tailnet_service.dart';
import '../theme/app_theme.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _authKeyController = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool? _testOk;
  String _scheme = 'http';
  ConnectionMode _connectionMode = ConnectionMode.direct;
  bool _tailnetBusy = false;

  bool _autoSync = false;
  bool _autoSyncLoading = true;
  bool _autoSyncSaving = false;
  ConfigApi? _configApi;

  @override
  void initState() {
    super.initState();
    final client = context.read<ApiClient>();
    _scheme = client.scheme;
    _connectionMode = client.connectionMode;
    _hostController.text = client.host;
    _portController.text = client.port.toString();
    _configApi = ConfigApi(client);
    _loadAutoSync();
  }

  Future<void> _loadAutoSync() async {
    final api = _configApi;
    if (api == null) return;
    final enabled = await api.savedAutoSyncEnabled();
    if (!mounted) return;
    setState(() {
      _autoSync = enabled;
      _autoSyncLoading = false;
    });
  }

  Future<void> _toggleAutoSync(bool enabled) async {
    final api = _configApi;
    if (api == null || _autoSyncSaving) return;
    setState(() {
      _autoSyncSaving = true;
      _autoSync = enabled;
    });
    final ok = await api.setSavedAutoSync(enabled);
    if (!mounted) return;
    setState(() {
      _autoSyncSaving = false;
      if (!ok) _autoSync = !enabled;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok ? (enabled ? '已开启：保存时自动同步到对应平台' : '已关闭自动同步') : '设置保存失败，请稍后重试',
          ),
          backgroundColor: ok ? null : Colors.red[700],
        ),
      );
  }

  Future<void> _requestAutoSync(bool enabled) async {
    if (enabled && !_autoSync) {
      final confirmed = await showAdaptiveDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text('开启自动同步？'),
          content: const Text(
            '开启后，在 OpenBiliClaw 点击收藏或稍后再看，会修改对应平台账号中的收藏、书签、播放列表或稍后观看。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('确认开启'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await _toggleAutoSync(enabled);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _authKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8420;
    setState(() => _saving = true);
    final client = context.read<ApiClient>();
    await client.saveSettings(
      host,
      port,
      scheme: _schemeFor(host),
      connectionMode: _connectionMode,
    );
    if (!mounted) return;
    final recommendations = context.read<RecommendProvider>();
    recommendations.stopPolling();
    recommendations.startPolling();
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('设置已保存，正在重新连接…'),
        duration: Duration(seconds: 1),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _testConnection() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8420;

    setState(() {
      _testing = true;
      _testResult = null;
      _testOk = null;
    });

    final client = context.read<ApiClient>();
    if (_connectionMode == ConnectionMode.tailscale) {
      final connected = await _connectTailnet();
      if (!connected) {
        if (!mounted) return;
        setState(() {
          _testing = false;
          _testOk = false;
          _testResult = context.read<TailnetService>().statusMessage;
        });
        return;
      }
    }
    final testHost = host.contains('://')
        ? host
        : '${_schemeFor(host)}://$host';
    final ok = await client.checkHealth(
      overrideHost: testHost,
      overridePort: port,
      overrideConnectionMode: _connectionMode,
    );

    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = ok;
      _testResult = ok ? '后端连接成功！' : '无法连接后端，请检查地址和端口';
    });
  }

  String _schemeFor(String host) {
    final parsed = Uri.tryParse(host);
    if (parsed != null && parsed.hasScheme) return parsed.scheme;
    return _scheme;
  }

  Future<bool> _connectTailnet() async {
    if (_tailnetBusy) return false;
    setState(() => _tailnetBusy = true);
    final service = context.read<TailnetService>();
    var ok = await service.connect(authKey: _authKeyController.text);
    _authKeyController.clear();
    final loginUrl = service.authUrl;
    if (!ok && loginUrl != null) {
      final opened = await launchUrl(
        loginUrl,
        mode: LaunchMode.externalApplication,
      );
      if (opened) ok = await service.waitForConnection();
    }
    if (mounted) setState(() => _tailnetBusy = false);
    return ok;
  }

  Future<void> _logoutTailnet() async {
    if (_tailnetBusy) return;
    setState(() => _tailnetBusy = true);
    await context.read<TailnetService>().logout();
    if (mounted) setState(() => _tailnetBusy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设置'),
        centerTitle: theme.platform == TargetPlatform.iOS,
        backgroundColor: context.appColors.background,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppGradients.brandSoft(context),
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  border: Border.all(
                    color: AppColors.brand.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.brandStrong,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: const Icon(
                        Icons.link,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '后端地址',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '局域网直连，或通过内置 Tailscale 安全访问',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Consumer<TailnetService>(
                builder: (context, tailnet, _) =>
                    DropdownButtonFormField<ConnectionMode>(
                      initialValue: _connectionMode,
                      decoration: InputDecoration(
                        labelText: '连接方式',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: context.appColors.surface,
                        prefixIcon: const Icon(Icons.route_outlined),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: ConnectionMode.direct,
                          child: Text('直接连接（局域网 / 公网）'),
                        ),
                        if (tailnet.supported)
                          const DropdownMenuItem(
                            value: ConnectionMode.tailscale,
                            child: Text('内置 Tailscale（Android / iOS）'),
                          ),
                      ],
                      onChanged: (value) => setState(
                        () => _connectionMode = value ?? ConnectionMode.direct,
                      ),
                    ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _scheme,
                decoration: InputDecoration(
                  labelText: '协议',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: context.appColors.surface,
                  prefixIcon: const Icon(Icons.security_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'http', child: Text('HTTP（局域网）')),
                  DropdownMenuItem(value: 'https', child: Text('HTTPS')),
                ],
                onChanged: (value) => setState(() => _scheme = value ?? 'http'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: '主机地址',
                  hintText: _connectionMode == ConnectionMode.tailscale
                      ? '例如 openbiliclaw-server 或 100.x.x.x'
                      : '例如 192.168.1.100',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: context.appColors.surface,
                  prefixIcon: const Icon(Icons.computer),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _portController,
                decoration: InputDecoration(
                  labelText: '端口',
                  hintText: '8420',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: context.appColors.surface,
                  prefixIcon: const Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
              ),
              if (_connectionMode == ConnectionMode.tailscale) ...[
                const SizedBox(height: 16),
                Consumer<TailnetService>(
                  builder: (context, tailnet, _) => Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      border: Border.all(color: context.appColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              tailnet.state == TailnetState.running
                                  ? Icons.check_circle_outline
                                  : Icons.vpn_key_outlined,
                              color: tailnet.state == TailnetState.running
                                  ? context.appPositive
                                  : theme.colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                tailnet.statusMessage,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        if (tailnet.state != TailnetState.running) ...[
                          const SizedBox(height: 14),
                          TextField(
                            controller: _authKeyController,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: InputDecoration(
                              labelText: 'Tailscale Auth Key（首次连接）',
                              hintText: 'tskey-auth-…',
                              helperText: '可留空改用网页登录；Key 不会保存到应用设置',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _tailnetBusy
                                    ? null
                                    : _connectTailnet,
                                icon: _tailnetBusy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.power_settings_new),
                                label: Text(
                                  tailnet.state == TailnetState.running
                                      ? '重新连接'
                                      : '连接 Tailscale',
                                ),
                              ),
                            ),
                            if (tailnet.state != TailnetState.idle) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _tailnetBusy ? null : _logoutTailnet,
                                child: const Text('移除设备'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.save, size: 20),
                      label: Text(
                        _saving ? '保存中…' : '保存',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.secondary,
                        side: BorderSide(color: theme.colorScheme.secondary),
                      ),
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find, size: 20),
                      label: Text(
                        _testing ? '测试中…' : '测试连接',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _testOk == true
                        ? context.appPositive.withValues(alpha: 0.1)
                        : theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _testOk == true ? Icons.check_circle : Icons.error,
                        color: _testOk == true
                            ? context.appPositive
                            : theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: TextStyle(
                            color: _testOk == true
                                ? context.appPositive
                                : theme.colorScheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  border: Border.all(color: context.appColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '保存与同步',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '保存时自动同步到对应平台',
                                style: TextStyle(fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '默认关闭。收藏和稍后再看始终先保存在本地；关闭时仍可在内容库手动同步。',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_autoSyncLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Switch.adaptive(
                            value: _autoSync,
                            onChanged: _autoSyncSaving
                                ? null
                                : _requestAutoSync,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.appColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.large),
                  border: Border.all(color: context.appColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用说明',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• Web、iOS、macOS 默认连接 127.0.0.1:8420\n'
                      '• Android 模拟器默认使用 10.0.2.2:8420\n'
                      '• Android 真机请填电脑的局域网 IP 和端口\n'
                      '• Tailscale 模式请填服务器的 MagicDNS 名称或 100.x 地址\n'
                      '• 首次连接可网页登录，或使用一次性/短期 Auth Key\n'
                      '• 有反向代理时可选择 HTTPS\n'
                      '• 后端开启密码门禁时，应用会自动进入登录页\n'
                      '• 保存后会立即按新地址重新连接',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appColors.inkMuted,
                        height: 1.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
