import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonorynth/artwork_image.dart';

class _DirectHttp extends HttpOverrides {}

// Keep production HTTPS URL normalization while serving the test bytes locally.
class _LocalHttpClient implements HttpClient {
  final HttpClient inner = _DirectHttp().createHttpClient(null);
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    if (url.host != '127.0.0.1') {
      throw StateError('Unexpected external request');
    }
    return inner.openUrl(method, url.replace(scheme: 'http'));
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('cached artwork survives remount and pending high resolution', (
    tester,
  ) async {
    final directory = Directory.systemTemp.createTempSync('sonorynth-artwork-');
    final channel = const MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(128, 128);
    final boundary = GlobalKey();
    final gate = Completer<void>.sync();
    final highStarted = Completer<void>.sync();
    late HttpServer server;
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xffff0000), BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(16, 16);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final result = bytes!.buffer.asUint8List();
      image.dispose();
      picture.dispose();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final size = request.uri.queryParameters['param'];
        if (size == '1000y1000') {
          if (!highStarted.isCompleted) highStarted.complete();
          await gate.future;
        }
        request.response.statusCode = size == '1200y1200' ? 503 : 200;
        request.response.add(result);
        await request.response.close();
      });
      return result;
    }))!;
    expect(png, isNotEmpty);
    final url = 'http://127.0.0.1:${server.port}/cover.png';
    Future<File?> load(int size) => HttpOverrides.runZoned(
      () => ArtworkImage.loadFile(url, size: size),
      createHttpClient: (_) => _LocalHttpClient(),
    );
    Widget host(int size, String identity) => MaterialApp(
      home: RepaintBoundary(
        key: boundary,
        child: SizedBox.expand(
          child: ArtworkImage(
            key: ValueKey(identity),
            url: url,
            size: size,
            fallback: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );
    Future<void> verifyRed(String phase) async {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final index =
            ((image.height ~/ 2) * image.width + image.width ~/ 2) * 4;
        expect(data!.getUint8(index), greaterThan(240), reason: phase);
        expect(
          data.getUint8(index + 1),
          lessThan(20),
          reason: '$phase must retain image, not white fallback',
        );
        expect(data.getUint8(index + 2), lessThan(20), reason: phase);
        image.dispose();
      });
    }

    try {
      final thumbnail = (await tester.runAsync(() => load(84)))!;
      expect(thumbnail, isNotNull);
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(key: boundary, child: const SizedBox.expand()),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          ResizeImage.resizeIfNeeded(84, 84, FileImage(thumbnail)),
          boundary.currentContext!,
        ),
      );
      await tester.pumpWidget(host(84, 'mini'));
      await tester.pump();
      await verifyRed('loaded thumbnail');
      late Future<File?> highResolution;
      await tester.runAsync(() async {
        highResolution = load(1000);
        await highStarted.future;
      });
      await tester.pumpWidget(host(1000, 'flight'));
      await verifyRed('first flight frame while high resolution waits');
      await tester.pumpWidget(host(1000, 'full'));
      await verifyRed('first full-page frame while high resolution waits');
      gate.complete();
      final full = (await tester.runAsync(() => highResolution))!;
      await tester.runAsync(
        () => precacheImage(
          ResizeImage.resizeIfNeeded(1000, 1000, FileImage(full)),
          boundary.currentContext!,
        ),
      );
      await tester.pump();
      await verifyRed('high resolution arrives');
      await tester.pumpWidget(host(84, 'mini-return'));
      await verifyRed('first returning mini-player frame');
      await tester.runAsync(() => load(1200));
      await tester.pumpWidget(host(1200, 'failed-upgrade'));
      await tester.pump();
      await verifyRed('failed upgrade retains available artwork');
      expect(tester.takeException(), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => server.close(force: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      directory.deleteSync(recursive: true);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
