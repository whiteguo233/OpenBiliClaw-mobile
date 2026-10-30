import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:openbiliclaw_app/views/backend_scan_view.dart';

class _Images extends ImagePickerPlatform {
  Future<XFile?> Function() select = () async => XFile('/cache/qr.png');
  int selections = 0;
  ImagePickerOptions? options;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) {
    expect(source, ImageSource.gallery);
    this.options = options;
    selections++;
    return select();
  }
}

class _Decoder extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  BarcodeCapture? result = const BarcodeCapture(
    barcodes: [Barcode(rawValue: 'http://192.168.1.7:8420/m/')],
  );
  bool cameraDenied = false;
  bool imageFails = false;
  int starts = 0;
  int stops = 0;
  final analyzed = <String>[];

  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    if (cameraDenied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.unavailable,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async => stops++;
  @override
  Future<void> dispose() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const [],
  }) async {
    expect(formats, [BarcodeFormat.qrCode]);
    analyzed.add(path);
    if (imageFails) throw StateError('image cannot be decoded');
    return result;
  }
}

void main() {
  late ImagePickerPlatform previousImages;
  late MobileScannerPlatform previousDecoder;
  late _Images images;
  late _Decoder decoder;
  late ValueNotifier<String?> imported;

  setUp(() {
    previousImages = ImagePickerPlatform.instance;
    previousDecoder = MobileScannerPlatform.instance;
    ImagePickerPlatform.instance = images = _Images();
    MobileScannerPlatform.instance = decoder = _Decoder();
    MobileScannerController.resetPlatformSessionOwner();
    imported = ValueNotifier(null);
  });

  tearDown(() async {
    ImagePickerPlatform.instance = previousImages;
    MobileScannerPlatform.instance = previousDecoder;
    MobileScannerController.resetPlatformSessionOwner();
    await decoder.captures.close();
    imported.dispose();
  });

  Future<void> open(WidgetTester tester, {bool dark = false}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                imported.value = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const BackendScanView()),
                );
              },
              child: const Text('打开扫码'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开扫码'));
    await tester.pumpAndSettle();
  }

  testWidgets('bottom right image action decodes and returns a valid QR', (
    tester,
  ) async {
    await open(tester);
    final button = find.widgetWithText(FilledButton, '选择图片');
    expect(tester.getRect(button).center.dx, greaterThan(260));
    expect(tester.getRect(button).center.dy, greaterThan(700));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(imported.value, 'http://192.168.1.7:8420/m/');
    expect(decoder.analyzed, ['/cache/qr.png']);
    expect(images.options?.requestFullMetadata, isFalse);
    expect(find.byType(BackendScanView), findsNothing);
  });

  testWidgets('cancel preserves scan page and resumes the camera', (
    tester,
  ) async {
    images.select = () async => null;
    await open(tester, dark: true);
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(imported.value, isNull);
    expect(decoder.analyzed, isEmpty);
    expect(decoder.starts, 2);
    expect(find.byType(BackendScanView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final invalid in [
    null,
    const BarcodeCapture(),
    const BarcodeCapture(
      barcodes: [Barcode(rawValue: 'http://127.0.0.1:8420/m/')],
    ),
  ]) {
    testWidgets('unusable picture keeps the original connection: $invalid', (
      tester,
    ) async {
      decoder.result = invalid;
      await open(tester);
      await tester.tap(find.text('选择图片'));
      await tester.pumpAndSettle();
      expect(imported.value, isNull);
      expect(find.byType(BackendScanView), findsOneWidget);
      expect(find.textContaining('图片中未找到'), findsOneWidget);
      expect(decoder.starts, 2);
    });
  }

  testWidgets('camera permission denial still allows image import', (
    tester,
  ) async {
    decoder.cameraDenied = true;
    await open(tester);
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(imported.value, 'http://192.168.1.7:8420/m/');
  });

  testWidgets('cancelling an image does not request a denied camera again', (
    tester,
  ) async {
    decoder.cameraDenied = true;
    images.select = () async => null;
    await open(tester);
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(imported.value, isNull);
    expect(decoder.starts, 1);
    expect(find.text('选择图片'), findsOneWidget);
  });

  testWidgets('picker and decoder failures leave a usable retry action', (
    tester,
  ) async {
    images.select = () async =>
        throw PlatformException(code: 'photo_access_denied');
    await open(tester);
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(imported.value, isNull);
    expect(find.textContaining('无法读取图片'), findsOneWidget);
    images.select = () async => XFile('/cache/qr.png');
    decoder.imageFails = true;
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(find.textContaining('无法读取图片'), findsOneWidget);
    decoder.imageFails = false;
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(imported.value, 'http://192.168.1.7:8420/m/');
  });

  testWidgets(
    'picker lifecycle and stale camera results cannot double import',
    (tester) async {
      final selection = Completer<XFile?>();
      images.select = () => selection.future;
      await open(tester);
      await tester.tap(find.text('选择图片'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      decoder.captures.add(
        const BarcodeCapture(
          barcodes: [Barcode(rawValue: 'http://192.168.8.8:8420/m/')],
        ),
      );
      await tester.pump();
      expect(imported.value, isNull);
      expect(decoder.starts, 1);
      expect(find.text('识别中…'), findsOneWidget);
      selection.complete(XFile('/cache/qr.png'));
      await tester.pumpAndSettle();
      expect(images.selections, 1);
      expect(imported.value, 'http://192.168.1.7:8420/m/');
    },
  );
}
