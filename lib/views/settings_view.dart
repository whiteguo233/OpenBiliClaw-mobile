import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/client.dart';
import '../theme/app_theme.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  bool _saving = false;
  bool _testing = false;
  String? _testResult;
  bool? _testOk;
  String _scheme = 'http';

  @override
  void initState() {
    super.initState();
    final client = context.read<ApiClient>();
    _scheme = client.scheme;
    _hostController.text = client.host;
    _portController.text = client.port.toString();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8420;
    setState(() => _saving = true);
    final client = context.read<ApiClient>();
    await client.saveSettings(host, port, scheme: _schemeFor(host));
    if (!mounted) return;
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
    final testHost = host.contains('://')
        ? host
        : '${_schemeFor(host)}://$host';
    final ok = await client.checkHealth(
      overrideHost: testHost,
      overridePort: port,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('连接设置'),
        centerTitle: true,
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppGradients.brandSoft(),
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
                  child: const Icon(Icons.link, color: Colors.white, size: 20),
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
                        '设置 OpenBiliClaw 后端的 IP 和端口',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _scheme,
            decoration: InputDecoration(
              labelText: '协议',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
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
              hintText: '例如 192.168.1.100',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.white,
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
              fillColor: Colors.white,
              prefixIcon: const Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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
                    foregroundColor: AppColors.lavender,
                    side: const BorderSide(color: AppColors.lavender),
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
                    ? const Color(0xFF30B980).withValues(alpha: 0.1)
                    : const Color(0xFFEF7A86).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _testOk == true ? Icons.check_circle : Icons.error,
                    color: _testOk == true
                        ? const Color(0xFF30B980)
                        : const Color(0xFFEF7A86),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _testResult!,
                      style: TextStyle(
                        color: _testOk == true
                            ? const Color(0xFF30B980)
                            : const Color(0xFFEF7A86),
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
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(color: AppColors.line),
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
                  '• 有反向代理时可选择 HTTPS\n'
                  '• 后端开启密码门禁时，应用会自动进入登录页\n'
                  '• 保存后会立即按新地址重新连接',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    height: 1.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
