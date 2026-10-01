import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonorynth/app_state.dart';
import 'package:sonorynth/experience_preferences.dart';
import 'package:sonorynth/models.dart';
import 'package:sonorynth/m3e_beat_stage.dart';
import 'package:sonorynth/onboarding.dart';
import 'package:sonorynth/ui.dart';

class ExperienceTestState extends ChangeNotifier implements MelodyState {
  ExperienceTestState(this.store);
  final ExperiencePreferences store;
  @override
  bool get onboardingCompleted => store.completed;
  @override
  HomeLayoutPreferences get homeLayout => store.homeLayout;
  @override
  ThemeMode themeMode = ThemeMode.system;
  @override
  AudioQuality quality = AudioQuality.exhigh;
  @override
  bool dynamicColor = true;
  @override
  bool karaokeLyrics = true;
  @override
  bool showTranslation = true;
  @override
  bool efficientRendering = true;
  @override
  bool privateMode = false;
  @override
  bool gradientPlayerBackground = false;
  @override
  bool singleColorPlayerBackground = false;
  @override
  int fontWeightLevel = 0;
  @override
  LyricScrollPreset lyricScrollPreset = LyricScrollPreset.balanced;
  @override
  int lyricFrameRate = 30;
  @override
  FontWeight get emphasisWeight => FontWeight.w600;
  @override
  bool hasCurrent = false;
  @override
  List<Track> recent = [];
  @override
  List<Track> queue = [];
  @override
  Set<String> likedTrackIds = {};
  @override
  List<MusicPlaylist> allPlaylists = [];
  @override
  List<MusicPlaylist> cloudPlaylists = [];
  @override
  ListeningStats get stats => const ListeningStats();
  @override
  int cardShape(String id, int fallback) => 0;

  @override
  Future<void> setHomeLayout(HomeLayoutPreferences layout) async {
    final saving = store.setHomeLayout(layout);
    notifyListeners();
    await saving;
  }

  @override
  Future<void> setHomeElementVisible(HomeElement element, bool visible) =>
      setHomeLayout(homeLayout.withVisibility(element, visible));

  @override
  Future<void> completeOnboarding({QuickSetupChoices? choices}) async {
    await store.finish(choices: choices);
    if (choices != null) {
      themeMode = choices.themeMode;
      quality = choices.quality;
    }
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final previewKey = GlobalKey();
  final capturePreviews =
      Platform.environment['SONORYNTH_CAPTURE_PREVIEWS'] == '1';
  setUpAll(() async {
    if (!capturePreviews) return;
    final fonts = <String, String>{
      'Roboto': '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      'MaterialIcons':
          '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    };
    for (final font in fonts.entries) {
      final loader = FontLoader(font.key)
        ..addFont(File(font.value).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });
  Future<ExperienceTestState> state() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final result = ExperienceTestState(await ExperiencePreferences.load(prefs));
    addTearDown(result.dispose);
    return result;
  }

  Future<void> mount(
    WidgetTester tester,
    ExperienceTestState state,
    Widget home, {
    Brightness brightness = Brightness.light,
    double scale = 1,
    Size size = const Size(390, 844),
    bool reduced = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MelodyScope(
        state: state,
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xff6750a4),
              brightness: brightness,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              platformBrightness: brightness,
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            child: RepaintBoundary(key: previewKey, child: child!),
          ),
          home: home,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('welcome-next')),
        matching: find.byType(FilledButton),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> preview(WidgetTester tester, String name) async {
    if (!capturePreviews) return;
    final boundary =
        previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/feature-previews');
      await dir.create(recursive: true);
      await File(
        '${dir.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    String page = 'welcome-preferences',
    double delta = 220,
  }) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        delta,
        maxScrolls: 60,
        scrollable: find
            .descendant(
              of: find.byKey(PageStorageKey(page)),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'complete first launch saves choices, back keeps draft and gate exits',
    (tester) async {
      final model = await state();
      await mount(
        tester,
        model,
        const FirstLaunchGate(home: Text('ready-home')),
      );
      expect(find.text('欢迎来到\nSonorynth'), findsOneWidget);
      await preview(tester, 'welcome-light');
      await next(tester);
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.text('听歌，也有你的风格'))).brightness,
        Brightness.dark,
      );
      expect(model.themeMode, ThemeMode.system);
      await preview(tester, 'setup-dark');
      await reveal(tester, find.byKey(const ValueKey('welcome-quality')));
      final standard = find.descendant(
        of: find.byKey(const ValueKey('welcome-quality')),
        matching: find.widgetWithText(ChoiceChip, '标准'),
      );
      await tester.tap(standard);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('单色渐变'));
      await tester.tap(find.text('单色渐变'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('灵动'));
      await tester.tap(find.text('灵动'));
      await reveal(tester, find.text('60 FPS'));
      await tester.tap(find.text('60 FPS'));
      await tester.pumpAndSettle();
      await next(tester);
      await tester.tap(find.text('全部关闭'));
      await tester.pumpAndSettle();
      expect(find.text('已显示 0 / 10 项'), findsOneWidget);
      await preview(tester, 'home-setup-dark');
      await tester.tap(find.byTooltip('上一步'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('深色'), delta: -220);
      expect(
        tester
            .widget<ChoiceChip>(
              find.ancestor(
                of: find.text('深色'),
                matching: find.byType(ChoiceChip),
              ),
            )
            .selected,
        isTrue,
      );
      await next(tester);
      expect(find.text('已显示 0 / 10 项'), findsOneWidget);
      await next(tester);
      expect(find.text('ready-home'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeMode'), 'dark');
      expect(prefs.getInt('quality'), AudioQuality.standard.index);
      expect(prefs.getBool('singleColorPlayerBackground'), isTrue);
      expect(prefs.getInt('lyricScrollPreset'), LyricScrollPreset.lively.index);
      expect(prefs.getInt('lyricFrameRate'), 60);
      expect((await ExperiencePreferences.load(prefs)).completed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('skip after changing a draft retains defaults', (tester) async {
    final model = await state();
    await mount(tester, model, const FirstLaunchGate(home: Text('ready-home')));
    await next(tester);
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('稍后设置'));
    await tester.pumpAndSettle();
    expect(find.text('ready-home'), findsOneWidget);
    expect(model.themeMode, ThemeMode.system);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('themeMode'), isNull);
    expect(model.onboardingCompleted, isTrue);
  });

  testWidgets('revisit cancel returns without applying a draft', (
    tester,
  ) async {
    final model = await state();
    await model.store.finish();
    await mount(
      tester,
      model,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const WelcomeScreen(revisit: true),
              ),
            ),
            child: const Text('open-welcome'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open-welcome'));
    await tester.pumpAndSettle();
    await next(tester);
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('open-welcome'), findsOneWidget);
    expect(model.themeMode, ThemeMode.system);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home settings hide all content and restore it without deleting music',
    (tester) async {
      final model = await state();
      model.likedTrackIds = {'kept-song'};
      await mount(tester, model, const Scaffold(body: HomeScreen()));
      expect(find.byType(StatTile), findsNWidgets(4));
      await tester.tap(find.byTooltip('主页设置'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsSwitch), findsNWidgets(10));
      await tester.tap(find.text('全部关闭'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StatTile), findsNothing);
      expect(find.byType(SectionHeader), findsNothing);
      expect(find.byType(WeeklyListeningCard), findsNothing);
      expect(find.text('SONORYNTH'), findsNothing);
      expect(find.byTooltip('主页设置'), findsOneWidget);
      expect(model.likedTrackIds, {'kept-song'});
      await tester.tap(find.byTooltip('主页设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部显示'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StatTile), findsNWidgets(4));
      expect(find.text('SONORYNTH'), findsOneWidget);
      await tester.tap(find.byTooltip('主页设置'));
      await tester.pumpAndSettle();
      final likedToggle = find.descendant(
        of: find.byKey(const ValueKey('home-toggle-likedSongs')),
        matching: find.byType(SwitchListTile),
      );
      await tester.ensureVisible(likedToggle);
      await tester.tap(likedToggle);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StatTile), findsNWidgets(3));
      expect(find.text('喜欢的歌曲'), findsNothing);
      expect(find.text('当前音质'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion freezes the flowing album background', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: AlbumBackground(
            singleColor: false,
            colors: [Colors.blue],
            trackId: 'reduced-motion',
            animate: true,
          ),
        ),
      ),
    );
    expect(
      tester
          .widget<PaletteGradientStage>(find.byType(PaletteGradientStage))
          .animate,
      isFalse,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'large text, short viewport and reduced motion in $brightness',
      (tester) async {
        final model = await state();
        await mount(
          tester,
          model,
          const WelcomeScreen(),
          brightness: brightness,
          scale: 2,
          size: const Size(360, 420),
          reduced: true,
        );
        expect(
          tester
              .widget<AnimatedScale>(
                find.descendant(
                  of: find.byType(M3EActionButton),
                  matching: find.byType(AnimatedScale),
                ),
              )
              .duration,
          Duration.zero,
        );
        await next(tester);
        await reveal(tester, find.text('单色渐变'));
        await tester.pumpAndSettle();
        await next(tester);
        await reveal(tester, find.text('主页迷你播放器'), page: 'welcome-home');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
