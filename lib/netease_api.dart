import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'lyrics_parser.dart';
import 'netease_local_api.dart';

String decodeTtmlBytes(List<int> bytes) {
  if (bytes.isEmpty) return '';
  if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
    final units = <int>[];
    for (var index = 2; index + 1 < bytes.length; index += 2) {
      units.add(bytes[index] | (bytes[index + 1] << 8));
    }
    return String.fromCharCodes(units).replaceFirst('\ufeff', '');
  }
  if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
    final units = <int>[];
    for (var index = 2; index + 1 < bytes.length; index += 2) {
      units.add((bytes[index] << 8) | bytes[index + 1]);
    }
    return String.fromCharCodes(units).replaceFirst('\ufeff', '');
  }
  return utf8.decode(bytes, allowMalformed: false).replaceFirst('\ufeff', '');
}

String extractTtmlDocument(String source) {
  var text = source.trim();
  if (text.startsWith('{')) {
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        dynamic candidate = json['ttml'] ?? json['content'] ?? json['data'];
        if (candidate is Map<String, dynamic>) {
          candidate = candidate['ttml'] ?? candidate['content'];
        }
        if (candidate is String) text = candidate.trim();
      }
    } catch (_) {
      return '';
    }
  }
  final start = text.indexOf(RegExp(r'<tt(?:\s|>)'));
  final end = text.lastIndexOf('</tt>');
  if (start < 0 || end < start) return '';
  return text.substring(start, end + 5);
}

class QrLoginSession {
  const QrLoginSession({required this.key, required this.url});
  final String key;
  final String url;
}

class QrLoginResult {
  const QrLoginResult(this.code, this.message, {this.cookie});
  final int code;
  final String message;
  final String? cookie;
}

class LyricsPayload {
  const LyricsPayload({
    this.lrc = '',
    this.translation = '',
    this.yrc = '',
    this.ttml = '',
    this.krc = '',
  });
  final String lrc;
  final String translation;
  final String yrc;
  final String ttml;
  final String krc;

  bool get isWordSynced =>
      ttml.trim().isNotEmpty || krc.trim().isNotEmpty || yrc.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'lrc': lrc,
    'translation': translation,
    'yrc': yrc,
    'ttml': ttml,
    'krc': krc,
  };

  factory LyricsPayload.fromJson(Map<String, dynamic> json) => LyricsPayload(
    lrc: '${json['lrc'] ?? ''}',
    translation: '${json['translation'] ?? ''}',
    yrc: '${json['yrc'] ?? ''}',
    ttml: '${json['ttml'] ?? ''}',
    krc: '${json['krc'] ?? ''}',
  );
}

class LyricChoice {
  const LyricChoice({
    required this.track,
    required this.payload,
    this.source = '网易云音乐',
  });
  final Track track;
  final LyricsPayload payload;
  final String source;
  bool get isWordSynced {
    try {
      if (payload.ttml.trim().isNotEmpty) {
        final parsed = LyricsParser.parseTtml(payload.ttml);
        if (parsed.any(
          (line) => line.words.isNotEmpty || line.backgroundWords.isNotEmpty,
        )) {
          return true;
        }
      }
      if (payload.krc.trim().isNotEmpty &&
          LyricsParser.parseKrc(
            payload.krc,
          ).any((line) => line.words.isNotEmpty)) {
        return true;
      }
      if (payload.yrc.trim().isNotEmpty &&
          LyricsParser.parseYrc(
            payload.yrc,
          ).any((line) => line.words.isNotEmpty)) {
        return true;
      }
    } catch (_) {
      // A malformed document must not be advertised as word-synchronised.
    }
    return false;
  }
}

class NeteaseProfile {
  const NeteaseProfile({
    required this.userId,
    required this.nickname,
    this.avatarUrl = '',
  });
  final String userId;
  final String nickname;
  final String avatarUrl;
}

/// In-app NetEase client. Requests are encrypted and sent from the Android
/// process directly; no separately deployed API server is required.
class NeteaseApi {
  NeteaseApi({NeteaseLocalApi? local}) : local = local ?? NeteaseLocalApi();
  final NeteaseLocalApi local;

  bool get hasAuthenticatedSession => local.session.isAuthenticated;

  Future<void> initialize() => local.initialize();

  Future<List<Track>> search(String keyword, {int limit = 30}) async {
    final data = await local.request('/api/cloudsearch/pc', {
      's': keyword,
      'type': 1,
      'limit': limit,
      'offset': 0,
      'total': true,
    });
    final result = data['result'] as Map<String, dynamic>? ?? const {};
    return _tracks(result['songs']);
  }

  Future<List<String>> hotSearch() async {
    final data = await local.request('/api/search/hot', const {'type': 1111});
    final result = data['result'] as Map<String, dynamic>? ?? const {};
    return ((result['hots'] ?? []) as List<dynamic>)
        .map((item) => '${(item as Map<String, dynamic>)['first'] ?? ''}')
        .where((value) => value.isNotEmpty)
        .take(12)
        .toList();
  }

  Future<List<Track>> personalizedSongs() async {
    if (hasAuthenticatedSession) {
      try {
        final daily = await local.request(
          '/api/v3/discovery/recommend/songs',
          const {},
          mode: NeteaseCryptoMode.weapi,
        );
        final value = daily['data'] as Map<String, dynamic>?;
        final tracks = _tracks(value?['dailySongs']);
        if (tracks.isNotEmpty) return tracks;
      } catch (_) {
        // Public recommendation below remains available if session expired.
      }
    }
    return const [];
  }

  Future<List<MusicPlaylist>> recommendedPlaylists({int limit = 12}) async {
    if (hasAuthenticatedSession) {
      try {
        final data = await local.request(
          '/api/v1/discovery/recommend/resource',
          const {},
          mode: NeteaseCryptoMode.weapi,
        );
        final values = _playlists(data['recommend']);
        if (values.isNotEmpty) return values;
      } catch (_) {}
    }
    final data = await local.request('/api/personalized/playlist', {
      'limit': limit,
      'total': true,
      'n': 1000,
    }, mode: NeteaseCryptoMode.weapi);
    return _playlists(data['result']);
  }

  Future<NeteaseProfile?> account() async {
    final data = await local.request(
      '/api/w/nuser/account/get',
      const {},
      mode: NeteaseCryptoMode.weapi,
    );
    final root = data['data'] as Map<String, dynamic>? ?? data;
    final profile = root['profile'] as Map<String, dynamic>?;
    final account = root['account'] as Map<String, dynamic>?;
    final id = profile?['userId'] ?? account?['id'];
    if (id == null) return null;
    return NeteaseProfile(
      userId: '$id',
      nickname: '${profile?['nickname'] ?? '网易云用户'}',
      avatarUrl: '${profile?['avatarUrl'] ?? ''}',
    );
  }

  Future<List<MusicPlaylist>> userPlaylists(String userId) async {
    final data = await local.request('/api/user/playlist', {
      'uid': userId,
      'limit': 1000,
      'offset': 0,
      'includeVideo': true,
    }, mode: NeteaseCryptoMode.weapi);
    return _playlists(data['playlist']);
  }

  Future<MusicPlaylist?> createPlaylist(String name) async {
    final data = await local.request('/api/playlist/create', {
      'name': name,
      'privacy': 0,
    }, mode: NeteaseCryptoMode.weapi);
    final playlist = data['playlist'] as Map<String, dynamic>?;
    return playlist == null ? null : MusicPlaylist.fromNetease(playlist);
  }

  Future<bool> addTracks(String playlistId, List<String> trackIds) async {
    final data = await local.request('/api/playlist/manipulate/tracks', {
      'op': 'add',
      'pid': playlistId,
      'trackIds': jsonEncode(trackIds),
      'imme': 'true',
    });
    return data['code'] == 200;
  }

  Future<MusicPlaylist> playlistDetail(String id) async {
    final data = await local.request('/api/v6/playlist/detail', {
      'id': id,
      'n': 100000,
      's': 8,
      // The request header already has a unique requestId; this field also
      // prevents intermediary/CDN reuse of a recently fetched playlist body.
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    final playlist = data['playlist'] as Map<String, dynamic>? ?? const {};
    var tracks = _tracks(playlist['tracks']);
    final ids = ((playlist['trackIds'] ?? []) as List<dynamic>)
        .map((item) {
          if (item is Map<String, dynamic>) return '${item['id'] ?? ''}';
          if (item is Map) return '${item['id'] ?? ''}';
          return '$item';
        })
        .where((id) => id.isNotEmpty && id != 'null')
        .toSet()
        .toList();
    if (ids.isNotEmpty) {
      final loaded = <Track>[];
      for (var offset = 0; offset < ids.length; offset += 300) {
        final batch = ids.sublist(offset, min(offset + 300, ids.length));
        final detail = await local.request('/api/v3/song/detail', {
          'c': jsonEncode(
            batch.map((id) => {'id': int.tryParse(id) ?? id}).toList(),
          ),
        });
        loaded.addAll(_tracks(detail['songs']));
      }
      if (loaded.isNotEmpty) {
        final byId = {for (final track in loaded) track.id: track};
        final embeddedById = {for (final track in tracks) track.id: track};
        // Preserve playlist order. If song/detail omits a restricted item,
        // retain its embedded metadata instead of shifting every later row.
        tracks = ids
            .map((id) => byId[id] ?? embeddedById[id])
            .whereType<Track>()
            .toList();
      }
    }
    return MusicPlaylist.fromNetease(playlist, tracks: tracks);
  }

  Future<String?> songUrl(String id, AudioQuality quality) async {
    final data = await local.request('/api/song/enhance/player/url/v1', {
      'ids': '[$id]',
      'level': quality.apiValue,
      'encodeType': 'flac',
    });
    final list = (data['data'] ?? []) as List<dynamic>;
    if (list.isEmpty) return null;
    final item = list.first as Map<String, dynamic>;
    if (item['freeTrialInfo'] != null) return null;
    final url = item['url'] as String?;
    if (item['code'] != 200 || url == null || url.isEmpty) return null;
    return url;
  }

  Future<LyricsPayload> lyrics(
    String id, {
    Track? track,
    bool includeKugou = true,
  }) async {
    if (!RegExp(r'^\d+$').hasMatch(id) && track != null) {
      try {
        final matches = await search(
          '${track.title} ${track.artist}'.trim(),
          limit: 5,
        );
        if (matches.isNotEmpty) {
          return lyrics(
            matches.first.id,
            track: track,
            includeKugou: includeKugou,
          );
        }
      } catch (_) {
        // A third-party catalog item can still use Kugou's fuzzy lyric match.
      }
      final kugou = includeKugou ? await _bestKugouLyrics(track) : null;
      return kugou ?? const LyricsPayload();
    }
    final amll = _amllLyrics(id);
    Map<String, dynamic> data = const {};
    try {
      data = await local.request('/api/song/lyric/v1', {
        'id': id,
        'cp': false,
        'tv': -1,
        'lv': -1,
        'rv': -1,
        'kv': -1,
        'yv': -1,
        'ytv': -1,
        'yrv': -1,
      });
    } catch (_) {
      // AMLL and Kugou remain available when the platform lyric API fails.
    }
    String value(String key) =>
        '${(data[key] as Map<String, dynamic>?)?['lyric'] ?? ''}';
    final ttml = await amll;
    final kugou = ttml.isEmpty && track != null && includeKugou
        ? await _bestKugouLyrics(track)
        : null;
    final neteaseLrc = value('lrc');
    return LyricsPayload(
      lrc: neteaseLrc.isNotEmpty ? neteaseLrc : kugou?.lrc ?? '',
      translation: value('tlyric'),
      yrc: value('yrc'),
      ttml: ttml,
      krc: kugou?.krc ?? '',
    );
  }

  Future<String> _amllLyrics(String id) async {
    final encoded = Uri.encodeComponent(id);
    final urls = <String>[
      'https://amll-ttml-db.gbclstudio.cn/ncm-lyrics/$encoded.ttml',
      'https://amll.mirror.dimeta.top/api/db/ncm-lyrics/$encoded.ttml',
      'https://amlldb.bikonoo.com/ncm-lyrics/$encoded.ttml',
    ];
    for (final url in urls) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 2));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          final document = extractTtmlDocument(
            decodeTtmlBytes(response.bodyBytes),
          );
          if (document.isNotEmpty) return document;
        }
      } catch (_) {
        // Continue to the next community mirror after two seconds.
      }
    }
    return '';
  }

  Future<List<LyricChoice>> searchLyrics(
    String keyword, {
    int limit = 5,
    Track? preferredTrack,
  }) async {
    List<Track> searched = const [];
    try {
      searched = await search(keyword, limit: limit);
    } catch (_) {
      // Preferred track and Kugou fuzzy search remain available.
    }
    final tracks = <Track>[
      if (preferredTrack != null && preferredTrack.id.isNotEmpty)
        preferredTrack,
      ...searched.where((track) => track.id != preferredTrack?.id),
    ];
    final choicesFuture = Future.wait(
      tracks.map((track) async {
        try {
          final payload = await lyrics(
            track.id,
            track: track,
            includeKugou: false,
          );
          return LyricChoice(
            track: track,
            payload: payload,
            source: payload.ttml.isNotEmpty
                ? 'AMLL TTML DB'
                : payload.krc.isNotEmpty
                ? '酷狗 KRC'
                : '网易云音乐',
          );
        } catch (_) {
          return const LyricChoice(
            track: Track(
              id: '',
              title: '',
              artist: '',
              album: '',
              coverUrl: '',
            ),
            payload: LyricsPayload(),
          );
        }
      }),
    );
    final kugouFuture = _searchKugouLyrics(
      keyword,
      preferredTrack: preferredTrack,
    );
    final choices = await choicesFuture;
    final valid = choices
        .where((choice) => choice.track.id.isNotEmpty)
        .toList();
    final kugou = await kugouFuture;
    final amll = valid.where((choice) => choice.payload.ttml.isNotEmpty);
    final neteaseKaraoke = valid.where(
      (choice) => choice.payload.ttml.isEmpty && choice.payload.yrc.isNotEmpty,
    );
    final neteasePlain = valid.where(
      (choice) => choice.payload.ttml.isEmpty && choice.payload.yrc.isEmpty,
    );
    return [...amll, ...neteaseKaraoke, ...kugou, ...neteasePlain];
  }

  Future<LyricsPayload?> _bestKugouLyrics(Track track) async {
    final candidates = await _kugouCandidates('${track.artist} ${track.title}');
    if (candidates.isEmpty) return null;
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[（(][^）)]*[）)]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final title = normalize(track.title);
    final artist = normalize(track.artist);
    int score(Map<String, dynamic> item) {
      final song = normalize('${item['song'] ?? ''}');
      final singer = normalize('${item['singer'] ?? ''}');
      return (song == title
              ? 4
              : song.contains(title)
              ? 2
              : 0) +
          (artist.isNotEmpty && singer.contains(artist) ? 2 : 0);
    }

    candidates.sort((left, right) => score(right).compareTo(score(left)));
    return _downloadKugouLyrics(candidates.first);
  }

  Future<List<LyricChoice>> _searchKugouLyrics(
    String keyword, {
    Track? preferredTrack,
  }) async {
    final candidates = (await _kugouCandidates(keyword)).take(4).toList();
    final values = await Future.wait(
      candidates.map((candidate) async {
        final payload = await _downloadKugouLyrics(candidate);
        if (payload == null) return null;
        return LyricChoice(
          track: Track(
            id: 'kugou-${candidate['id']}',
            title: '${candidate['song'] ?? '未知歌曲'}',
            artist: '${candidate['singer'] ?? '未知歌手'}',
            album: '',
            coverUrl: preferredTrack?.coverUrl ?? '',
          ),
          payload: payload,
          source: payload.krc.isNotEmpty ? '酷狗 KRC' : '酷狗 LRC',
        );
      }),
    );
    return values.whereType<LyricChoice>().toList();
  }

  Future<List<Map<String, dynamic>>> _kugouCandidates(String keyword) async {
    try {
      final uri = Uri.https('lyrics.kugou.com', '/search', {
        'ver': '1',
        'man': 'yes',
        'client': 'pc',
        'keyword': keyword,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return const [];
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return ((data['candidates'] ?? []) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<LyricsPayload?> _downloadKugouLyrics(
    Map<String, dynamic> candidate,
  ) async {
    final id = '${candidate['id'] ?? ''}';
    final accessKey = '${candidate['accesskey'] ?? ''}';
    if (id.isEmpty || accessKey.isEmpty) return null;
    Future<String?> download(String format) async {
      final uri = Uri.https('lyrics.kugou.com', '/download', {
        'ver': '1',
        'client': 'pc',
        'id': id,
        'accesskey': accessKey,
        'fmt': format,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return data['content'] as String?;
    }

    try {
      final content = await download('krc');
      if (content != null && content.isNotEmpty) {
        return LyricsPayload(krc: _decodeKrc(content));
      }
    } catch (_) {}
    try {
      final content = await download('lrc');
      if (content != null && content.isNotEmpty) {
        return LyricsPayload(lrc: utf8.decode(base64Decode(content)));
      }
    } catch (_) {}
    return null;
  }

  static String _decodeKrc(String content) {
    const key = <int>[
      64,
      71,
      97,
      119,
      94,
      50,
      116,
      71,
      81,
      54,
      49,
      45,
      206,
      210,
      110,
      105,
    ];
    final raw = base64Decode(content);
    if (raw.length <= 4) throw const FormatException('KRC 数据过短');
    final encrypted = raw.sublist(4);
    final decoded = List<int>.generate(
      encrypted.length,
      (index) => encrypted[index] ^ key[index % key.length],
    );
    return utf8.decode(ZLibDecoder().convert(decoded));
  }

  Future<QrLoginSession> createQrLogin() async {
    final data = await local.request('/api/login/qrcode/unikey', {'type': 3});
    final key =
        '${data['unikey'] ?? (data['data'] as Map<String, dynamic>?)?['unikey'] ?? ''}';
    if (key.isEmpty) throw const NeteaseRequestException('二维码 key 获取失败');
    return QrLoginSession(
      key: key,
      url: 'https://music.163.com/login?codekey=$key',
    );
  }

  Future<QrLoginResult> checkQr(String key) async {
    final data = await local.request('/api/login/qrcode/client/login', {
      'key': key,
      'type': 3,
    });
    final code = data['code'] as int? ?? 801;
    final cookie = data['cookie'] as String?;
    if (cookie != null && cookie.isNotEmpty) {
      await local.session.mergeCookieString(cookie);
    }
    return QrLoginResult(code, switch (code) {
      800 => '二维码已过期',
      801 => '等待扫码',
      802 => '已扫码，请在手机上确认',
      803 => '登录成功',
      _ => '${data['message'] ?? '状态 $code'}',
    }, cookie: cookie);
  }

  Future<void> sendPhoneCaptcha(
    String phone, {
    String countryCode = '86',
  }) async {
    final data = await local.request('/api/sms/captcha/sent', {
      'cellphone': phone,
      'ctcode': countryCode,
      'secrete': 'music_middleuser_pclogin',
    }, mode: NeteaseCryptoMode.weapi);
    if (data['code'] != 200) {
      throw NeteaseRequestException(
        '${data['message'] ?? data['msg'] ?? '验证码发送失败'}',
        code: int.tryParse('${data['code'] ?? ''}'),
        body: data,
      );
    }
  }

  Future<void> loginWithPhoneCaptcha(
    String phone,
    String captcha, {
    String countryCode = '86',
  }) async {
    final verification = await local.request('/api/sms/captcha/verify', {
      'cellphone': phone,
      'ctcode': countryCode,
      'captcha': captcha,
    }, mode: NeteaseCryptoMode.weapi);
    if (verification['code'] != 200) {
      throw NeteaseRequestException(
        '${verification['message'] ?? verification['msg'] ?? '验证码校验失败'}',
        code: int.tryParse('${verification['code'] ?? ''}'),
        body: verification,
      );
    }
    final data = await local.request('/api/w/login/cellphone', {
      'type': '1',
      'https': 'true',
      'phone': phone,
      'countrycode': countryCode,
      'captcha': captcha,
      'remember': 'true',
      'secureCaptcha': '',
    }, mode: NeteaseCryptoMode.weapi);
    final cookie = '${data['cookie'] ?? ''}';
    if (cookie.isNotEmpty) await local.session.mergeCookieString(cookie);
    if (data['code'] != 200 || !local.session.isAuthenticated) {
      throw NeteaseRequestException(
        '${data['message'] ?? data['msg'] ?? '手机号登录失败'}',
        code: int.tryParse('${data['code'] ?? ''}'),
        body: data,
      );
    }
  }

  Future<void> importCookie(String cookie) =>
      local.session.mergeCookieString(cookie);

  Future<void> logout() => local.session.clear();

  Future<bool> like(String id, bool value) async {
    final data = await local.request('/api/song/like', {
      'trackId': id,
      'like': value,
      'time': 3,
    }, mode: NeteaseCryptoMode.weapi);
    return data['code'] == 200;
  }

  Future<Set<String>> likedIds(String userId) async {
    final data = await local.request('/api/song/like/get', {
      'uid': userId,
    }, mode: NeteaseCryptoMode.weapi);
    return ((data['ids'] ?? []) as List<dynamic>).map((id) => '$id').toSet();
  }

  Future<List<Track>> listeningHistory(String userId) async {
    final data = await local.request('/api/v1/play/record', {
      'uid': userId,
      'type': 1,
    }, mode: NeteaseCryptoMode.weapi);
    final entries =
        (data['weekData'] ?? data['allData'] ?? []) as List<dynamic>;
    return entries.map((entry) {
      final item = entry as Map<String, dynamic>;
      return Track.fromNetease(item['song'] as Map<String, dynamic>);
    }).toList();
  }

  static List<Track> _tracks(dynamic value) => ((value ?? []) as List<dynamic>)
      .map((item) => Track.fromNetease(item as Map<String, dynamic>))
      .toList();

  static List<MusicPlaylist> _playlists(dynamic value) =>
      ((value ?? []) as List<dynamic>)
          .map(
            (item) => MusicPlaylist.fromNetease(item as Map<String, dynamic>),
          )
          .toList();
}

abstract interface class AuthorizedSourceAdapter {
  Future<Uri?> resolve(Track track, AudioQuality quality);
}

abstract interface class RejectableSourceAdapter {
  void reject(Track track, AudioQuality quality, Uri uri);
}

class NeteaseOfficialAdapter implements AuthorizedSourceAdapter {
  NeteaseOfficialAdapter(this.api);
  final NeteaseApi api;
  @override
  Future<Uri?> resolve(Track track, AudioQuality quality) async {
    if (track.audioUrl != null) return Uri.tryParse(track.audioUrl!);
    if (track.id.isEmpty) return null;
    final value = await api.songUrl(track.id, quality);
    return value == null ? null : Uri.tryParse(value);
  }
}

/// Adapter for a source service the user owns or is authorized to access.
class UserEndpointAdapter implements AuthorizedSourceAdapter {
  UserEndpointAdapter(this.endpoint);
  final String endpoint;
  @override
  Future<Uri?> resolve(Track track, AudioQuality quality) async {
    if (endpoint.trim().isEmpty) return null;
    final uri = Uri.parse(endpoint).replace(
      queryParameters: {
        'id': track.id,
        'quality': quality.apiValue,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return Uri.tryParse('${data['url'] ?? ''}');
  }
}

class SourceResolver {
  SourceResolver(this.adapters);
  final List<AuthorizedSourceAdapter> adapters;
  final Map<String, _ResolvedSource> _cache = {};
  final Map<String, Future<Uri?>> _pending = {};
  final Map<String, Set<String>> _rejected = {};
  final Map<String, AuthorizedSourceAdapter> _lastAdapter = {};
  final Map<String, Set<AuthorizedSourceAdapter>> _rejectedAdapters = {};

  Future<Uri?> resolve(Track track, AudioQuality quality) async {
    final key = '${track.id}:${quality.name}';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().isBefore(cached.expiresAt) &&
        !(_rejected[key]?.contains(cached.uri.toString()) ?? false)) {
      return cached.uri;
    }
    final existing = _pending[key];
    if (existing != null) return existing;
    final request = _resolveFresh(track, quality);
    _pending[key] = request;
    try {
      final uri = await request;
      if (uri != null) {
        _cache[key] = _ResolvedSource(
          uri,
          DateTime.now().add(const Duration(minutes: 8)),
        );
      }
      return uri;
    } finally {
      _pending.remove(key);
    }
  }

  Future<Uri?> _resolveFresh(Track track, AudioQuality quality) async {
    final key = '${track.id}:${quality.name}';
    for (final adapter in adapters) {
      if (_rejectedAdapters[key]?.contains(adapter) ?? false) continue;
      try {
        final uri = await adapter.resolve(track, quality);
        if (uri != null &&
            uri.hasScheme &&
            !(_rejected[key]?.contains(uri.toString()) ?? false)) {
          _lastAdapter[key] = adapter;
          return uri;
        }
      } catch (_) {
        // Continue through the authorized source chain.
      }
    }
    return null;
  }

  Future<void> prefetch(Track track, AudioQuality quality) async {
    await resolve(track, quality);
  }

  void invalidate(Track track, AudioQuality quality) {
    _cache.remove('${track.id}:${quality.name}');
  }

  void reject(Track track, AudioQuality quality, Uri uri) {
    final key = '${track.id}:${quality.name}';
    _cache.remove(key);
    (_rejected[key] ??= <String>{}).add(uri.toString());
    final adapter = _lastAdapter[key];
    if (adapter is RejectableSourceAdapter) {
      final rejectable = adapter as RejectableSourceAdapter;
      rejectable.reject(track, quality, uri);
    } else if (adapter != null) {
      (_rejectedAdapters[key] ??= <AuthorizedSourceAdapter>{}).add(adapter);
    }
  }
}

class _ResolvedSource {
  const _ResolvedSource(this.uri, this.expiresAt);
  final Uri uri;
  final DateTime expiresAt;
}
