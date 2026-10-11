import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonorynth/lyric_gyroscope.dart';
import 'package:sonorynth/luminous_lyrics.dart';
import 'package:sonorynth/models.dart';

void main() {
  testWidgets('sensor listens only during visible foreground playback', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <String>[];
    const channel = MethodChannel('app.sonorynth.player/lyric_gyroscope');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final clock = ValueNotifier(Duration.zero);
    addTearDown(clock.dispose);
    Widget stage(bool playing) => MaterialApp(
      home: LuminousLyrics(
        lines: const [],
        position: clock,
        playing: playing,
        ink: Colors.white,
        accent: Colors.blue,
      ),
    );
    await tester.pumpWidget(stage(false));
    expect(calls, isEmpty);
    await tester.pumpWidget(stage(true));
    await tester.pump();
    expect(calls, ['listen']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls.last, 'cancel');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls.last, 'listen');
    await tester.pumpWidget(stage(false));
    await tester.pump();
    expect(calls.last, 'cancel');
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  test('gyro is bounded, ignores invalid data and returns to center', () {
    final tilt = LyricTilt();
    for (var i = 0; i < 1000; i++) {
      tilt.update(100, -100, .033);
    }
    expect(tilt.value.dx.abs(), lessThanOrEqualTo(1));
    expect(tilt.value.dy.abs(), lessThanOrEqualTo(1));
    final previous = tilt.value;
    expect(tilt.update(double.nan, 0, .1), previous);
    for (var i = 0; i < 120; i++) {
      tilt.update(0, 0, .033);
    }
    expect(tilt.value.distance, lessThan(.001));
  });

  testWidgets(
    'worst animated text bounds fit portrait, landscape and large fonts',
    (tester) async {
      final words = List.generate(
        32,
        (i) => LyricWord(
          i.isEven ? '歌词' : 'longword',
          Duration(seconds: i),
          Duration(seconds: i + 1),
        ),
      );
      for (final size in [
        const Size(288, 360),
        const Size(650, 105),
        const Size(288, 180),
      ]) {
        for (final scale in [1.0, 2.5]) {
          final layout = LuminousLayout.calculate(
            words,
            size,
            TextScaler.linear(scale),
            TextDirection.ltr,
          );
          expect(layout.words.length, words.length);
          for (final box in layout.words) {
            final halfX = (box.size.width + box.size.height * .035) * 1.12 / 2;
            final halfY = (box.size.height + box.size.width * .035) * 1.12 / 2;
            // Drift + gyro + pulse + glow are all included in the envelope.
            final rect = Rect.fromCenter(
              center: box.center,
              width: (halfX + 9 + 6) * 2,
              height: (halfY + 24 + 6) * 2,
            );
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.top, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
          }
        }
      }
    },
  );

  for (final size in [const Size(320, 568), const Size(740, 200)]) {
    testWidgets('safe layout, seeking and backwards scrubbing at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = ValueNotifier(const Duration(milliseconds: 1500));
      addTearDown(clock.dispose);
      Duration? sought;
      final lines = [
        LyricLine(
          start: Duration.zero,
          end: const Duration(seconds: 3),
          text: 'Hello world',
          translation: '很长的翻译内容 ' * 20,
          words: const [
            LyricWord('Hello', Duration.zero, Duration(seconds: 1)),
            LyricWord('world', Duration(seconds: 1), Duration(seconds: 3)),
          ],
        ),
        const LyricLine(
          start: Duration(seconds: 3),
          end: Duration(seconds: 7),
          text: 'Next line',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(2.5),
            ),
            child: Scaffold(
              body: LuminousLyrics(
                lines: lines,
                position: clock,
                playing: false,
                ink: Colors.white,
                accent: Colors.blue,
                onSeek: (value) => sought = value,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Next line'));
      await tester.tap(find.text('Next line'));
      expect(sought, const Duration(seconds: 3));
      clock.value = const Duration(seconds: 4);
      await tester.pump();
      expect(find.byKey(const ValueKey('luminous-stage')), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 80));
      final entering = tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('luminous-stage')).last,
              matching: find.byType(FadeTransition),
            )
            .first,
      );
      expect(entering.opacity.value, greaterThan(0));
      expect(entering.opacity.value, lessThan(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('luminous-stage')), findsOneWidget);
      var painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('luminous-stage')).last,
                  )
                  .painter!
              as LuminousPainter;
      expect(painter.line!.text, 'Next line');
      clock.value = const Duration(milliseconds: 500);
      await tester.pump();
      painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('luminous-stage')).last,
                  )
                  .painter!
              as LuminousPainter;
      expect(painter.line!.text, 'Hello world');
      expect(tester.takeException(), isNull);
      // Ensure all fallback fragments retain the original line timing.
      final fallback = LuminousPainter(
        line: lines.first,
        position: clock.value,
        tilt: Offset.zero,
        ink: Colors.white,
        accent: Colors.blue,
        textScaler: TextScaler.noScaling,
        karaoke: false,
        motion: false,
        direction: TextDirection.ltr,
      );
      expect(fallback.words.map((word) => word.text).join(), lines.first.text);
      expect(
        fallback.words.every(
          (word) =>
              word.start == lines.first.start && word.end == lines.first.end,
        ),
        isTrue,
      );
    });
  }
}
