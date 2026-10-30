import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:openbiliclaw_app/models/backend_connection_link.dart';
import 'fixtures/connection_qr_images.dart';

/// Decode backend-generated QR v5/v10 PNGs on macOS, Android or physical iOS.
/// iOS simulators do not support image analysis in mobile_scanner.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native decoder imports LAN, Tailnet, HTTPS and long URLs', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('obc-qr-decode-');
    addTearDown(() => directory.delete(recursive: true));
    final controller = MobileScannerController(autoStart: false);
    addTearDown(controller.dispose);
    var index = 0;
    for (final entry in connectionQrImages.entries) {
      final link = entry.key;
      final file = File('${directory.path}/connection-${index++}.png');
      await file.writeAsBytes(base64Decode(entry.value));
      final capture = await controller.analyzeImage(file.path);
      expect(
        capture?.barcodes.map((barcode) => barcode.rawValue),
        contains(link),
      );
      final parsed = BackendConnectionLink.parse(link);
      expect(
        parsed.usesEmbeddedTailnet,
        link.contains('obc_connection=tailscale'),
      );
    }
  });
}
