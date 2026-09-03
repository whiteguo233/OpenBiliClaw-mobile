import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/bilibili_api.dart';
import '../api/client.dart';
import '../models/bilibili_auth.dart';

/// Bilibili QR-code login page.
///
/// The backend owns the actual Bilibili login flow and writes the Cookie into
/// the OpenBiliClaw runtime store; this page only displays the QR code and
/// polls until the user finishes scanning.
class BilibiliLoginView extends StatefulWidget {
  const BilibiliLoginView({super.key});

  @override
  State<BilibiliLoginView> createState() => _BilibiliLoginViewState();
}

class _BilibiliLoginViewState extends State<BilibiliLoginView> {
  BilibiliApi? _api;
  BilibiliQrLogin? _qr;
  BilibiliQrStatus _status = BilibiliQrStatus.pending;
  String _message = '等待扫码…';
  Timer? _timer;
  bool _loading = true;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _api = BilibiliApi(context.read<ApiClient>());
    await _refresh();
  }

  Future<void> _refresh() async {
    final api = _api;
    if (api == null) return;
    _timer?.cancel();
    setState(() {
      _loading = true;
      _status = BilibiliQrStatus.pending;
      _message = '正在生成二维码…';
    });
    try {
      final qr = await api.startQrLogin();
      if (!mounted) return;
      setState(() {
        _qr = qr;
        _loading = false;
      });
      _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _poll(qr.qrcodeKey),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = '二维码生成失败：$error';
      });
    }
  }

  Future<void> _poll(String key) async {
    if (_polling || !mounted) return;
    final api = _api;
    if (api == null) return;
    _polling = true;
    try {
      final poll = await api.pollQrLogin(qrcodeKey: key);
      if (!mounted) return;
      setState(() {
        _status = poll.status;
        _message = poll.message.isEmpty
            ? _statusLabel(poll.status)
            : poll.message;
      });
      if (poll.status == BilibiliQrStatus.confirmed ||
          poll.status == BilibiliQrStatus.expired) {
        _timer?.cancel();
        if (poll.status == BilibiliQrStatus.confirmed) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (_) {
      // A transient poll failure should not tear down the login page.
    } finally {
      _polling = false;
    }
  }

  String _statusLabel(BilibiliQrStatus status) {
    return switch (status) {
      BilibiliQrStatus.pending => '等待扫码…',
      BilibiliQrStatus.scanned => '已扫码，请在手机上确认',
      BilibiliQrStatus.confirmed => '登录成功',
      BilibiliQrStatus.expired => '二维码已过期',
      BilibiliQrStatus.failed => '登录失败',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qr = _qr;
    return Scaffold(
      appBar: AppBar(title: const Text('扫码登录 B站')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: _loading || qr == null
                    ? const SizedBox(
                        width: 240,
                        height: 240,
                        child: Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      )
                    : QrImageView(
                        data: qr.qrcodeUrl,
                        version: QrVersions.auto,
                        size: 240,
                        backgroundColor: Colors.white,
                      ),
              ),
              const SizedBox(height: 20),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: _status == BilibiliQrStatus.expired
                      ? theme.colorScheme.error
                      : _status == BilibiliQrStatus.confirmed
                      ? theme.colorScheme.primary
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '使用 B站 App 扫一扫，登录态会保存到你的 OpenBiliClaw 后端。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_status == BilibiliQrStatus.expired) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新二维码'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
