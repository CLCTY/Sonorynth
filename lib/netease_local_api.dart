import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

enum NeteaseCryptoMode { weapi, eapi, api }

class NeteaseRequestException implements Exception {
  const NeteaseRequestException(this.message, {this.code, this.body});
  final String message;
  final int? code;
  final Map<String, dynamic>? body;

  @override
  String toString() => code == null ? message : '$message（$code）';
}

/// Device-local NetEase session. Sensitive cookies are kept in Android secure
/// storage rather than SharedPreferences.
class NeteaseSession {
  NeteaseSession({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _cookieKey = 'netease_session_cookie_v1';
  static const _deviceKey = 'netease_device_id_v1';
  final FlutterSecureStorage _storage;
  final Map<String, String> _cookies = {};
  String _deviceId = '';
  String _webNuid = '';
  String _webWnmcid = '';

  Map<String, String> get cookies => Map.unmodifiable(_cookies);
  bool get isAuthenticated => (_cookies['MUSIC_U'] ?? '').isNotEmpty;
  String get cookieString => _cookies.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');

  Future<void> initialize() async {
    final stored = await _storage.read(key: _cookieKey);
    if (stored != null) mergeCookieString(stored, persist: false);
    _deviceId = await _storage.read(key: _deviceKey) ?? '';
    if (_deviceId.isEmpty) {
      final random = Random.secure();
      _deviceId = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _storage.write(key: _deviceKey, value: _deviceId);
    }
    final webDigest = sha256.convert(utf8.encode(_deviceId)).bytes;
    _webNuid = webDigest
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final webName = webDigest
        .take(6)
        .map((value) => String.fromCharCode(97 + value % 26))
        .join();
    _webWnmcid = '$webName.${DateTime.now().millisecondsSinceEpoch}.01.0';
  }

  Map<String, String> requestCookies({bool webAuthentication = false}) {
    final cookies = <String, String>{
      ..._cookies,
      '__remember_me': 'true',
      'os': _cookies['os'] ?? 'android',
      'appver': _cookies['appver'] ?? '9.1.65',
      'osver': _cookies['osver'] ?? '14',
      'channel': _cookies['channel'] ?? 'xiaomi',
      'deviceId': _cookies['deviceId'] ?? _deviceId,
    };
    if (webAuthentication) {
      cookies.addAll({
        'os': 'pc',
        'appver': '3.1.17.204416',
        'osver': 'Microsoft-Windows-10-Professional-build-19045-64bit',
        'channel': 'netease',
        'ntes_kaola_ad': '1',
        '_ntes_nuid': cookies['_ntes_nuid'] ?? _webNuid,
        '_ntes_nnid':
            cookies['_ntes_nnid'] ??
            '${cookies['_ntes_nuid'] ?? _webNuid},${DateTime.now().millisecondsSinceEpoch}',
        'WNMCID': cookies['WNMCID'] ?? _webWnmcid,
        'WEVNSM': cookies['WEVNSM'] ?? '1.0.0',
      });
    }
    return cookies;
  }

  Future<void> mergeCookieString(String raw, {bool persist = true}) async {
    for (final part in raw.split(RegExp(r'[;\n]'))) {
      final index = part.indexOf('=');
      if (index <= 0) continue;
      final key = part.substring(0, index).trim();
      final value = part.substring(index + 1).trim();
      if (key.isNotEmpty && !_cookieAttributes.contains(key.toLowerCase())) {
        _cookies[key] = value;
      }
    }
    if (persist) await _persist();
  }

  Future<void> mergeSetCookieHeader(String? raw) async {
    if (raw == null || raw.isEmpty) return;
    final chunks = raw.split(RegExp(r',(?=[^;,\s]+=)'));
    for (final chunk in chunks) {
      final pair = chunk.split(';').first;
      await mergeCookieString(pair, persist: false);
    }
    await _persist();
  }

  Future<void> clear() async {
    _cookies.clear();
    await _storage.delete(key: _cookieKey);
  }

  Future<void> _persist() =>
      _storage.write(key: _cookieKey, value: cookieString);

  static const _cookieAttributes = {
    'path',
    'domain',
    'expires',
    'max-age',
    'secure',
    'httponly',
    'samesite',
  };
}

class NeteaseLocalApi {
  NeteaseLocalApi({http.Client? client, NeteaseSession? session})
    : _client = client ?? http.Client(),
      session = session ?? NeteaseSession();

  final http.Client _client;
  final NeteaseSession session;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await session.initialize();
    _initialized = true;
  }

  Future<Map<String, dynamic>> request(
    String apiPath,
    Map<String, dynamic> data, {
    NeteaseCryptoMode mode = NeteaseCryptoMode.eapi,
  }) async {
    await initialize();
    final webAuthentication =
        mode == NeteaseCryptoMode.weapi &&
        (apiPath.contains('/login/') || apiPath.contains('/sms/captcha/'));
    final cookies = session.requestCookies(
      webAuthentication: webAuthentication,
    );
    final csrf = cookies['__csrf'] ?? '';
    final payload = <String, dynamic>{...data};
    if (mode == NeteaseCryptoMode.weapi) {
      payload.putIfAbsent('csrf_token', () => csrf);
    } else if (mode == NeteaseCryptoMode.eapi) {
      final now = DateTime.now().millisecondsSinceEpoch;
      payload['header'] = <String, dynamic>{
        'osver': cookies['osver'],
        'deviceId': cookies['deviceId'],
        'os': cookies['os'],
        'appver': cookies['appver'],
        'versioncode': '9001065',
        'mobilename': '',
        'buildver': '${now ~/ 1000}',
        'resolution': '1080x2400',
        '__csrf': csrf,
        'channel': cookies['channel'],
        'requestId':
            '$now${Random.secure().nextInt(1000).toString().padLeft(3, '0')}',
        if ((cookies['MUSIC_U'] ?? '').isNotEmpty)
          'MUSIC_U': cookies['MUSIC_U'],
        if ((cookies['MUSIC_A'] ?? '').isNotEmpty)
          'MUSIC_A': cookies['MUSIC_A'],
      };
    }
    final cookieHeader = cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
    final uri = _requestUri(apiPath, mode);
    final encrypted = switch (mode) {
      NeteaseCryptoMode.weapi => NeteaseCrypto.weapi(payload),
      NeteaseCryptoMode.eapi => NeteaseCrypto.eapi(apiPath, payload),
      NeteaseCryptoMode.api => payload.map(
        (key, value) =>
            MapEntry(key, value is String ? value : jsonEncode(value)),
      ),
    };
    final response = await _client
        .post(
          uri,
          headers: {
            'Cookie': cookieHeader,
            'Referer': 'https://music.163.com/',
            'User-Agent': mode == NeteaseCryptoMode.weapi
                ? webAuthentication
                      ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0'
                      : 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36'
                : 'NeteaseMusic/9.1.65.240927161425(9001065);Dalvik/2.1.0 (Linux; U; Android 14)',
          },
          body: encrypted,
        )
        .timeout(const Duration(seconds: 18));
    await session.mergeSetCookieHeader(response.headers['set-cookie']);
    Map<String, dynamic> body;
    try {
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw NeteaseRequestException('网易云返回了无法解析的数据', code: response.statusCode);
    }
    final code = _intValue(body['code']) ?? response.statusCode;
    const accepted = {200, 201, 302, 400, 800, 801, 802, 803};
    if (response.statusCode < 200 ||
        response.statusCode >= 400 ||
        (!accepted.contains(code) && code >= 400)) {
      throw NeteaseRequestException(
        '${body['message'] ?? body['msg'] ?? '网易云请求失败'}',
        code: code,
        body: body,
      );
    }
    return body;
  }

  Uri _requestUri(String path, NeteaseCryptoMode mode) {
    final suffix = path.startsWith('/api/')
        ? path.substring(5)
        : path.replaceFirst('/', '');
    return switch (mode) {
      NeteaseCryptoMode.weapi => Uri.parse(
        'https://music.163.com/weapi/$suffix',
      ),
      NeteaseCryptoMode.eapi => Uri.parse(
        'https://interface.music.163.com/eapi/$suffix',
      ),
      NeteaseCryptoMode.api => Uri.parse(
        'https://interface.music.163.com$path',
      ),
    };
  }

  static int? _intValue(dynamic value) => switch (value) {
    int v => v,
    String v => int.tryParse(v),
    _ => null,
  };
}

class NeteaseCrypto {
  static const _iv = '0102030405060708';
  static const _presetKey = '0CoJUm6Qyw8W8jud';
  static const _eapiKey = 'e82ckenh8dichen8';
  static const _base62 =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static final _rsaModulus = BigInt.parse(
    '00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b7'
    '25152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e'
    '0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce'
    '10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462'
    'db0a22b8e7',
    radix: 16,
  );
  static final _rsaExponent = BigInt.parse('010001', radix: 16);

  static Map<String, String> weapi(Map<String, dynamic> data) {
    final random = Random.secure();
    final secret = List.generate(
      16,
      (_) => _base62[random.nextInt(_base62.length)],
    ).join();
    final first = _aesCbcBase64(jsonEncode(data), _presetKey);
    final params = _aesCbcBase64(first, secret);
    return {'params': params, 'encSecKey': _rsaEncrypt(secret)};
  }

  static Map<String, String> eapi(String path, Map<String, dynamic> data) {
    final text = jsonEncode(data);
    final digest = md5.convert(
      utf8.encode('nobody${path}use${text}md5forencrypt'),
    );
    final payload = '$path-36cd479b6b5-$text-36cd479b6b5-$digest';
    final encrypted = _aesEcb(utf8.encode(payload), utf8.encode(_eapiKey));
    return {'params': _hex(encrypted).toUpperCase()};
  }

  static String _aesCbcBase64(String value, String key) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      true,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(
          KeyParameter(Uint8List.fromList(utf8.encode(key))),
          Uint8List.fromList(utf8.encode(_iv)),
        ),
        null,
      ),
    );
    return base64Encode(cipher.process(Uint8List.fromList(utf8.encode(value))));
  }

  static Uint8List _aesEcb(List<int> value, List<int> key) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      ECBBlockCipher(AESEngine()),
    );
    cipher.init(
      true,
      PaddedBlockCipherParameters<KeyParameter, Null>(
        KeyParameter(Uint8List.fromList(key)),
        null,
      ),
    );
    return cipher.process(Uint8List.fromList(value));
  }

  static String _rsaEncrypt(String secret) {
    final reversed = utf8.encode(secret).reversed.toList();
    final value = BigInt.parse(_hex(reversed), radix: 16);
    return value
        .modPow(_rsaExponent, _rsaModulus)
        .toRadixString(16)
        .padLeft(256, '0');
  }

  static String _hex(Iterable<int> bytes) =>
      bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
}
