import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'app_state.dart';
import 'audio_handler.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter's defaults are generous for desktop-class hardware. Bound decoded
  // artwork on memory-constrained Android devices without changing its display
  // resolution or visual quality.
  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.maximumSize = 32;
  imageCache.maximumSizeBytes = 24 << 20;
  final audioHandler = await AudioService.init(
    builder: MelodyAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'app.sonorynth.player.audio',
      androidNotificationChannelName: 'Sonorynth 播放',
      androidNotificationChannelDescription: '显示正在播放的歌曲与媒体快捷操作',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      artDownscaleWidth: 512,
      artDownscaleHeight: 512,
      preloadArtwork: true,
    ),
  );
  await audioHandler.initialize();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final state = MelodyState(audioHandler);
  audioHandler.onSkip = state.skip;
  await state.initialize();
  runApp(MelodyScope(state: state, child: const MelodyApp()));
}

class MelodyApp extends StatelessWidget {
  const MelodyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = MelodyScope.read(context);
    return ValueListenableBuilder<int>(
      valueListenable: state.themeRevision,
      builder: (context, _, _) {
        final palette = !state.hasCurrent
            ? const [Color(0xffeceae7), Color(0xffe8e9eb), Color(0xffefe9eb)]
            : state.dynamicColor
            ? state.coverPalette
            : const [Color(0xff514fa0), Color(0xff76528f), Color(0xffa45062)];
        return MaterialApp(
          title: 'Sonorynth',
          debugShowCheckedModeBanner: false,
          themeMode: state.themeMode,
          theme: _theme(
            _scheme(palette, Brightness.light, idle: !state.hasCurrent),
            state,
          ),
          darkTheme: _theme(
            _scheme(palette, Brightness.dark, idle: !state.hasCurrent),
            state,
          ),
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  Theme.of(context).brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              statusBarBrightness:
                  Theme.of(context).brightness == Brightness.dark
                  ? Brightness.dark
                  : Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness:
                  Theme.of(context).brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
            child: child!,
          ),
          home: const AppShell(),
        );
      },
    );
  }

  ColorScheme _scheme(
    List<Color> palette,
    Brightness brightness, {
    bool idle = false,
  }) {
    if (idle) {
      final neutral = ColorScheme.fromSeed(
        seedColor: const Color(0xffdedddb),
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.neutral,
      );
      if (brightness == Brightness.dark) return neutral;
      return neutral.copyWith(
        surface: const Color(0xfffaf9f7),
        surfaceContainerLowest: const Color(0xffffffff),
        surfaceContainerLow: const Color(0xfff6f4f1),
        surfaceContainer: const Color(0xfff1efec),
        surfaceContainerHigh: const Color(0xffebe9e6),
        surfaceContainerHighest: const Color(0xffe5e3e0),
      );
    }
    final maximumSaturation = palette
        .map((color) => HSLColor.fromColor(color).saturation)
        .fold<double>(0, (value, item) => item > value ? item : value);
    final monochrome = maximumSaturation <= .02;
    final schemeVariant = monochrome
        ? DynamicSchemeVariant.monochrome
        : maximumSaturation <= .32
        ? DynamicSchemeVariant.neutral
        : DynamicSchemeVariant.tonalSpot;
    final primary = ColorScheme.fromSeed(
      seedColor: palette[0],
      brightness: brightness,
      dynamicSchemeVariant: schemeVariant,
    );
    // A monochrome Material scheme already contains deliberately varied
    // neutral primary/secondary/tertiary containers. Replacing all three with
    // independently generated primary containers turned every home card dark
    // grey and broke the mini player's foreground contrast.
    if (monochrome) return primary;
    final secondary = ColorScheme.fromSeed(
      seedColor: palette[1],
      brightness: brightness,
      dynamicSchemeVariant: schemeVariant,
    );
    final tertiary = ColorScheme.fromSeed(
      seedColor: palette[2],
      brightness: brightness,
      dynamicSchemeVariant: schemeVariant,
    );
    return primary.copyWith(
      secondary: secondary.primary,
      onSecondary: secondary.onPrimary,
      secondaryContainer: secondary.primaryContainer,
      onSecondaryContainer: secondary.onPrimaryContainer,
      secondaryFixed: secondary.primaryFixed,
      secondaryFixedDim: secondary.primaryFixedDim,
      onSecondaryFixed: secondary.onPrimaryFixed,
      onSecondaryFixedVariant: secondary.onPrimaryFixedVariant,
      tertiary: tertiary.primary,
      onTertiary: tertiary.onPrimary,
      tertiaryContainer: tertiary.primaryContainer,
      onTertiaryContainer: tertiary.onPrimaryContainer,
      tertiaryFixed: tertiary.primaryFixed,
      tertiaryFixedDim: tertiary.primaryFixedDim,
      onTertiaryFixed: tertiary.onPrimaryFixed,
      onTertiaryFixedVariant: tertiary.onPrimaryFixedVariant,
    );
  }

  ThemeData _theme(ColorScheme scheme, MelodyState state) {
    final baseText = Typography.material2021(
      platform: TargetPlatform.android,
    ).black.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: scheme.brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      textTheme: _weightedTextTheme(
        baseText,
        state.normalWeight,
        state.emphasisWeight,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
            fontWeight: states.contains(WidgetState.selected)
                ? state.emphasisWeight
                : state.normalWeight,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.tertiaryContainer,
        foregroundColor: scheme.onTertiaryContainer,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.secondaryContainer,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }

  TextTheme _weightedTextTheme(
    TextTheme base,
    FontWeight normal,
    FontWeight emphasis,
  ) => base.copyWith(
    displayLarge: base.displayLarge?.copyWith(fontWeight: emphasis),
    displayMedium: base.displayMedium?.copyWith(fontWeight: emphasis),
    displaySmall: base.displaySmall?.copyWith(fontWeight: emphasis),
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: emphasis),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: emphasis),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: emphasis),
    titleLarge: base.titleLarge?.copyWith(fontWeight: emphasis),
    titleMedium: base.titleMedium?.copyWith(fontWeight: emphasis),
    titleSmall: base.titleSmall?.copyWith(fontWeight: emphasis),
    bodyLarge: base.bodyLarge?.copyWith(fontWeight: normal),
    bodyMedium: base.bodyMedium?.copyWith(fontWeight: normal),
    bodySmall: base.bodySmall?.copyWith(fontWeight: normal),
    labelLarge: base.labelLarge?.copyWith(fontWeight: normal),
    labelMedium: base.labelMedium?.copyWith(fontWeight: normal),
    labelSmall: base.labelSmall?.copyWith(fontWeight: normal),
  );
}
