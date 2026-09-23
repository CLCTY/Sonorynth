import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/app_state.dart';
import 'package:melody_flow/ui.dart';
import 'package:melody_flow/models.dart';

class SettingsTestState extends ChangeNotifier implements MelodyState {
  @override
  FontWeight get emphasisWeight => FontWeight.w600;
  @override
  bool get efficientRendering => efficient;
  bool efficient = true;
  @override
  AudioQuality quality = AudioQuality.hires;
  @override
  bool get karaokeLyrics => true;
  @override
  LyricScrollPreset get lyricScrollPreset => LyricScrollPreset.balanced;
  @override
  int get lyricFrameRate => 30;
  @override
  String get themeModeLabel => '跟随系统';
  @override
  bool get dynamicColor => true;
  @override
  bool get loggedIn => false;
  @override
  bool get privateMode => false;
  @override
  Future<void> setQuality(AudioQuality value) async {
    quality = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setSetting) {
      efficient = invocation.positionalArguments[1] as bool;
      notifyListeners();
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('categories open detail, update and return in $brightness', (
      tester,
    ) async {
      final state = SettingsTestState();
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
            home: const SettingsScreen(),
          ),
        ),
      );
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('播放与音质'), findsOneWidget);
      expect(find.text('歌词与动画'), findsOneWidget);
      await tester.ensureVisible(find.text('性能与存储'));
      await tester.tap(find.text('性能与存储'));
      await tester.pumpAndSettle();
      expect(find.text('高效渲染'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(state.efficient, isFalse);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('设置'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('高效渲染关闭 · 存储说明'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
      'quality is selected inline and summary updates in $brightness',
      (tester) async {
        final state = SettingsTestState();
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
              home: const SettingsScreen(),
            ),
          ),
        );
        expect(find.text('默认 Hi-Res · 按歌曲与权益提供'), findsOneWidget);
        await tester.tap(find.text('播放与音质'));
        await tester.pumpAndSettle();
        expect(find.byType(RadioListTile<AudioQuality>), findsNWidgets(5));
        await tester.tap(find.text('标准'));
        await tester.pumpAndSettle();
        expect(state.quality, AudioQuality.standard);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('默认音质'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('默认 标准 · 按歌曲与权益提供'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
