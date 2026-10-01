import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sonorynth/experience_preferences.dart';
import 'package:sonorynth/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test(
    'unfinished first launch survives the old background migration',
    () async {
      final storage = await prefs({});
      final initial = await ExperiencePreferences.load(storage);
      expect(initial.completed, isFalse);
      await storage.setBool('staticCoverBackgroundMigrationV1', true);
      final restored = await ExperiencePreferences.load(storage);
      expect(restored.completed, isFalse);
      expect(restored.homeLayout.visibleCount, HomeElement.values.length);
    },
  );

  test(
    'existing installations bypass welcome and retain their preferences',
    () async {
      final storage = await prefs({
        'staticCoverBackgroundMigrationV1': true,
        'themeMode': 'dark',
        'quality': 4,
      });
      expect((await ExperiencePreferences.load(storage)).completed, isTrue);
      expect(storage.getString('themeMode'), 'dark');
      expect(storage.getInt('quality'), 4);
    },
  );

  test(
    'home visibility restores by stable names without deleting music',
    () async {
      final storage = await prefs({'recent': '["keep"]'});
      final store = await ExperiencePreferences.load(storage);
      final first = store.setHomeLayout(
        store.homeLayout.withVisibility(HomeElement.likedSongs, false),
      );
      final second = store.setHomeLayout(
        store.homeLayout.withVisibility(HomeElement.weeklyListening, false),
      );
      await Future.wait([first, second]);
      final restored = await ExperiencePreferences.load(storage);
      expect(restored.homeLayout.hidden, {
        HomeElement.likedSongs,
        HomeElement.weeklyListening,
      });
      expect(storage.getString('recent'), '["keep"]');
      expect(
        HomeLayoutPreferences.fromNames(['future-element']).hidden,
        isEmpty,
      );
    },
  );

  test(
    'finish saves all appearance, lyrics and home choices then completion',
    () async {
      final storage = await prefs({});
      final store = await ExperiencePreferences.load(storage);
      await store.finish(
        choices: QuickSetupChoices(
          themeMode: ThemeMode.dark,
          quality: AudioQuality.standard,
          dynamicColor: false,
          karaokeLyrics: false,
          showTranslation: false,
          efficientRendering: false,
          privateMode: true,
          homeLayout: HomeLayoutPreferences(hidden: Set.of(HomeElement.values)),
          gradientPlayerBackground: true,
          singleColorPlayerBackground: true,
          fontWeightLevel: 2,
          lyricScrollPresetIndex: 2,
          lyricFrameRate: 60,
        ),
      );
      final restored = await ExperiencePreferences.load(storage);
      expect(restored.completed, isTrue);
      expect(restored.homeLayout.visibleCount, 0);
      expect(storage.getString('themeMode'), 'dark');
      expect(storage.getInt('quality'), AudioQuality.standard.index);
      for (final key in [
        'dynamicColor',
        'karaokeLyrics',
        'showTranslation',
        'efficientRendering',
      ]) {
        expect(storage.getBool(key), isFalse, reason: key);
      }
      for (final key in [
        'privateMode',
        'gradientPlayerBackground',
        'singleColorPlayerBackground',
      ]) {
        expect(storage.getBool(key), isTrue, reason: key);
      }
      expect(storage.getInt('fontWeightLevel'), 2);
      expect(storage.getInt('lyricScrollPreset'), 2);
      expect(storage.getInt('lyricFrameRate'), 60);
    },
  );

  test(
    'skip marks welcome complete without resetting existing choices',
    () async {
      final storage = await prefs({'themeMode': 'dark', 'quality': 4});
      final store = await ExperiencePreferences.load(storage);
      await store.finish();
      expect((await ExperiencePreferences.load(storage)).completed, isTrue);
      expect(storage.getString('themeMode'), 'dark');
      expect(storage.getInt('quality'), 4);
      expect(storage.containsKey(ExperiencePreferences.hiddenHomeKey), isFalse);
    },
  );
}
