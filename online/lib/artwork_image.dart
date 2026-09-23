import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class ArtworkImage extends StatelessWidget {
  const ArtworkImage({
    super.key,
    required this.url,
    required this.size,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String url;
  final int size;
  final Widget fallback;
  final BoxFit fit;

  // Coalesce requests and retain only tiny File handles for stable providers;
  // the completed image bytes themselves remain in the disk cache.
  static const _maximumCachedFiles = 48;
  static final LinkedHashMap<String, Future<File?>> _requests =
      LinkedHashMap<String, Future<File?>>();
  static final Future<Directory> _diskCache = _createDiskCache();

  static Future<Directory> _createDiskCache() async {
    final root = await getTemporaryDirectory();
    final directory = Directory('${root.path}/artwork-v1');
    await directory.create(recursive: true);
    return directory;
  }

  static Future<File> _cacheFile(String url) async {
    final directory = await _diskCache;
    final key = sha1.convert(utf8.encode(url)).toString();
    return File('${directory.path}/$key.img');
  }

  static Future<File?> _loadFile(String url) async {
    File? staleFile;
    try {
      final file = await _cacheFile(url);
      if (await file.exists()) {
        final modified = await file.lastModified();
        staleFile = file;
        if (DateTime.now().difference(modified) < const Duration(days: 1)) {
          if (await file.length() > 0) return file;
        }
      }
      final response = await http
          .get(Uri.parse(url), headers: neteaseArtworkHeaders)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        if (kDebugMode) {
          debugPrint('Artwork HTTP ${response.statusCode}: $url');
        }
        return staleFile;
      }
      await file.writeAsBytes(response.bodyBytes, flush: false);
      return file;
    } catch (error) {
      if (kDebugMode) debugPrint('Artwork request failed: $url ($error)');
      return staleFile;
    }
  }

  static Future<File?> _cachedFile(String url) {
    final existing = _requests[url];
    if (existing != null) return existing;
    final request = _loadFile(url);
    _requests[url] = request;
    request.then((file) {
      if (file == null && identical(_requests[url], request)) {
        _requests.remove(url);
      }
    });
    while (_requests.length > _maximumCachedFiles) {
      _requests.remove(_requests.keys.first);
    }
    return request;
  }

  static Future<File?> loadFile(String raw, {int size = 600}) {
    final resolved = neteaseArtworkUrl(raw, size: size);
    if (resolved.isEmpty) return Future.value();
    return _cachedFile(resolved);
  }

  static Future<Uint8List?> loadBytes(String raw, {int size = 600}) {
    return loadFile(raw, size: size).then((file) => file?.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    if (neteaseArtworkUrl(url, size: size).isEmpty) return fallback;
    return FutureBuilder<File?>(
      future: loadFile(url, size: size),
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) return fallback;
        return Image.file(
          file,
          fit: fit,
          gaplessPlayback: true,
          cacheWidth: size,
          cacheHeight: size,
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => fallback,
        );
      },
    );
  }
}

class ArtworkAvatar extends StatelessWidget {
  const ArtworkAvatar({
    super.key,
    required this.url,
    required this.diameter,
    required this.fallback,
  });

  final String url;
  final double diameter;
  final Widget fallback;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox.square(
      dimension: diameter,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: ArtworkImage(
          url: url,
          size: (diameter * 3).round(),
          fallback: Center(child: fallback),
        ),
      ),
    ),
  );
}
