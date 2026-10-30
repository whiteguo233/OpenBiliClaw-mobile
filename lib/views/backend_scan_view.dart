import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/backend_connection_link.dart';

/// Camera frames and selected images are decoded locally without upload.
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
  bool _readingImage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || _completed || _readingImage) return;
    try {
      await _controller.start();
      // Permission prompts can finish after the image picker has opened.
      if (!mounted || _readingImage || _completed) await _controller.stop();
    } catch (_) {
      if (mounted && _error == null) {
        setState(() => _error = '无法打开相机。可以选择二维码图片，或返回后粘贴连接链接。');
      }
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
    if (_readingImage) return;
    _acceptCapture(capture);
  }

  bool _acceptCapture(BarcodeCapture capture, {bool fromImage = false}) {
    if (!mounted || _completed) return false;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null) continue;
      try {
        BackendConnectionLink.parse(value);
      } on FormatException catch (error) {
        if (!fromImage) setState(() => _error = error.message);
        continue;
      }
      _completed = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(value);
      return true;
    }
    return false;
  }

  Future<void> _selectImage() async {
    if (_readingImage || _completed) return;
    final resumeCamera = _controller.value.isRunning;
    setState(() {
      _readingImage = true;
      _error = null;
    });
    try {
      await _controller.stop();
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (!mounted || image == null) return;
      final capture = await _controller.analyzeImage(
        image.path,
        formats: const [BarcodeFormat.qrCode],
      );
      if (!mounted) return;
      if (capture == null || !_acceptCapture(capture, fromImage: true)) {
        setState(() => _error = '图片中未找到可用的后端二维码，请选择电脑 Web 或插件中的完整二维码截图。');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '无法读取图片，请重新选择清晰的二维码截图，或检查图片访问权限。');
      }
    } finally {
      if (mounted) {
        setState(() => _readingImage = false);
        if (resumeCamera &&
            !_completed &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          unawaited(_start());
        }
      }
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
                child: Text('无法使用相机。可以选择二维码图片，或在系统设置中允许相机权限。'),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error ?? '识别后自动保存后端地址。相机画面与图片仅在本机识别。',
                    style: TextStyle(
                      color: _error == null
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _readingImage ? null : _selectImage,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  icon: _readingImage
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(_readingImage ? '识别中…' : '选择图片'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
