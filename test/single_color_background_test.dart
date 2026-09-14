import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonorynth/m3e_beat_stage.dart';

void main() {
  for (final dark in [false, true]) {
    test('single hue, subtle brighter bottom ($dark)', () {
      final colors = AlbumBackground.gradientColors([Colors.red], dark).map(HSLColor.fromColor).toList();
      expect(colors.first.hue, closeTo(colors.last.hue, 1));
      expect(colors.last.lightness - colors.first.lightness, closeTo(.07, .01));
      expect(colors.first.saturation, greaterThan(.60));
      for (final color in AlbumBackground.gradientColors([Colors.grey], dark)) {
        expect(HSLColor.fromColor(color).saturation, 0);
      }
    });
  }
  testWidgets('static option does not mount animated renderer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AlbumBackground(
      singleColor: true, colors: [Colors.red], trackId: 'test',
    )));
    expect(find.byType(PaletteGradientStage), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
