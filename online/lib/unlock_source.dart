// “破解音源”解锁适配器。
//
// 将桌面端 Splayer 插件 music-unlock.js 的解锁逻辑移植为 Dart 适配器，
// 作为 AuthorizedSourceAdapter 责任链的一环。排在 NeteaseOfficialAdapter
// 之后：当用户已登录网易云且拥有 VIP 时，官方适配器会直接返回完整播放地址；
// 当账号无 VIP、或歌曲受限（freeTrial）官方返回 null 时，回退到本解锁链。
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'netease_api.dart';

/* ===========================================================
 * kwDES —— 酷我 DES 加密（自 music-unlock.js 的 Long/DES 移植）
 * 使用 BigInt 表达 64 位整数，与原 JS 的 BigInt 语义一致。
 * =========================================================== */

const _kwSecretKey = 'ylzsxkwm';

final List<BigInt> _arrayE = _longArray([
  31,
  0,
  1,
  2,
  3,
  4,
  -1,
  -1,
  3,
  4,
  5,
  6,
  7,
  8,
  -1,
  -1,
  7,
  8,
  9,
  10,
  11,
  12,
  -1,
  -1,
  11,
  12,
  13,
  14,
  15,
  16,
  -1,
  -1,
  15,
  16,
  17,
  18,
  19,
  20,
  -1,
  -1,
  19,
  20,
  21,
  22,
  23,
  24,
  -1,
  -1,
  23,
  24,
  25,
  26,
  27,
  28,
  -1,
  -1,
  27,
  28,
  29,
  30,
  31,
  30,
  -1,
  -1,
]);

final List<BigInt> _arrayIP = _longArray([
  57,
  49,
  41,
  33,
  25,
  17,
  9,
  1,
  59,
  51,
  43,
  35,
  27,
  19,
  11,
  3,
  61,
  53,
  45,
  37,
  29,
  21,
  13,
  5,
  63,
  55,
  47,
  39,
  31,
  23,
  15,
  7,
  56,
  48,
  40,
  32,
  24,
  16,
  8,
  0,
  58,
  50,
  42,
  34,
  26,
  18,
  10,
  2,
  60,
  52,
  44,
  36,
  28,
  20,
  12,
  4,
  62,
  54,
  46,
  38,
  30,
  22,
  14,
  6,
]);

final List<BigInt> _arrayIPInv = _longArray([
  39,
  7,
  47,
  15,
  55,
  23,
  63,
  31,
  38,
  6,
  46,
  14,
  54,
  22,
  62,
  30,
  37,
  5,
  45,
  13,
  53,
  21,
  61,
  29,
  36,
  4,
  44,
  12,
  52,
  20,
  60,
  28,
  35,
  3,
  43,
  11,
  51,
  19,
  59,
  27,
  34,
  2,
  42,
  10,
  50,
  18,
  58,
  26,
  33,
  1,
  41,
  9,
  49,
  17,
  57,
  25,
  32,
  0,
  40,
  8,
  48,
  16,
  56,
  24,
]);

const _arrayLs = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

final List<BigInt> _arrayLsMask = [
  BigInt.zero,
  BigInt.from(0x100001),
  BigInt.from(0x300003),
];

final List<BigInt> _arrayMask = List<BigInt>.generate(
  64,
  (n) => BigInt.one << n,
)..[63] = (BigInt.one << 63) * BigInt.from(-1);

final List<BigInt> _arrayP = _longArray([
  15,
  6,
  19,
  20,
  28,
  11,
  27,
  16,
  0,
  14,
  22,
  25,
  4,
  17,
  30,
  9,
  1,
  7,
  23,
  13,
  31,
  26,
  2,
  8,
  18,
  12,
  29,
  5,
  21,
  10,
  3,
  24,
]);

final List<BigInt> _arrayPC1 = _longArray([
  56,
  48,
  40,
  32,
  24,
  16,
  8,
  0,
  57,
  49,
  41,
  33,
  25,
  17,
  9,
  1,
  58,
  50,
  42,
  34,
  26,
  18,
  10,
  2,
  59,
  51,
  43,
  35,
  62,
  54,
  46,
  38,
  30,
  22,
  14,
  6,
  61,
  53,
  45,
  37,
  29,
  21,
  13,
  5,
  60,
  52,
  44,
  36,
  28,
  20,
  12,
  4,
  27,
  19,
  11,
  3,
]);

final List<BigInt> _arrayPC2 = _longArray([
  13,
  16,
  10,
  23,
  0,
  4,
  -1,
  -1,
  2,
  27,
  14,
  5,
  20,
  9,
  -1,
  -1,
  22,
  18,
  11,
  3,
  25,
  7,
  -1,
  -1,
  15,
  6,
  26,
  19,
  12,
  1,
  -1,
  -1,
  40,
  51,
  30,
  36,
  46,
  54,
  -1,
  -1,
  29,
  39,
  50,
  44,
  32,
  47,
  -1,
  -1,
  43,
  48,
  38,
  55,
  33,
  52,
  -1,
  -1,
  45,
  41,
  49,
  35,
  28,
  31,
  -1,
  -1,
]);

const _matrixNSBox = [
  [
    14,
    4,
    3,
    15,
    2,
    13,
    5,
    3,
    13,
    14,
    6,
    9,
    11,
    2,
    0,
    5,
    4,
    1,
    10,
    12,
    15,
    6,
    9,
    10,
    1,
    8,
    12,
    7,
    8,
    11,
    7,
    0,
    0,
    15,
    10,
    5,
    14,
    4,
    9,
    10,
    7,
    8,
    12,
    3,
    13,
    1,
    3,
    6,
    15,
    12,
    6,
    11,
    2,
    9,
    5,
    0,
    4,
    2,
    11,
    14,
    1,
    7,
    8,
    13,
  ],
  [
    15,
    0,
    9,
    5,
    6,
    10,
    12,
    9,
    8,
    7,
    2,
    12,
    3,
    13,
    5,
    2,
    1,
    14,
    7,
    8,
    11,
    4,
    0,
    3,
    14,
    11,
    13,
    6,
    4,
    1,
    10,
    15,
    3,
    13,
    12,
    11,
    15,
    3,
    6,
    0,
    4,
    10,
    1,
    7,
    8,
    4,
    11,
    14,
    13,
    8,
    0,
    6,
    2,
    15,
    9,
    5,
    7,
    1,
    10,
    12,
    14,
    2,
    5,
    9,
  ],
  [
    10,
    13,
    1,
    11,
    6,
    8,
    11,
    5,
    9,
    4,
    12,
    2,
    15,
    3,
    2,
    14,
    0,
    6,
    13,
    1,
    3,
    15,
    4,
    10,
    14,
    9,
    7,
    12,
    5,
    0,
    8,
    7,
    13,
    1,
    2,
    4,
    3,
    6,
    12,
    11,
    0,
    13,
    5,
    14,
    6,
    8,
    15,
    2,
    7,
    10,
    8,
    15,
    4,
    9,
    11,
    5,
    9,
    0,
    14,
    3,
    10,
    7,
    1,
    12,
  ],
  [
    7,
    10,
    1,
    15,
    0,
    12,
    11,
    5,
    14,
    9,
    8,
    3,
    9,
    7,
    4,
    8,
    13,
    6,
    2,
    1,
    6,
    11,
    12,
    2,
    3,
    0,
    5,
    14,
    10,
    13,
    15,
    4,
    13,
    3,
    4,
    9,
    6,
    10,
    1,
    12,
    11,
    0,
    2,
    5,
    0,
    13,
    14,
    2,
    8,
    15,
    7,
    4,
    15,
    1,
    10,
    7,
    5,
    6,
    12,
    11,
    3,
    8,
    9,
    14,
  ],
  [
    2,
    4,
    8,
    15,
    7,
    10,
    13,
    6,
    4,
    1,
    3,
    12,
    11,
    7,
    14,
    0,
    12,
    2,
    5,
    9,
    10,
    13,
    0,
    3,
    1,
    11,
    15,
    5,
    6,
    8,
    9,
    14,
    14,
    11,
    5,
    6,
    4,
    1,
    3,
    10,
    2,
    12,
    15,
    0,
    13,
    2,
    8,
    5,
    11,
    8,
    0,
    15,
    7,
    14,
    9,
    4,
    12,
    7,
    10,
    9,
    1,
    13,
    6,
    3,
  ],
  [
    12,
    9,
    0,
    7,
    9,
    2,
    14,
    1,
    10,
    15,
    3,
    4,
    6,
    12,
    5,
    11,
    1,
    14,
    13,
    0,
    2,
    8,
    7,
    13,
    15,
    5,
    4,
    10,
    8,
    3,
    11,
    6,
    10,
    4,
    6,
    11,
    7,
    9,
    0,
    6,
    4,
    2,
    13,
    1,
    9,
    15,
    3,
    8,
    15,
    3,
    1,
    14,
    12,
    5,
    11,
    0,
    2,
    12,
    14,
    7,
    5,
    10,
    8,
    13,
  ],
  [
    4,
    1,
    3,
    10,
    15,
    12,
    5,
    0,
    2,
    11,
    9,
    6,
    8,
    7,
    6,
    9,
    11,
    4,
    12,
    15,
    0,
    3,
    10,
    5,
    14,
    13,
    7,
    8,
    13,
    14,
    1,
    2,
    13,
    6,
    14,
    9,
    4,
    1,
    2,
    14,
    11,
    13,
    5,
    0,
    1,
    10,
    8,
    3,
    0,
    11,
    3,
    5,
    9,
    4,
    15,
    2,
    7,
    8,
    12,
    15,
    10,
    7,
    6,
    12,
  ],
  [
    13,
    7,
    10,
    0,
    6,
    9,
    5,
    15,
    8,
    4,
    3,
    10,
    11,
    14,
    12,
    5,
    2,
    11,
    9,
    6,
    15,
    12,
    0,
    3,
    4,
    1,
    14,
    13,
    1,
    2,
    7,
    8,
    1,
    2,
    12,
    15,
    10,
    4,
    0,
    3,
    13,
    14,
    6,
    9,
    7,
    8,
    9,
    6,
    15,
    1,
    5,
    12,
    3,
    10,
    14,
    5,
    8,
    7,
    11,
    0,
    4,
    13,
    2,
    11,
  ],
];

List<BigInt> _longArray(List<int> values) =>
    values.map((n) => n == -1 ? BigInt.from(-1) : BigInt.from(n)).toList();

BigInt _bitTransform(List<BigInt> arrInt, BigInt l) {
  var l2 = BigInt.zero;
  for (var i = 0; i < arrInt.length; i++) {
    final idx = arrInt[i];
    if (idx.isNegative) continue;
    if ((l & _arrayMask[idx.toInt()]) == BigInt.zero) continue;
    l2 |= _arrayMask[i];
  }
  return l2;
}

BigInt _des64(List<BigInt> longs, BigInt l) {
  final pR = List<BigInt>.filled(8, BigInt.zero);
  final pSource = [BigInt.zero, BigInt.zero];
  var out = _bitTransform(_arrayIP, l);
  pSource[0] = out & BigInt.from(0xffffffff);
  pSource[1] = (out & BigInt.from(-4294967296)) >> 32;

  for (var i = 0; i < 16; i++) {
    var sOut = BigInt.zero;
    var r = pSource[1];
    r = _bitTransform(_arrayE, r);
    r ^= longs[i];
    for (var j = 0; j < 8; j++) {
      pR[j] = (r >> (j * 8)) & BigInt.from(255);
    }
    for (var sbi = 7; sbi >= 0; sbi--) {
      sOut = (sOut << 4) | BigInt.from(_matrixNSBox[sbi][pR[sbi].toInt()]);
    }
    r = _bitTransform(_arrayP, sOut);
    final left = pSource[0];
    pSource[0] = pSource[1];
    pSource[1] = left ^ r;
  }
  // JS 末尾 `pSource.reverse()` 后取 pSource[1]<<32 | pSource[0]，
  // 等价于（不反转）原 pSource[0]<<32 | 原 pSource[1]。
  final s0 = pSource[0];
  final s1 = pSource[1];
  out =
      ((s0 << 32) & BigInt.from(-4294967296)) | (s1 & BigInt.from(0xffffffff));
  return _bitTransform(_arrayIPInv, out);
}

void _subKeys(BigInt l, List<BigInt> longs, int mode) {
  var l2 = _bitTransform(_arrayPC1, l);
  for (var i = 0; i < 16; i++) {
    final mask = _arrayLsMask[_arrayLs[i]];
    l2 = ((l2 & mask) << (28 - _arrayLs[i])) | ((l2 & ~mask) >> _arrayLs[i]);
    longs[i] = _bitTransform(_arrayPC2, l2);
  }
  if (mode == 1) {
    for (var j = 0; j < 8; j++) {
      final tmp = longs[j];
      longs[j] = longs[15 - j];
      longs[15 - j] = tmp;
    }
  }
}

Uint8List _crypt(List<int> msg, List<int> key, int mode) {
  var l = BigInt.zero;
  for (var i = 0; i < 8; i++) {
    l = (BigInt.from(key[i]) << (i * 8)) | l;
  }

  final j = msg.length ~/ 8;
  final arrLong1 = List<BigInt>.filled(16, BigInt.zero);
  _subKeys(l, arrLong1, mode);

  final arrLong2 = List<BigInt>.filled(j, BigInt.zero);
  for (var m = 0; m < j; m++) {
    for (var n = 0; n < 8; n++) {
      arrLong2[m] = (BigInt.from(msg[n + m * 8]) << (n * 8)) | arrLong2[m];
    }
  }

  final arrLong3 = List<BigInt>.filled(j + 1, BigInt.zero);
  for (var i1 = 0; i1 < j; i1++) {
    arrLong3[i1] = _des64(arrLong1, arrLong2[i1]);
  }

  final arrByte1 = msg.sublist(j * 8);
  var l2 = BigInt.zero;
  for (var i1 = 0; i1 < msg.length % 8; i1++) {
    l2 = (BigInt.from(arrByte1[i1]) << (i1 * 8)) | l2;
  }

  if (arrByte1.isNotEmpty || mode == 0) {
    arrLong3[j] = _des64(arrLong1, l2);
  }

  final out = Uint8List(8 * arrLong3.length);
  var i4 = 0;
  for (final l3 in arrLong3) {
    for (var i6 = 0; i6 < 8; i6++) {
      out[i4] = ((l3 >> (i6 * 8)) & BigInt.from(255)).toInt();
      i4 += 1;
    }
  }
  return out;
}

String _kwEncryptQuery(String query) {
  final bytes = _crypt(utf8.encode(query), utf8.encode(_kwSecretKey), 0);
  return base64.encode(bytes);
}

/* ===========================================================
 * 歌曲匹配 / 解锁服务（移植自 music-unlock.js）
 * =========================================================== */

class _Match {
  const _Match({
    required this.keyword,
    required this.songName,
    required this.artist,
  });
  final String keyword;
  final String songName;
  final String artist;
}

String _normalizeName(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[（(][^）)]*[）)]'), '').trim();
}

String _normalizeArtist(String artist) {
  return artist
      .toLowerCase()
      .replaceAll(RegExp(r'[&/、，,;；]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isSongMatch(String resultName, String resultArtist, _Match match) {
  final normalizedResult = _normalizeName(resultName);
  final normalizedOriginal = _normalizeName(match.songName);
  if (normalizedResult.isEmpty) return false;
  if (normalizedOriginal.isNotEmpty) {
    if (!normalizedResult.contains(normalizedOriginal) &&
        !normalizedOriginal.contains(normalizedResult)) {
      return false;
    }
  }
  if (resultArtist.isNotEmpty && match.artist.isNotEmpty) {
    final a = _normalizeArtist(resultArtist);
    final b = _normalizeArtist(match.artist);
    if (a.isNotEmpty && b.isNotEmpty) {
      if (!a.contains(b) && !b.contains(a)) return false;
    }
  }
  return true;
}

final String _deviceId = _generateDeviceId();
String _generateDeviceId() {
  final rng = Random();
  final n = rng.nextInt(100000000001);
  return n.toString();
}

class _KuwoSong {
  const _KuwoSong(this.id, this.name, this.artists);
  final String id;
  final String name;
  final List<String> artists;
}

_KuwoSong? _formatKuwoSong(Map<String, dynamic> song) {
  final musicrid = '${song['MUSICRID'] ?? ''}';
  final id = musicrid.split('_').isEmpty ? '' : musicrid.split('_').last;
  return _KuwoSong(
    id,
    '${song['SONGNAME'] ?? ''}',
    '${song['ARTIST'] ?? ''}'.split('&'),
  );
}

Future<String?> _searchKuwo(_Match match) async {
  final keyword = Uri.encodeQueryComponent(
    match.keyword.replaceAll(' - ', ' '),
  );
  final url =
      'http://search.kuwo.cn/r.s?&correct=1&vipver=1&stype=comprehensive&encoding=utf8'
      '&rformat=json&mobi=1&show_copyright_off=1&searchapi=6&all=$keyword';
  final resp = await http
      .get(Uri.parse(url))
      .timeout(const Duration(seconds: 8));
  if (resp.statusCode != 200 || resp.body.isEmpty) return null;
  final Map<String, dynamic> data;
  try {
    data = jsonDecode(resp.body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  final content = data['content'];
  if (content is! List || content.length < 2) return null;
  final musicpage = (content[1] as Map<String, dynamic>?)?['musicpage'];
  if (musicpage is! Map<String, dynamic>) return null;
  final abslist = musicpage['abslist'];
  if (abslist is! List || abslist.isEmpty) return null;
  for (final raw in abslist) {
    if (raw is! Map<String, dynamic>) continue;
    final item = _formatKuwoSong(raw);
    if (item == null || item.id.isEmpty) continue;
    final artistStr = item.artists.join('&');
    if (_isSongMatch(item.name, artistStr, match)) return item.id;
  }
  return null;
}

/// Searches the additional catalog exposed by the unlock source chain.
///
/// Result IDs are namespaced so they cannot accidentally be sent to NetEase
/// as song IDs. Playback still goes through [UnlockSourceAdapter], which
/// validates the title and artist before resolving a stream.
Future<List<Track>> searchUnlockSources(
  String keyword, {
  int limit = 20,
}) async {
  final query = keyword.trim();
  if (query.isEmpty) return const [];
  try {
    final encoded = Uri.encodeQueryComponent(query.replaceAll(' - ', ' '));
    final url =
        'http://search.kuwo.cn/r.s?&correct=1&vipver=1&stype=comprehensive&encoding=utf8'
        '&rformat=json&mobi=1&show_copyright_off=1&searchapi=6&pn=0&rn=$limit&all=$encoded';
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200 || response.body.isEmpty) return const [];
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = data['content'];
    if (content is! List || content.length < 2) return const [];
    final musicPage = (content[1] as Map<String, dynamic>?)?['musicpage'];
    final rawSongs = musicPage is Map<String, dynamic>
        ? musicPage['abslist']
        : null;
    if (rawSongs is! List) return const [];

    Duration durationOf(dynamic value) {
      if (value is num) return Duration(seconds: value.round());
      final text = '$value'.trim();
      final parts = text.split(':');
      if (parts.length == 2) {
        return Duration(
          minutes: int.tryParse(parts[0]) ?? 0,
          seconds: int.tryParse(parts[1]) ?? 0,
        );
      }
      return Duration(seconds: int.tryParse(text) ?? 0);
    }

    String artworkOf(Map<String, dynamic> song) {
      var value =
          '${song['web_albumpic_short'] ?? song['web_albumpic'] ?? song['hts_MVPIC'] ?? song['MVPIC'] ?? song['ALBUM_PIC'] ?? song['web_artistpic_short'] ?? ''}'
              .trim();
      if (value.startsWith('//')) value = 'https:$value';
      if (value.startsWith('http://')) {
        value = 'https://${value.substring('http://'.length)}';
      }
      if (value.isNotEmpty && !value.startsWith('https://')) {
        value = value.replaceFirst(RegExp(r'^/+'), '');
        if (value.startsWith('120/')) {
          value = '300/${value.substring('120/'.length)}';
        }
        value = 'https://img1.kuwo.cn/star/albumcover/$value';
      }
      return value;
    }

    final tracks = <Track>[];
    final seen = <String>{};
    for (final raw in rawSongs) {
      if (raw is! Map<String, dynamic>) continue;
      final song = _formatKuwoSong(raw);
      if (song == null || song.id.isEmpty || !seen.add(song.id)) continue;
      tracks.add(
        Track(
          id: 'kuwo:${song.id}',
          title: song.name.trim().isEmpty ? '未知歌曲' : song.name.trim(),
          artist: song.artists
              .where((value) => value.trim().isNotEmpty)
              .join(' / '),
          album: '${raw['ALBUM'] ?? ''}'.trim(),
          coverUrl: artworkOf(raw),
          duration: durationOf(raw['DURATION'] ?? raw['DURATIONMS']),
        ),
      );
      if (tracks.length >= limit) break;
    }
    return tracks;
  } catch (_) {
    return const [];
  }
}

Future<void> _sendAdFreeRequest() async {
  try {
    const adurl =
        'http://bd-api.kuwo.cn/api/service/advert/watch?uid=-1&token=&timestamp=1724306124436&sign=15a676d66285117ad714e8c8371691da';
    final headers = {
      'user-agent': 'Dart/2.19 (dart:io)',
      'plat': 'ar',
      'channel': 'aliopen',
      'devid': _deviceId,
      'ver': '3.9.0',
      'host': 'bd-api.kuwo.cn',
      'qimei36': '1e9970cbcdc20a031dee9f37100017e1840e',
      'content-type': 'application/json; charset=utf-8',
    };
    await http
        .post(
          Uri.parse(adurl),
          headers: headers,
          body: jsonEncode({
            'type': 5,
            'subType': 5,
            'musicId': 0,
            'adToken': '',
          }),
        )
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    // 广告免扣请求仅为前置步骤，失败不影响后续解锁。
  }
}

String _generateSign(String str) {
  final uri = Uri.parse(str);
  final ts = DateTime.now().millisecondsSinceEpoch;
  final stamped = '$str&timestamp=$ts';
  final filtered = stamped
      .substring(stamped.indexOf('?') + 1)
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .split('')
      .join();
  final dataToEncrypt = 'kuwotest$filtered${uri.path}';
  final digest = md5.convert(utf8.encode(dataToEncrypt)).toString();
  return '$stamped&sign=$digest';
}

Future<Uri?> _unlockByNetease(String id) async {
  try {
    if (id.isEmpty) return null;
    final baseUrl = 'https://music-api.gdstudio.xyz/api.php';
    final resp = await http
        .get(Uri.parse('$baseUrl?types=url&id=${Uri.encodeQueryComponent(id)}'))
        .timeout(const Duration(seconds: 8));
    if (resp.statusCode != 200 || resp.body.isEmpty) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final url = '${data['url'] ?? ''}';
    if (url.isEmpty) return null;
    return Uri.tryParse(url);
  } catch (_) {
    return null;
  }
}

Future<Uri?> _unlockByBodian(_Match match) async {
  try {
    if (match.keyword.isEmpty) return null;
    final songId = await _searchKuwo(match);
    if (songId == null) return null;
    final headers = {
      'user-agent': 'Dart/2.19 (dart:io)',
      'plat': 'ar',
      'channel': 'aliopen',
      'devid': _deviceId,
      'ver': '3.9.0',
      'host': 'bd-api.kuwo.cn',
      'X-Forwarded-For': '1.0.1.114',
    };
    await _sendAdFreeRequest();
    for (final br in ['320kmp3', '192kmp3', '128kmp3']) {
      var audioUrl =
          'http://bd-api.kuwo.cn/api/play/music/v2/audioUrl?br=$br&musicId=$songId';
      audioUrl = _generateSign(audioUrl);
      final result = await http
          .get(Uri.parse(audioUrl), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (result.statusCode != 200 || result.body.isEmpty) continue;
      final body = jsonDecode(result.body) as Map<String, dynamic>;
      final url =
          '${(body['data'] as Map<String, dynamic>?)?['audioUrl'] ?? ''}';
      if (url.isNotEmpty) return Uri.tryParse(url);
    }
    return null;
  } catch (_) {
    return null;
  }
}

Future<({Uri uri, String stage})?> _unlockByKuwo(
  _Match match,
  Set<String> rejectedStages,
) async {
  try {
    if (match.keyword.isEmpty) return null;
    final songId = await _searchKuwo(match);
    if (songId == null) return null;

    // Try 1: antiserver（无需加密，稳定完整 MP3）
    if (!rejectedStages.contains('kuwo-anti')) {
      final antiUrl =
          'http://antiserver.kuwo.cn/anti.s?type=convert_url&format=mp3&response=url&rid=MUSIC_$songId';
      final result = await http
          .get(Uri.parse(antiUrl))
          .timeout(const Duration(seconds: 8));
      final body = result.body.trim();
      final uri = body.startsWith('http') ? Uri.tryParse(body) : null;
      if (uri != null) return (uri: uri, stage: 'kuwo-anti');
    }

    // Try 2: www.kuwo.cn/url（Web API，可指定码率）
    if (!rejectedStages.contains('kuwo-web')) {
      final kwUrl =
          'http://www.kuwo.cn/url?format=mp3&response=url&type=convert_url3&br=320kmp3&rid=$songId';
      final result = await http
          .get(Uri.parse(kwUrl), headers: {'Referer': 'http://www.kuwo.cn/'})
          .timeout(const Duration(seconds: 8));
      final body = result.body.trim();
      final uri = body.startsWith('http') ? Uri.tryParse(body) : null;
      if (uri != null) return (uri: uri, stage: 'kuwo-web');
    }

    // Try 3: mobi.s + kwDES（兜底，可能仅返回试听预览）
    if (!rejectedStages.contains('kuwo-mobi')) {
      const packageName = 'kwplayer_ar_5.1.0.0_B_jiakong_vh.apk';
      final query =
          'corp=kuwo&source=$packageName&p2p=1&type=convert_url2&sig=0&format=mp3&rid=$songId';
      final url =
          'http://mobi.kuwo.cn/mobi.s?f=kuwo&q=${_kwEncryptQuery(query)}';
      final result = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'okhttp/3.10.0'})
          .timeout(const Duration(seconds: 8));
      final m = RegExp(r'http[^\s$"<>]+').firstMatch(result.body);
      final uri = m == null ? null : Uri.tryParse(m.group(0)!);
      if (uri != null) return (uri: uri, stage: 'kuwo-mobi');
    }

    return null;
  } catch (_) {
    return null;
  }
}

/// 解锁音源适配器：依次尝试网易云镜像、酷我 bodian、酷多源，全部失败返回 null。
class UnlockSourceAdapter
    implements AuthorizedSourceAdapter, RejectableSourceAdapter {
  final Map<String, Set<String>> _rejectedStages = {};
  final Map<String, String> _lastStage = {};

  String _key(Track track, AudioQuality quality) =>
      '${track.id}:${quality.name}';

  Uri? _accept(String key, String stage, Uri? uri, Set<String> rejected) {
    if (uri == null || !uri.hasScheme || rejected.contains(stage)) return null;
    _lastStage[key] = stage;
    return uri;
  }

  @override
  Future<Uri?> resolve(Track track, AudioQuality quality) async {
    final key = _key(track, quality);
    final rejected = _rejectedStages[key] ?? const <String>{};
    final songName = track.title;
    final singer = track.artist;
    final keyword = '$songName-$singer';
    final match = _Match(keyword: keyword, songName: songName, artist: singer);

    // 1. 网易云镜像（按 netease 歌曲 id 解锁，仅对网易云曲目有效）
    if (track.id.isNotEmpty &&
        !track.id.startsWith('kuwo:') &&
        !rejected.contains('netease-mirror')) {
      final uri = await _unlockByNetease(track.id);
      final accepted = _accept(key, 'netease-mirror', uri, rejected);
      if (accepted != null) return accepted;
    }

    // 2. 酷我 bodian（bd-api，含签名）
    if (keyword.isNotEmpty) {
      if (!rejected.contains('kuwo-bodian')) {
        final uri = await _unlockByBodian(match);
        final accepted = _accept(key, 'kuwo-bodian', uri, rejected);
        if (accepted != null) return accepted;
      }

      // 3. 酷我 anti/web/mobi 多源兜底
      final result = await _unlockByKuwo(match, rejected);
      if (result != null) {
        _lastStage[key] = result.stage;
        return result.uri;
      }
    }

    return null;
  }

  @override
  void reject(Track track, AudioQuality quality, Uri uri) {
    final key = _key(track, quality);
    final stage = _lastStage[key];
    if (stage != null) (_rejectedStages[key] ??= <String>{}).add(stage);
  }
}
