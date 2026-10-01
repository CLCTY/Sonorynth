import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

enum HomeElement {
  branding('应用名称', '主页顶部的 SONORYNTH 标识', Icons.music_note_rounded),
  greeting('时段问候', '随时间变化的问候语', Icons.waving_hand_rounded),
  continueListening('继续聆听', '最近歌曲与继续播放入口', Icons.play_circle_rounded),
  overviewHeading('概览标题', '「你的音乐概览」分区标题', Icons.title_rounded),
  likedSongs('喜欢的歌曲', '收藏数量与喜欢歌曲入口', Icons.favorite_rounded),
  playlists('创建的歌单', '歌单数量与歌单入口', Icons.queue_music_rounded),
  recentPlays('最近播放', '播放记录数量与入口', Icons.history_rounded),
  audioQuality('当前音质', '默认音质与切换入口', Icons.high_quality_rounded),
  weeklyListening('本周聆听', '听歌时长、连续天数与趋势', Icons.bar_chart_rounded),
  miniPlayer('主页迷你播放器', '仅控制主页上的悬浮播放条', Icons.album_rounded);

  const HomeElement(this.title, this.description, this.icon);
  final String title;
  final String description;
  final IconData icon;
}

@immutable
class HomeLayoutPreferences {
  const HomeLayoutPreferences({this.hidden = const {}});

  factory HomeLayoutPreferences.fromNames(Iterable<String> names) =>
      HomeLayoutPreferences(
        hidden: Set.unmodifiable(
          HomeElement.values.where((element) => names.contains(element.name)),
        ),
      );

  final Set<HomeElement> hidden;
  bool isVisible(HomeElement element) => !hidden.contains(element);
  int get visibleCount => HomeElement.values.length - hidden.length;

  HomeLayoutPreferences withVisibility(HomeElement element, bool visible) {
    final updated = {...hidden};
    visible ? updated.remove(element) : updated.add(element);
    return HomeLayoutPreferences(hidden: Set.unmodifiable(updated));
  }

  List<String> get hiddenNames => [
    for (final element in HomeElement.values)
      if (hidden.contains(element)) element.name,
  ];
}

@immutable
class QuickSetupChoices {
  const QuickSetupChoices({
    required this.themeMode,
    required this.quality,
    required this.dynamicColor,
    required this.karaokeLyrics,
    required this.showTranslation,
    required this.efficientRendering,
    required this.privateMode,
    required this.homeLayout,
    required this.gradientPlayerBackground,
    required this.singleColorPlayerBackground,
    required this.fontWeightLevel,
    required this.lyricScrollPresetIndex,
    required this.lyricFrameRate,
  });

  final ThemeMode themeMode;
  final AudioQuality quality;
  final bool dynamicColor;
  final bool karaokeLyrics;
  final bool showTranslation;
  final bool efficientRendering;
  final bool privateMode;
  final HomeLayoutPreferences homeLayout;
  final bool gradientPlayerBackground;
  final bool singleColorPlayerBackground;
  final int fontWeightLevel;
  final int lyricScrollPresetIndex;
  final int lyricFrameRate;
}

/// One store shared by first-run setup and the regular home settings.
class ExperiencePreferences {
  ExperiencePreferences._(this._prefs, this.homeLayout, this.completed);

  static const hiddenHomeKey = 'hiddenHomeElementsV1';
  static const completedKey = 'onboardingCompletedV1';
  final SharedPreferences _prefs;
  HomeLayoutPreferences homeLayout;
  bool completed;

  static Future<ExperiencePreferences> load(SharedPreferences prefs) async {
    // Existing installations already wrote this marker. Do not interrupt
    // returning listeners with first-run setup after an application update.
    final completed =
        prefs.getBool(completedKey) ??
        prefs.containsKey('staticCoverBackgroundMigrationV1');
    if (!prefs.containsKey(completedKey)) {
      await prefs.setBool(completedKey, completed);
    }
    return ExperiencePreferences._(
      prefs,
      HomeLayoutPreferences.fromNames(prefs.getStringList(hiddenHomeKey) ?? []),
      completed,
    );
  }

  Future<void> setHomeLayout(HomeLayoutPreferences layout) async {
    final previous = homeLayout;
    homeLayout = layout;
    try {
      if (!await _prefs.setStringList(hiddenHomeKey, layout.hiddenNames)) {
        throw StateError('Unable to save home layout');
      }
    } catch (_) {
      if (identical(homeLayout, layout)) homeLayout = previous;
      rethrow;
    }
  }

  Future<void> finish({QuickSetupChoices? choices}) async {
    if (choices != null) {
      final results = await Future.wait([
        _prefs.setString('themeMode', choices.themeMode.name),
        _prefs.setInt('quality', choices.quality.index),
        _prefs.setBool('dynamicColor', choices.dynamicColor),
        _prefs.setBool('karaokeLyrics', choices.karaokeLyrics),
        _prefs.setBool('showTranslation', choices.showTranslation),
        _prefs.setBool('efficientRendering', choices.efficientRendering),
        _prefs.setBool('privateMode', choices.privateMode),
        _prefs.setBool(
          'gradientPlayerBackground',
          choices.gradientPlayerBackground,
        ),
        _prefs.setBool(
          'singleColorPlayerBackground',
          choices.singleColorPlayerBackground,
        ),
        _prefs.setInt('fontWeightLevel', choices.fontWeightLevel),
        _prefs.setInt('lyricScrollPreset', choices.lyricScrollPresetIndex),
        _prefs.setInt('lyricFrameRate', choices.lyricFrameRate),
        _prefs.setStringList(hiddenHomeKey, choices.homeLayout.hiddenNames),
      ]);
      if (results.any((saved) => !saved)) {
        throw StateError('Unable to save quick setup');
      }
    }
    // Commit this last: an interrupted save must not skip setup next launch.
    if (!await _prefs.setBool(completedKey, true)) {
      throw StateError('Unable to finish onboarding');
    }
    if (choices != null) homeLayout = choices.homeLayout;
    completed = true;
  }
}
