import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/backend_connection_link.dart';

/// Camera frames are decoded on-device and are never uploaded to a backend.
class BackendScanView extends StatefulWidget {
  const BackendScanView({super.key});

  @override
  State<BackendScanView> createState() => _BackendScanViewState();
}

class _BackendScanViewState extends State<BackendScanView>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _completed) return;
    try {
      await _controller.start();
    } catch (_) {
      if (mounted) setState(() => _error = '无法打开相机，请检查相机权限，或返回后粘贴连接链接。');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_start());
    } else {
      unawaited(_controller.stop());
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_completed) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      try {
        BackendConnectionLink.parse(value);
      } on FormatException catch (error) {
        setState(() => _error = error.message);
        continue;
      }
      _completed = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('扫码连接后端')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('打开电脑 Web 或插件的「手机版」，选择连接网络后，将二维码对准相机。'),
        ),
        Expanded(
          child: MobileScanner(
            controller: _controller,
            useAppLifecycleState: false,
            onDetect: _onDetect,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('无法使用相机。请在系统设置中允许相机权限，或返回后使用「粘贴连接链接」。'),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              _error ?? '识别后自动保存后端地址。相机画面仅在本机识别。',
              style: TextStyle(
                color: _error == null
                    ? null
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
