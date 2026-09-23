import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/lyric_colors.dart';
import 'package:melody_flow/app_state.dart';
import 'package:melody_flow/models.dart';
import 'package:melody_flow/ui.dart';

class _State extends ChangeNotifier implements MelodyState {
  @override
  FontWeight get emphasisWeight => FontWeight.w600;
  @override
  FontWeight get normalWeight => FontWeight.w400;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('played and active words retain their role colour', (
    tester,
  ) async {
    final state = _State();
    final clock = ValueNotifier(const Duration(milliseconds: 1500));
    addTearDown(state.dispose);
    addTearDown(clock.dispose);
    await tester.pumpWidget(
      MelodyScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(
            body: KaraokeWords(
              words: const [
                LyricWord('已播', Duration.zero, Duration(seconds: 1)),
                LyricWord('当前', Duration(seconds: 1), Duration(seconds: 2)),
                LyricWord('未播', Duration(seconds: 2), Duration(seconds: 3)),
              ],
              positionListenable: clock,
              alignment: WrapAlignment.start,
              accentColor: Colors.red,
              inkColor: Colors.black,
            ),
          ),
        ),
      ),
    );
    Color? color(String text) =>
        tester.widget<Text>(find.text(text)).style?.color;
    expect(color('已播'), Colors.red);
    expect(color('当前'), Colors.red);
    expect(color('未播'), isNot(Colors.red));
    clock.value = const Duration(seconds: 4);
    await tester.pump(const Duration(seconds: 1));
    expect(color('未播'), Colors.red);
    await tester.pumpWidget(const SizedBox());
  });
  for (final dark in [false, true]) {
    test('monochrome roles stay neutral and distinct ($dark)', () {
      final roles = List.generate(
        3,
        (i) => albumLyricRoleColor([Colors.grey], dark, i),
      );
      expect(roles.toSet().length, 3);
      for (final color in roles) {
        expect(HSLColor.fromColor(color).saturation, 0);
      }
    });
    test('single hue produces three album-related roles ($dark)', () {
      final roles = List.generate(
        3,
        (i) => albumLyricRoleColor([Colors.red], dark, i),
      );
      expect(roles.toSet().length, 3);
      for (final color in roles) {
        expect(HSLColor.fromColor(color).saturation, greaterThan(.77));
        if (dark) {
          expect(HSLColor.fromColor(color).lightness, lessThan(.68));
        }
      }
    });
  }
}
