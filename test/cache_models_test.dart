import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonorynth/lyrics_parser.dart';
import 'package:sonorynth/models.dart';
import 'package:sonorynth/netease_api.dart';

void main() {
  test('lyrics payload survives persistent cache serialization', () {
    const payload = LyricsPayload(
      lrc: '[00:01]普通歌词',
      translation: '[00:01]translation',
      ttml: '<tt><body /></tt>',
      qrc: '<QrcInfos />',
    );
    final restored = LyricsPayload.fromJson(payload.toJson());
    expect(restored.lrc, payload.lrc);
    expect(restored.translation, payload.translation);
    expect(restored.ttml, payload.ttml);
    expect(restored.qrc, payload.qrc);
    expect(restored.isWordSynced, isTrue);
  });

  test('AMLL TTML is decoded as UTF-8 instead of HTTP Latin-1', () {
    const xml =
        '<tt xmlns="http://www.w3.org/ns/ttml"><body><p>星も空も光も</p></body></tt>';
    final decoded = extractTtmlDocument(decodeTtmlBytes(utf8.encode(xml)));
    expect(decoded, contains('星も空も光も'));
    expect(decoded, isNot(contains('æ˜Ÿ')));
  });

  test('AMLL mirror JSON wrapper is normalized to a TTML document', () {
    const xml = '<tt><body><p>逐字歌词</p></body></tt>';
    final wrapped = jsonEncode({
      'data': {'ttml': xml},
    });
    expect(extractTtmlDocument(wrapped), xml);
  });

  test('lyric choice only advertises genuinely parsed word timing', () {
    const track = Track(
      id: '1',
      title: '歌曲',
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
    );
    const plainTtml = LyricChoice(
      track: track,
      payload: LyricsPayload(
        ttml: '<tt><body><p begin="1" end="2">整行</p></body></tt>',
      ),
    );
    const wordTtml = LyricChoice(
      track: track,
      payload: LyricsPayload(
        ttml:
            '<tt><body><p begin="1" end="2">'
            '<span begin="1" end="2">字</span></p></body></tt>',
      ),
    );
    expect(plainTtml.isWordSynced, isFalse);
    expect(wordTtml.isWordSynced, isTrue);
  });

  test('cached playlist keeps its loaded track detail', () {
    const track = Track(
      id: '1',
      title: '歌曲',
      artist: '歌手',
      album: '专辑',
      coverUrl: 'https://example.com/cover.jpg',
    );
    const playlist = MusicPlaylist(
      id: '2',
      name: '歌单',
      coverUrl: 'https://example.com/list.jpg',
      tracks: [track],
      trackCount: 1,
    );
    final restored = MusicPlaylist.fromJson(playlist.toJson());
    expect(restored.tracks.single.title, '歌曲');
    expect(restored.displayTrackCount, 1);
    expect(restored.hasCompleteTrackDetail, isTrue);
  });

  test('playlist detail becomes stale when server track count changes', () {
    const track = Track(
      id: '1',
      title: '旧歌曲',
      artist: '歌手',
      album: '专辑',
      coverUrl: '',
    );
    const stale = MusicPlaylist(
      id: '2',
      name: '歌单',
      coverUrl: '',
      tracks: [track],
      trackCount: 2,
    );
    expect(stale.hasCompleteTrackDetail, isFalse);
  });

  test('listening statistics retain daily time, plays and streaks', () {
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    var stats = const ListeningStats();
    stats = stats.add(
      const Duration(seconds: 40),
      newPlay: true,
      now: twoDaysAgo,
    );
    stats = stats.add(
      const Duration(seconds: 50),
      newPlay: true,
      now: yesterday,
    );
    stats = stats.add(const Duration(seconds: 70), newPlay: true, now: today);
    stats = stats.add(const Duration(seconds: 30), now: today);
    stats = stats.add(const Duration(milliseconds: 500), now: today);
    stats = stats.add(const Duration(milliseconds: 500), now: today);
    final restored = ListeningStats.fromJson(stats.toJson());
    expect(restored.todaySeconds, 101);
    expect(restored.todayPlays, 1);
    expect(restored.totalPlays, 3);
    expect(restored.streakDays, 3);
  });

  test(
    'lyrics insert an interlude only for a gap of at least five seconds',
    () {
      const lines = [
        LyricLine(
          start: Duration(seconds: 1),
          end: Duration(seconds: 3),
          text: '第一句',
        ),
        LyricLine(
          start: Duration(seconds: 9),
          end: Duration(seconds: 11),
          text: '第二句',
        ),
        LyricLine(
          start: Duration(seconds: 14),
          end: Duration(seconds: 16),
          text: '第三句',
        ),
      ];
      final result = LyricsParser.withInterludes(lines);
      expect(result.where((line) => line.isInterlude), hasLength(1));
      final interlude = result.firstWhere((line) => line.isInterlude);
      expect(interlude.start, const Duration(seconds: 3));
      expect(interlude.end, const Duration(seconds: 9));
    },
  );
}
