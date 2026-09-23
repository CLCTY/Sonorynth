import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/lyrics_parser.dart';

void main() {
  test('parses LRC line and word timestamps', () {
    final lines = LyricsParser.parse(
      '[00:05.00]<00:05.00>Hello <00:05.50>world\n'
      '[00:09.00]Next line',
    );
    expect(lines, hasLength(2));
    expect(lines.first.text, 'Hello world');
    expect(lines.first.words, hasLength(2));
    expect(lines.first.words[1].start.inMilliseconds, 5500);
    expect(lines.first.end.inSeconds, 9);
  });

  test('merges duplicate-timestamp translation', () {
    final lines = LyricsParser.parse('[00:01.00]Morning\n[00:01.00]清晨');
    expect(lines, hasLength(1));
    expect(lines.first.translation, '清晨');
  });

  test('parses NetEase YRC karaoke words', () {
    final lines = LyricsParser.parseYrc(
      '[1000,2000](1000,500,0)你(1500,700,0)好',
    );
    expect(lines.single.words, hasLength(2));
    expect(lines.single.text, '你好');
    expect(
      LyricsParser.activeLine(lines, const Duration(milliseconds: 1600)),
      0,
    );
  });

  test('merges translation into NetEase YRC lines', () {
    final lines = LyricsParser.parseYrc(
      '[1000,2000](1000,500,0)Hello',
      translation: '[00:01.00]你好',
    );
    expect(lines.single.translation, '你好');
  });

  test('parses AMLL TTML word timestamps', () {
    final lines = LyricsParser.parseTtml(
      '<tt><body><div><p begin="00:01.000" end="00:03.000">'
      '<span begin="00:01.000" end="00:01.500">你</span>'
      '<span begin="00:01.500" end="00:02.000">好</span>'
      '</p></div></body></tt>',
    );
    expect(lines.single.text, '你好');
    expect(lines.single.words, hasLength(2));
    expect(lines.single.words.last.end.inMilliseconds, 2000);
  });

  test('parses AMLL duet sides and timed background vocals', () {
    final lines = LyricsParser.parseTtml(
      '<tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>'
      '<p begin="1s" end="4s" ttm:agent="v1">'
      '<span begin="1s" end="2s">主唱</span>'
      '<span ttm:role="x-bg" begin="2s" end="4s">'
      '<span begin="2s" end="3s">和</span>'
      '<span begin="3s" end="4s">声</span>'
      '</span></p>'
      '<p begin="2s" end="5s" ttm:agent="v2">'
      '<span begin="2s" end="5s">对唱</span>'
      '</p></div></body></tt>',
    );
    expect(lines, hasLength(2));
    expect(lines.first.alignRight, isFalse);
    expect(lines.last.alignRight, isTrue);
    expect(lines.first.backgroundText, '和声');
    expect(lines.first.backgroundWords, hasLength(2));
  });

  test('parses AMLL seconds-only timestamps', () {
    final lines = LyricsParser.parseTtml(
      '<tt><body><p begin="45.404" end="48.709">'
      '<span begin="45.404" end="45.755">金</span>'
      '<span begin="45.755" end="46.696">色</span>'
      '</p></body></tt>',
    );
    expect(lines, hasLength(1));
    expect(lines.single.start.inMilliseconds, 45404);
    expect(lines.single.words, hasLength(2));
    expect(lines.single.words.last.end.inMilliseconds, 46696);
  });

  test('parses AMLL single-digit minute clock timestamps', () {
    final lines = LyricsParser.parseTtml(
      '<tt><body><p begin="58.769" end="1:02.927">'
      '<span begin="58.769" end="1:00.100">一</span>'
      '<span begin="1:00.100" end="1:02.927">分钟后</span>'
      '</p></body></tt>',
    );
    expect(lines, hasLength(1));
    expect(lines.single.end.inMilliseconds, 62927);
    expect(lines.single.words, hasLength(2));
    expect(lines.single.words.last.start.inMilliseconds, 60100);
  });

  test('parses nested AMLL words instead of collapsing their timing', () {
    final lines = LyricsParser.parseTtml(
      '<tt><body><p begin="1" end="4" ttm:agent="v1" '
      'xmlns:ttm="http://www.w3.org/ns/ttml#metadata">'
      '<span><span begin="1" end="2">对</span>'
      '<span begin="2" end="3">唱</span></span>'
      '</p></body></tt>',
    );
    expect(lines.single.text, '对唱');
    expect(lines.single.words, hasLength(2));
  });

  test('preserves spaces between timed AMLL English words', () {
    final lines = LyricsParser.parseTtml(
      '<tt><body><p begin="1" end="4">'
      '<span begin="1" end="2">Hello</span> '
      '<span begin="2" end="3">beautiful</span> '
      '<span begin="3" end="4">world</span>'
      '</p></body></tt>',
    );
    expect(lines.single.text, 'Hello beautiful world');
    expect(
      lines.single.words.map((word) => word.text).join(),
      'Hello beautiful world',
    );
  });

  test('uses an x-bg container timestamp for untokenized harmony', () {
    final lines = LyricsParser.parseTtml(
      '<tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body>'
      '<p begin="1" end="5"><span begin="1" end="2">主唱</span>'
      '<span ttm:role="x-bg" begin="2.2" end="4.8">和声</span>'
      '</p></body></tt>',
    );
    expect(lines.single.backgroundText, '和声');
    expect(lines.single.backgroundWords, hasLength(1));
    expect(lines.single.backgroundWords.single.start.inMilliseconds, 2200);
  });

  test('links Apple Music style AMLL translations by line key', () {
    final lines = LyricsParser.parseTtml(
      '<tt xmlns:itunes="http://music.apple.com/lyric-ttml-internal">'
      '<head><metadata><iTunesMetadata><translations>'
      '<translation xml:lang="zh-CN"><text for="L1">翻译内容</text>'
      '</translation></translations></iTunesMetadata></metadata></head>'
      '<body><p begin="1" end="2" itunes:key="L1">'
      '<span begin="1" end="2">Original</span></p></body></tt>',
    );
    expect(lines.single.translation, '翻译内容');
  });

  test('removes explicit songwriting credits without touching lyric text', () {
    final lines = LyricsParser.withoutCredits(
      LyricsParser.parse(
        '[00:01.00]作词：Alice\n'
        '[00:02.00]作曲 / Bob\n'
        '[00:03.00]词：Carol\n'
        '[00:04.00]曲: David\n'
        '[00:05.00]Lyrics by Eve\n'
        '[00:06.00]Composed by Frank\n'
        '[00:07.00]Composer | Grace\n'
        '[00:08.00]我把作词写进这句歌词\n'
        '[00:09.00]真正的歌词',
      ),
    );
    expect(lines.map((line) => line.text), ['我把作词写进这句歌词', '真正的歌词']);
    expect(lines.first.start, const Duration(seconds: 8));
  });

  test('removes platform instrumental placeholder text', () {
    final parsed = LyricsParser.parse(
      '[00:01.00]纯音乐，请欣赏\n'
      '[00:02.00]此歌曲为纯音乐',
    );
    expect(LyricsParser.containsInstrumentalPlaceholder(parsed), isTrue);
    final lines = LyricsParser.withoutCredits(parsed);
    expect(lines, isEmpty);
  });
}
