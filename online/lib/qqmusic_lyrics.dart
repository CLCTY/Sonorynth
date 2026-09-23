import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'qq_qrc_decoder.dart';

class QqLyricResult {
  const QqLyricResult({this.qrc = '', this.lrc = '', this.translation = ''});
  final String qrc;
  final String lrc;
  final String translation;

  bool get isNotEmpty => qrc.isNotEmpty || lrc.isNotEmpty;
}

class QqLyricCandidate {
  const QqLyricCandidate(this.track, this.songId);
  final Track track;
  final int songId;
}

/// Anonymous QQ Music lyric lookup. Audio still comes from the current source.
class QqMusicLyrics {
  static final _endpoint = Uri.parse('https://u.y.qq.com/cgi-bin/musicu.fcg');
  static final _random = Random();

  static String _base64(String text) => base64Encode(utf8.encode(text));

  Future<Map<String, dynamic>> _request(
    String module,
    String method,
    Map<String, Object> param, {
    bool liteSearch = false,
  }) async {
    final comm = <String, Object>{
      'ct': 11,
      'cv': liteSearch ? '1003006' : 14090008,
      'v': liteSearch ? '1003006' : 14090008,
      'chid': '10003505',
      'os_ver': '15',
      'phonetype': '24122RKC7C',
      'tmeAppID': liteSearch ? 'qqmusiclight' : 'qqmusic',
      'nettype': 'NETWORK_WIFI',
      'udid': '0',
      'OpenUDID': '0',
      'QIMEI36': '0',
      'uin': '0',
    };
    final response = await http
        .post(
          _endpoint,
          headers: const {
            'Content-Type': 'application/json',
            'User-Agent': 'QQMusic 14090008(android 15)',
            'Referer': 'https://y.qq.com',
            'Cookie': 'tmeLoginType=-1;',
          },
          body: jsonEncode({
            'comm': comm,
            'request': {'module': module, 'method': method, 'param': param},
          }),
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('QQ lyric HTTP ${response.statusCode}');
    }
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is! Map || body['code'] != 0) {
      throw const FormatException('QQ lyric response rejected');
    }
    final request = body['request'];
    if (request is! Map || request['code'] != 0 || request['data'] is! Map) {
      throw const FormatException('QQ lyric request rejected');
    }
    return Map<String, dynamic>.from(request['data'] as Map);
  }

  Future<List<QqLyricCandidate>> search(String keyword, {int limit = 5}) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];
    // The mobile search API expects a large decimal request identifier.
    final searchId =
        (1 + _random.nextInt(20)) * 18014398509481984 +
        _random.nextInt(4194305) * 4294967296 +
        DateTime.now().millisecondsSinceEpoch % 86400000;
    final data = await _request(
      'music.search.SearchCgiService',
      'DoSearchForQQMusicLite',
      {
        'search_id': '$searchId',
        'remoteplace': 'search.android.keyboard',
        'query': query,
        'page_num': 1,
        'num_per_page': limit.clamp(1, 20),
        'search_type': 0,
        'highlight': 0,
        'nqc_flag': 0,
        'page_id': 1,
        'grp': 1,
      },
      liteSearch: true,
    );
    final body = data['body'];
    final songs = body is Map ? body['item_song'] : null;
    if (songs is! List) return const [];
    return songs
        .whereType<Map>()
        .map((song) {
          final id = song['id'];
          final singer = song['singer'];
          final artist = singer is List
              ? singer
                    .whereType<Map>()
                    .map((s) => '${s['name'] ?? ''}')
                    .where((name) => name.isNotEmpty)
                    .join(' / ')
              : '';
          final album = song['album'];
          final seconds = song['interval'];
          final track = Track(
            id: 'qq:$id',
            title: '${song['title'] ?? ''}',
            artist: artist,
            album: album is Map ? '${album['name'] ?? ''}' : '',
            coverUrl: '',
            duration: Duration(seconds: seconds is num ? seconds.round() : 0),
          );
          return QqLyricCandidate(track, id is num ? id.toInt() : 0);
        })
        .where(
          (candidate) =>
              candidate.songId > 0 && candidate.track.title.isNotEmpty,
        )
        .toList();
  }

  static String _normal(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[(（][^)）]*[)）]'), '')
      .replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');

  /// Reject weak fuzzy matches so unrelated songs never silently replace lyrics.
  Future<QqLyricCandidate?> bestMatch(Track track) async {
    final candidates = await search(
      '${track.title} ${track.artist}',
      limit: 10,
    );
    final title = _normal(track.title);
    final artist = _normal(track.artist);
    if (title.isEmpty) return null;
    QqLyricCandidate? best;
    var bestScore = -1;
    for (final candidate in candidates) {
      final otherTitle = _normal(candidate.track.title);
      final otherArtist = _normal(candidate.track.artist);
      if (otherTitle != title ||
          (artist.isNotEmpty &&
              !otherArtist.contains(artist) &&
              (otherArtist.isEmpty || !artist.contains(otherArtist)))) {
        continue;
      }
      final seconds = track.duration.inSeconds;
      final delta = (seconds - candidate.track.duration.inSeconds).abs();
      if (seconds > 0 && candidate.track.duration.inSeconds > 0 && delta > 20) {
        continue;
      }
      final score =
          (otherArtist == artist ? 100 : 50) +
          (seconds > 0 ? max(0, 20 - delta) : 0);
      if (score > bestScore) {
        bestScore = score.toInt();
        best = candidate;
      }
    }
    return best;
  }

  Future<QqLyricResult> lyrics(QqLyricCandidate candidate) async {
    final track = candidate.track;
    final param = <String, Object>{
      'albumName': _base64(track.album),
      'crypt': 1,
      'ct': 19,
      'cv': 2111,
      'interval': track.duration.inSeconds,
      'lrc_t': 0,
      'qrc': 1,
      'qrc_t': 0,
      'roma': 1,
      'roma_t': 0,
      'singerName': _base64(track.artist),
      'songID': candidate.songId,
      'songName': _base64(track.title),
      'trans': 1,
      'trans_t': 0,
      'type': 0,
    };
    const module = 'music.musichallSong.PlayLyricInfo';
    const method = 'GetPlayLyricInfo';
    final data = await _request(module, method, param);
    String decode(dynamic value) {
      if (value is! String || value.isEmpty) return '';
      try {
        return QqQrcDecoder.decodeHex(value);
      } catch (_) {
        return '';
      }
    }

    final main = decode(data['lyric']);
    final qrc = data['qrc_t'] != 0 ? main : '';
    var lrc = data['qrc_t'] == 0 ? main : '';
    if (qrc.isNotEmpty && lrc.isEmpty) {
      try {
        final plain = await _request(module, method, {
          ...param,
          'qrc': 0,
          'qrc_t': 0,
          'roma': 0,
        });
        lrc = decode(plain['lyric']);
      } catch (_) {
        // Word-synced QRC remains usable when its plain fallback fails.
      }
    }
    return QqLyricResult(
      qrc: qrc,
      lrc: lrc,
      translation: decode(data['trans']),
    );
  }
}
