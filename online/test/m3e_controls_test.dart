import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/ui.dart';

void main() {
  test('overview tones retain contrast across dark/light artwork hues', () {
    for (final brightness in Brightness.values) {
      for (final seed in [Colors.red, Colors.blue, Colors.green, Colors.grey]) {
        final scheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
          dynamicSchemeVariant: seed == Colors.grey
              ? DynamicSchemeVariant.monochrome
              : DynamicSchemeVariant.tonalSpot,
        );
        for (var tone = 0; tone < 4; tone++) {
          final colors = overviewColors(scheme, tone);
          final a = colors.background.computeLuminance();
          final b = colors.foreground.computeLuminance();
          final contrast =
              (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
          expect(
            contrast,
            greaterThanOrEqualTo(4.5),
            reason: '$brightness $seed tone $tone',
          );
          if (brightness == Brightness.dark) expect(a, lessThan(.3));
        }
      }
    }
  });
  for (final brightness in Brightness.values) {
    testWidgets('expressive control respects reduced motion in $brightness', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.red,
              brightness: brightness,
            ),
          ),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: ExpressiveIconButton(
                tooltip: '播放',
                icon: const Icon(Icons.play_arrow),
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
      expect(
        tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .duration,
        Duration.zero,
      );
      expect(
        tester.getSize(find.byType(ExpressiveIconButton)),
        const Size(48, 48),
      );
      await tester.tap(find.byType(ExpressiveIconButton));
      await tester.pump();
      expect(taps, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('overview reserves height for enlarged text', (tester) async {
    Future<double> cardHeight(double scale) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SizedBox(
                width: 360,
                child: AdaptiveM3Grid(
                  preferredHeight: 148,
                  children: [
                    SizedBox(key: ValueKey('first')),
                    SizedBox(),
                    SizedBox(),
                    SizedBox(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      return tester.getSize(find.byKey(const ValueKey('first'))).height;
    }

    final normal = await cardHeight(1);
    final enlarged = await cardHeight(2);
    expect(enlarged, greaterThanOrEqualTo(normal + 64));
  });
}
