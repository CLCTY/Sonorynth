import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonorynth/app_state.dart';
import 'package:sonorynth/models.dart';
import 'package:sonorynth/netease_api.dart';
import 'package:sonorynth/ui.dart';

class PickerTestState extends ChangeNotifier implements MelodyState {
  @override
  Track current = const Track(
    id: 'song',
    title: '当前歌曲',
    artist: '歌手',
    album: '',
    coverUrl: '',
  );
  @override
  bool hasCachedCurrentLyrics = true;
  @override
  bool searchingLyrics = false;
  @override
  String lyricChoicesTrackId = '';
  @override
  List<LyricChoice> lyricChoices = [];
  @override
  bool showTranslation = true;
  @override
  bool karaokeLyrics = true;
  @override
  String get lyricSourceOrderLabel => '网易云音乐';
  @override
  LyricScrollPreset get lyricScrollPreset => LyricScrollPreset.balanced;
  @override
  double get lyricScrollStiffness => 210;
  @override
  double get lyricScrollDamping => 25;
  @override
  int get lyricFrameRate => 30;
  @override
  int get lyricDelayMs => 0;
  @override
  FontWeight get emphasisWeight => FontWeight.w600;
  int searches = 0;
  LyricChoice? selected;
  bool emptyResults = false;

  @override
  Future<void> searchLyrics(String keyword) async {
    searches++;
    lyricChoicesTrackId = current.id;
    lyricChoices = emptyResults
        ? []
        : List.generate(
            30,
            (index) => LyricChoice(
              track: Track(
                id: '$index',
                title: '候选歌词 $index',
                artist: '歌手',
                album: '',
                coverUrl: '',
              ),
              payload: const LyricsPayload(lrc: '[00:00.00]歌词'),
            ),
          );
    notifyListeners();
  }

  @override
  void selectLyrics(LyricChoice choice) => selected = choice;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> openPicker(
  WidgetTester tester,
  PickerTestState state,
  Size size,
) async {
  await state.searchLyrics('${state.current.title} ${state.current.artist}');
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MelodyScope(
      state: state,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showLyricPickerSheet(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cached song shows choices, expands and scrolls to another lyric',
    (tester) async {
      final state = PickerTestState();
      addTearDown(state.dispose);
      await openPicker(tester, state, const Size(390, 700));
      expect(state.searches, 1);
      expect(find.text('候选歌词 0'), findsOneWidget);
      expect(find.text('显示翻译'), findsNothing);
      final scroll = find.byType(CustomScrollView);
      final initialHeight = tester
          .getSize(find.byType(DraggableScrollableSheet))
          .height;
      await tester.drag(scroll, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(DraggableScrollableSheet)).height,
        greaterThan(initialHeight),
      );
      await tester.scrollUntilVisible(
        find.text('候选歌词 20'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('候选歌词 20'));
      await tester.pumpAndSettle();
      expect(state.selected?.track.id, '20');
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'small screen and keyboard keep settings and choices scrollable',
    (tester) async {
      final state = PickerTestState();
      addTearDown(state.dispose);
      await openPicker(tester, state, const Size(360, 640));
      await tester.tap(find.text('歌词显示与时间设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('候选歌词 0'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(tester.takeException(), isNull);
      // Simulate the reduced viewport while the search keyboard is open.
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('候选歌词 10'),
        150,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('候选歌词 10'));
      await tester.pumpAndSettle();
      expect(state.selected?.track.id, '10');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty search preserves cached lyrics and allows a retry', (
    tester,
  ) async {
    final state = PickerTestState()..emptyResults = true;
    addTearDown(state.dispose);
    await openPicker(tester, state, const Size(390, 700));
    expect(find.textContaining('当前缓存歌词仍可使用'), findsOneWidget);
    expect(state.hasCachedCurrentLyrics, isTrue);
    state.emptyResults = false;
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pumpAndSettle();
    expect(state.searches, 2);
    expect(find.text('候选歌词 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
