import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('build/player-live');
  await output.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      await File('${output.path}/$name.png').writeAsBytes(bytes);
      return bytes.isNotEmpty;
    },
    responseDataCallback: (data) async {
      await File('${output.path}/report.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert(data?['live']),
      );
    },
    writeResponseOnFailure: true,
  );
}
