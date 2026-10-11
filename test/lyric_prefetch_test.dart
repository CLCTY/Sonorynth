import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sonorynth/app_state.dart';
import 'package:sonorynth/audio_handler.dart';
import 'package:sonorynth/models.dart';
import 'package:sonorynth/netease_api.dart';

class PrefetchPlayer implements AudioPlayer {
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PrefetchHandler implements MelodyAudioHandler {
  @override
  final AudioPlayer player = PrefetchPlayer();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PendingSources implements SourceResolver {
  @override
  Future<Uri?> resolve(Track track, AudioQuality quality) =>
      Completer<Uri?>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class PrefetchApi implements NeteaseApi {
  final requests = <(Track, Completer<List<LyricChoice>>)>[];
  @override
  Future<List<LyricChoice>> searchLyrics(
    String keyword, {
    int limit = 5,
    Track? preferredTrack,
  }) {
    final done = Completer<List<LyricChoice>>();
    requests.add((preferredTrack!, done));
    return done.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #lyrics) {
      return Future.value(const LyricsPayload(lrc: '[00:00.00]cached lyrics'));
    }
    return null;
  }
}

const first = Track(
  id: 'first',
  title: 'First',
  artist: 'Artist',
  album: '',
  coverUrl: '',
);
const second = Track(
  id: 'second',
  title: 'Second',
  artist: 'Artist',
  album: '',
  coverUrl: '',
);
LyricChoice candidate(Track track) => LyricChoice(
  track: track,
  payload: const LyricsPayload(lrc: '[00:00.00]text'),
);

void main() {
  test(
    'playing a song preloads candidates before any picker is opened',
    () async {
      final api = PrefetchApi();
      final state = MelodyState(PrefetchHandler())
        ..api = api
        ..sources = PendingSources();
      addTearDown(state.dispose);
      unawaited(state.playTrack(first));
      expect(api.requests.length, 1);
      expect(state.searchingLyrics, isTrue);
      api.requests.first.$2.complete([candidate(first)]);
      await Future<void>.delayed(Duration.zero);
      expect(state.lyricChoices.single.track.id, first.id);
      expect(state.searchingLyrics, isFalse);
      // Reopening / returning to a song uses its ready cached list.
      await state.prepareLyricChoices();
      expect(api.requests.length, 1);
      expect(state.lyricChoicesTrackId, first.id);
    },
  );

  test(
    'late results from the previous song cannot replace the new song list',
    () async {
      final api = PrefetchApi();
      final state = MelodyState(PrefetchHandler())
        ..api = api
        ..sources = PendingSources();
      addTearDown(state.dispose);
      unawaited(state.playTrack(first));
      unawaited(state.playTrack(second));
      expect(api.requests.length, 2);
      api.requests[0].$2.complete([candidate(first)]);
      await Future<void>.delayed(Duration.zero);
      expect(state.lyricChoices, isEmpty);
      expect(state.lyricChoicesTrackId, second.id);
      expect(state.searchingLyrics, isTrue);
      api.requests[1].$2.complete([candidate(second)]);
      await Future<void>.delayed(Duration.zero);
      expect(state.lyricChoices.single.track.id, second.id);
      expect(state.searchingLyrics, isFalse);
      unawaited(state.playTrack(first));
      expect(api.requests.length, 2);
      expect(state.lyricChoices.single.track.id, first.id);
    },
  );
}
