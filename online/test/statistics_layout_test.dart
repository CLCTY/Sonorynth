import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/app_state.dart';
import 'package:melody_flow/models.dart';
import 'package:melody_flow/ui.dart';

class StatsState extends ChangeNotifier implements MelodyState {
  @override
  FontWeight get emphasisWeight => FontWeight.w600;
  @override
  ListeningStats get stats => ListeningStats(
    totalPlays: 205,
    days: {
      ListeningStats.dateKey(DateTime.now()): const ListeningDay(
        seconds: 7320,
        plays: 6,
      ),
    },
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('statistics cards are safe at $brightness / $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = StatsState();
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MelodyScope(
            state: state,
            child: MaterialApp(
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blue,
                  brightness: brightness,
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const ListeningStatsScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(StatTile), findsNWidgets(4));
        for (final tile in tester.widgetList<StatTile>(find.byType(StatTile))) {
          expect(tile.shape, M3ContentShape.softSquare);
          expect(tile.valueFontSize, 24);
        }
        final label = find.text('累计播放');
        final card = find
            .ancestor(of: label, matching: find.byType(Card))
            .first;
        expect(
          tester.getRect(card).contains(tester.getRect(label).topLeft),
          isTrue,
        );
        expect(
          tester.getRect(card).contains(tester.getRect(label).bottomRight),
          isTrue,
        );
        await tester.ensureVisible(find.text('本周趋势'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
