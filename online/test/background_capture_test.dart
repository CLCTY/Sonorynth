import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/m3e_beat_stage.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('red artwork stays red in $brightness', (tester) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(const Color(0xffff0000), BlendMode.src);
      final picture = recorder.endRecording();
      final texture = (await tester.runAsync(() => picture.toImage(12, 12)))!;
      picture.dispose();
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: RepaintBoundary(
            key: key,
            child: PaletteGradientStage(
              colors: const [Color(0xffff0000)],
              trackId: 'red-regression',
              debugTexture: texture,
              animate: false,
            ),
          ),
        ),
      );
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final rendered = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: .1),
      ))!;
      final data = (await tester.runAsync(
        () => rendered.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final center =
          ((rendered.height ~/ 2) * rendered.width + rendered.width ~/ 2) * 4;
      // Preserve red hue while adapting luminance to the actual app theme.
      final red = data.getUint8(center);
      final green = data.getUint8(center + 1);
      final blue = data.getUint8(center + 2);
      expect(red - green, greaterThan(35));
      expect(red - blue, greaterThan(35));
      expect((green - blue).abs(), lessThan(15));
      if (brightness == Brightness.light) {
        expect(red, greaterThan(180));
      } else {
        expect(green, lessThan(90));
      }
      rendered.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      texture.dispose();
    });
  }
  Future<void> capture(
    WidgetTester tester,
    Brightness brightness,
    String golden, {
    List<Color> colors = const [
      Color(0xff239a91),
      Color(0xff8fa23d),
      Color(0xffb8663b),
    ],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(432, 936);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final texture = await tester.runAsync(() async {
      final bytes = await File(
        'design-qa/amll-reference-cover.png',
      ).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 12,
        targetHeight: 12,
      );
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    });
    if (texture == null) {
      throw StateError('Could not decode the visual-QA album texture.');
    }
    addTearDown(texture.dispose);

    final captureKey = ValueKey('flow-background-$brightness');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff3f8f91),
            brightness: brightness,
          ),
        ),
        home: RepaintBoundary(
          key: captureKey,
          child: PaletteGradientStage(
            colors: colors,
            trackId: 'amll-reference-flow',
            animate: true,
            debugTexture: texture,
          ),
        ),
      ),
    );
    await tester.pump();
    if (brightness == Brightness.light) {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile('../design-qa/start-$golden'),
      );
    }
    if (brightness == Brightness.dark) {
      await expectLater(
        find.byKey(captureKey),
        matchesGoldenFile(
          '../design-qa/melody-amll-flow-start-implementation.png',
        ),
      );
    }
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (i == 59 && brightness == Brightness.light) {
        await expectLater(
          find.byKey(captureKey),
          matchesGoldenFile('../design-qa/mid-$golden'),
        );
      }
    }

    await expectLater(
      find.byKey(captureKey),
      matchesGoldenFile('../design-qa/$golden'),
    );
  }

  testWidgets('captures the dark flowing mesh background for visual QA', (
    tester,
  ) async {
    await capture(
      tester,
      Brightness.dark,
      'melody-amll-flow-implementation.png',
    );
  });

  testWidgets('captures the light flowing mesh background for visual QA', (
    tester,
  ) async {
    await capture(
      tester,
      Brightness.light,
      'melody-amll-flow-light-implementation.png',
    );
  });

  test('a monochrome palette cannot reintroduce a coloured cast', () {
    const palette = [Color(0xff707070), Color(0xff565656), Color(0xff929292)];
    expect(PaletteGradientStage.debugIsNeutralPalette(palette), isTrue);
    final field = PaletteGradientStage.debugBuildFieldPalette(
      palette,
      const Color(0xff3f8f91),
      true,
    );
    expect(
      field.every((color) => HSLColor.fromColor(color).saturation <= .001),
      isTrue,
    );
  });
  for (final entry in <String, List<Color>>{
    'red-blue': [
      const Color(0xffec1428),
      const Color(0xff07597e),
      const Color(0xffdc2633),
    ],
    'monochrome': [
      const Color(0xff777777),
      const Color(0xff444444),
      const Color(0xffaaaaaa),
    ],
    'pastel': [
      const Color(0xffead6cf),
      const Color(0xffdeb6cb),
      const Color(0xffa8cbeb),
    ],
  }.entries) {
    testWidgets('light flow multi-time ${entry.key}', (tester) async {
      await capture(
        tester,
        Brightness.light,
        'light-flow-${entry.key}.png',
        colors: entry.value,
      );
    });
  }
}
