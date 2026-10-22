import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonorynth/ui_motion.dart';

Widget host(Widget child, {bool reduce = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('press feedback preserves the child tap and releases scale', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        MotionPress(
          child: TextButton(onPressed: () => taps++, child: const Text('Open')),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Open')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      .975,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets(
    'entrance finishes and remains settled across ordinary rebuilds',
    (tester) async {
      Widget content() =>
          host(const MotionEntrance(order: 3, child: Text('Card')));
      await tester.pumpWidget(content());
      await tester.pumpAndSettle();
      final opacity = find.ancestor(
        of: find.text('Card'),
        matching: find.byType(Opacity),
      );
      expect(tester.widget<Opacity>(opacity.first).opacity, 1);
      await tester.pumpWidget(content());
      await tester.pump();
      expect(tester.widget<Opacity>(opacity.first).opacity, 1);
      expect(tester.hasRunningAnimations, isFalse);
    },
  );

  testWidgets('reduced motion skips entrances and press scaling', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const MotionEntrance(
          order: 5,
          child: MotionPress(
            child: SizedBox(width: 80, height: 48, child: Text('Card')),
          ),
        ),
        reduce: true,
      ),
    );
    final opacity = find.ancestor(
      of: find.text('Card'),
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(opacity.first).opacity, 1);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Card')),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('song replacement retires the old content after its transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const MotionSwap(identity: 'a', child: Text('First'))),
    );
    await tester.pumpWidget(
      host(const MotionSwap(identity: 'b', child: Text('Second'))),
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
