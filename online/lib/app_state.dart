import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'artwork_image.dart';
import 'audio_handler.dart';
import 'lyrics_parser.dart';
import 'models.dart';
import 'netease_api.dart';
import 'unlock_source.dart';

enum CoverColorStyle {
  analogous('同频柔光'),
  vibrant('鲜彩跃动'),
  bright('晨光明调'),
  balanced('自然和鸣'),
  diverse('万花交响');

  const CoverColorStyle(this.label);
  final String label;
}

enum PlaybackRepeatMode { all, one }

enum LyricScrollPreset {
  gentle('柔和', 1.05, 155, 25),
  balanced('自然', 1, 210, 25),
  lively('灵动', .9, 300, 21),
  efficient('省电', 1, 265, 36),
  custom('自定义', 1, 210, 25);

  const LyricScrollPreset(this.label, this.mass, this.stiffness, this.damping);

  final String label;
  final double mass;
  final double stiffness;
  final double damping;
}

enum MusicSearchSource {
  all('全部'),
  netease('网易云'),
  kuwo('酷我');

  const MusicSearchSource(this.label);
  final String label;
}

class PlaybackTimeline {
  const PlaybackTimeline({required this.position, required this.duration});
  final Duration position;
  final Duration duration;
}

class MelodyState extends ChangeNotifier {
  static const _lyricCacheVersion = 4;
  MelodyState(this.audioHandler) : player = audioHandler.player;

  @visibleForTesting
  static bool debugIsPredominantlyMonochrome(List<int> chromaSamples) =>
      _isPredominantlyMonochrome(chromaSamples);

  static bool _isPredominantlyMonochrome(List<int> chromaSamples) {
    if (chromaSamples.isEmpty) return true;
    final chromaticPixels = chromaSamples.where((chroma) => chroma > 12).length;
    // Sparse coloured lettering on black artwork is still real album colour.
    // Only discard a tiny fringe population, not up to a quarter of the cover.
    return chromaticPixels / chromaSamples.length <= .02;
  }

  final MelodyAudioHandler audioHandler;
  final AudioPlayer player;
  SharedPreferences? _prefs;
  late final NeteaseApi api;
  late SourceResolver sources;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerSub;
  StreamSubscription<Duration?>? _durationSub;
  Timer? _saveTimer;
  Timer? _messageTimer;
  Future<void>? _persistenceInFlight;
  bool _fullPersistenceRequested = false;
  bool _checkpointPersistenceRequested = false;
  Duration _uncommittedListeningTime = Duration.zero;
  int _playRequestSerial = 0;
  bool _advancingAfterCompletion = false;
  bool _switchingShortSource = false;
  Uri? _activeSourceUri;
  Future<void> _sourceMutation = Future<void>.value();

  int tab = 0;
  static const emptyTrack = Track(
    id: '',
    title: '尚未播放',
    artist: '选择一首歌曲',
    album: '',
    coverUrl: '',
    duration: Duration.zero,
  );

  Track current = emptyTrack;
  List<Track> queue = [];
  List<Track> recent = [];
  List<Track> recommendations = [];
  List<Track> cloudHistory = [];
  List<Track> searchResults = [];
  MusicSearchSource searchSource = MusicSearchSource.all;
  String searchKeyword = '';
  List<String> hotSearches = [];
  List<MusicPlaylist> playlists = [];
  List<MusicPlaylist> cloudPlaylists = [];
  List<MusicPlaylist> recommendedPlaylists = [];
  Set<String> likedTrackIds = {};
  Map<String, int> homeCardShapes = {};
  List<LyricLine> lyrics = [];
  bool instrumentalLyrics = false;
  List<LyricChoice> lyricChoices = [];
  ListeningStats stats = const ListeningStats();
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  final ValueNotifier<PlaybackTimeline> playbackTimeline = ValueNotifier(
    const PlaybackTimeline(position: Duration.zero, duration: Duration.zero),
  );
  final ValueNotifier<int> themeRevision = ValueNotifier(0);
  int lyricDelayMs = 0;
  int lyricFrameRate = 30;
  LyricScrollPreset lyricScrollPreset = LyricScrollPreset.balanced;
  double lyricScrollMass = LyricScrollPreset.balanced.mass;
  double lyricScrollStiffness = LyricScrollPreset.balanced.stiffness;
  double lyricScrollDamping = LyricScrollPreset.balanced.damping;
  AudioQuality quality = AudioQuality.exhigh;
  bool loading = true;
  bool searching = false;
  bool refreshing = false;
  bool loadingLyrics = false;
  bool searchingLyrics = false;
  bool preparingPlayback = false;
  bool dynamicColor = true;
  bool gradientPlayerBackground = false;
  bool singleColorPlayerBackground = false;
  bool efficientRendering = true;
  bool shuffleEnabled = false;
  PlaybackRepeatMode repeatMode = PlaybackRepeatMode.all;
  CoverColorStyle coverColorStyle = CoverColorStyle.analogous;
  ThemeMode themeMode = ThemeMode.system;
  int fontWeightLevel = 0;
  bool showTranslation = true;
  bool karaokeLyrics = true;
  List<LyricSource> lyricSourceOrder = LyricSource.values.toList();
  bool privateMode = false;
  bool loggedIn = false;
  String userId = '';
  String nickname = '未登录';
  String avatarUrl = '';
  String adapterEndpoint = '';
  String? message;
  static const _neutralPalette = <Color>[
    Color(0xff707070),
    Color(0xff565656),
    Color(0xff929292),
  ];
  static const _brandPalette = <Color>[
    Color(0xff514fa0),
    Color(0xff76528f),
    Color(0xffa45062),
  ];
  List<Color> _coverPalette = _neutralPalette;
  final Map<String, LyricsPayload> _lyricCache = {};
  String lyricChoicesTrackId = '';
  String _dailyCacheDate = '';

  bool get playing => player.playing;
  bool get hasCurrent => current.id.isNotEmpty;
  Duration get lyricPosition => position - Duration(milliseconds: lyricDelayMs);
  Color get seedColor => _coverPalette.first;
  List<Color> get coverPalette => dynamicColor ? _coverPalette : _brandPalette;
  FontWeight get normalWeight => switch (fontWeightLevel) {
    0 => FontWeight.w300,
    1 => FontWeight.w400,
    _ => FontWeight.w500,
  };
  FontWeight get emphasisWeight => switch (fontWeightLevel) {
    0 => FontWeight.w500,
    1 => FontWeight.w600,
    _ => FontWeight.w700,
  };
  String get fontWeightLabel => switch (fontWeightLevel) {
    0 => '轻盈',
    1 => '标准',
    _ => '清晰',
  };
  List<MusicPlaylist> get allPlaylists => [...playlists, ...cloudPlaylists];
  bool isLiked(Track track) => likedTrackIds.contains(track.id);
  bool get hasCachedCurrentLyrics => _lyricCache.containsKey(current.id);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    adapterEndpoint = _prefs?.getString('adapterEndpoint') ?? '';
    dynamicColor = _prefs?.getBool('dynamicColor') ?? true;
    // Restore the original static cover-derived surface for existing installs
    // as well as new ones. Later explicit user choices remain persistent.
    if (_prefs?.getBool('staticCoverBackgroundMigrationV1') != true) {
      await _prefs?.setBool('gradientPlayerBackground', false);
      await _prefs?.setBool('staticCoverBackgroundMigrationV1', true);
    }
    gradientPlayerBackground =
        _prefs?.getBool('gradientPlayerBackground') ?? false;
    singleColorPlayerBackground =
        _prefs?.getBool('singleColorPlayerBackground') ?? false;
    efficientRendering = _prefs?.getBool('efficientRendering') ?? true;
    shuffleEnabled = _prefs?.getBool('shuffleEnabled') ?? false;
    final savedRepeatName = _prefs?.getString('repeatModeName');
    final legacyRepeatIndex = _prefs?.getInt('repeatMode');
    repeatMode =
        savedRepeatName == PlaybackRepeatMode.one.name ||
            (savedRepeatName == null && legacyRepeatIndex == 2)
        ? PlaybackRepeatMode.one
        : PlaybackRepeatMode.all;
    coverColorStyle =
        CoverColorStyle.values[(_prefs?.getInt('coverColorStyle') ??
                CoverColorStyle.analogous.index)
            .clamp(0, CoverColorStyle.values.length - 1)];
    final savedThemeMode = _prefs?.getString('themeMode') ?? 'system';
    themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == savedThemeMode,
      orElse: () => ThemeMode.system,
    );
    fontWeightLevel = (_prefs?.getInt('fontWeightLevel') ?? 0).clamp(0, 2);
    showTranslation = _prefs?.getBool('showTranslation') ?? true;
    karaokeLyrics = _prefs?.getBool('karaokeLyrics') ?? true;
    final savedLyricSources = _prefs?.getStringList('lyricSourceOrder') ?? [];
    lyricSourceOrder = LyricSource.values.toList()
      ..sort((a, b) {
        final aIndex = savedLyricSources.indexOf(a.id);
        final bIndex = savedLyricSources.indexOf(b.id);
        final aOrder = aIndex < 0 ? savedLyricSources.length + a.index : aIndex;
        final bOrder = bIndex < 0 ? savedLyricSources.length + b.index : bIndex;
        return aOrder.compareTo(bOrder);
      });
    privateMode = _prefs?.getBool('privateMode') ?? false;
    lyricDelayMs = _prefs?.getInt('lyricDelayMs') ?? 0;
    lyricFrameRate = (_prefs?.getInt('lyricFrameRate') ?? 30).clamp(15, 60);
    lyricScrollPreset =
        LyricScrollPreset.values[(_prefs?.getInt('lyricScrollPreset') ??
                LyricScrollPreset.balanced.index)
            .clamp(0, LyricScrollPreset.values.length - 1)];
    lyricScrollMass = lyricScrollPreset == LyricScrollPreset.custom
        ? (_prefs?.getDouble('lyricScrollMass') ??
              LyricScrollPreset.balanced.mass)
        : lyricScrollPreset.mass;
    lyricScrollStiffness = lyricScrollPreset == LyricScrollPreset.custom
        ? (_prefs?.getDouble('lyricScrollStiffness') ??
              LyricScrollPreset.balanced.stiffness)
        : lyricScrollPreset.stiffness;
    lyricScrollDamping = lyricScrollPreset == LyricScrollPreset.custom
        ? (_prefs?.getDouble('lyricScrollDamping') ??
              LyricScrollPreset.balanced.damping)
        : lyricScrollPreset.damping;
    quality = AudioQuality
        .values[_prefs?.getInt('quality') ?? AudioQuality.exhigh.index];
    _restoreLocalData();
    _syncPlaybackTimeline();

    api = NeteaseApi();
    await api.initialize();
    // One-time migration from the first prototype's unencrypted preference.
    final legacyCookie = _prefs?.getString('cookie') ?? '';
    if (legacyCookie.isNotEmpty) {
      await api.importCookie(legacyCookie);
      await _prefs?.remove('cookie');
    }
    _rebuildSources();
    _listenToPlayer();
    if (hasCurrent) {
      unawaited(_extractCoverColor(current));
      unawaited(loadLyrics(current));
    }
    _saveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      // Playback only changes the current position and listening time. Avoid
      // repeatedly encoding every playlist and cached lyric while a song is
      // playing; those collections are persisted when they actually change.
      unawaited(_persistPlaybackCheckpoint());
      if (!refreshing && _dailyCacheDate != _todayKey()) {
        unawaited(refreshAll());
      }
    });

    loading = false;
    notifyListeners();
    final hasDailyData =
        recommendations.isNotEmpty ||
        recommendedPlaylists.isNotEmpty ||
        hotSearches.isNotEmpty ||
        cloudPlaylists.isNotEmpty;
    if (_dailyCacheDate != _todayKey() || !hasDailyData) {
      unawaited(refreshAll());
    }
  }

  void _restoreLocalData() {
    final storedPlaylists = _prefs?.getString('playlists');
    final storedStats = _prefs?.getString('stats');
    final storedRecent = _prefs?.getString('recent');
    _dailyCacheDate = _prefs?.getString('dailyCacheDate') ?? '';
    if (storedPlaylists != null) {
      playlists = (jsonDecode(storedPlaylists) as List<dynamic>)
          .map((item) => MusicPlaylist.fromJson(item as Map<String, dynamic>))
          .where(
            (item) => !{'saved', 'morning', 'road', 'night'}.contains(item.id),
          )
          .toList();
    }
    if (storedStats != null) {
      stats = ListeningStats.fromJson(
        jsonDecode(storedStats) as Map<String, dynamic>,
      );
    }
    if (storedRecent != null) {
      recent = (jsonDecode(storedRecent) as List<dynamic>)
          .map((item) => Track.fromJson(item as Map<String, dynamic>))
          .where((item) => !item.id.startsWith('demo'))
          .toList();
    }
    try {
      recommendations = _restoreTracks('recommendations');
      cloudHistory = _restoreTracks('cloudHistory');
      cloudPlaylists = _restorePlaylists('cloudPlaylists');
      recommendedPlaylists = _restorePlaylists('recommendedPlaylists');
      hotSearches = ((_decodePreference('hotSearches') ?? []) as List<dynamic>)
          .map((item) => '$item')
          .toList();
      likedTrackIds =
          ((_decodePreference('likedTrackIds') ?? []) as List<dynamic>)
              .map((item) => '$item')
              .toSet();
      final savedCardShapes = _decodePreference('homeCardShapes');
      if (savedCardShapes is Map<String, dynamic>) {
        homeCardShapes = savedCardShapes.map(
          (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
        );
      }
      queue = _restoreTracks('playQueue');
      final savedCurrent = _decodePreference('currentTrack');
      if (savedCurrent is Map<String, dynamic>) {
        final restored = Track.fromJson(savedCurrent);
        if (restored.id.isNotEmpty && !restored.id.startsWith('demo')) {
          current = restored;
          position = Duration(
            milliseconds: _prefs?.getInt('currentPositionMs') ?? 0,
          );
          duration = restored.duration;
          if (queue.every((item) => item.id != restored.id)) {
            queue = [restored, ...queue];
          }
        }
      }
      final account = _decodePreference('accountCache');
      if (account is Map<String, dynamic>) {
        loggedIn = account['loggedIn'] == true;
        userId = '${account['userId'] ?? ''}';
        nickname = '${account['nickname'] ?? '未登录'}';
        avatarUrl = '${account['avatarUrl'] ?? ''}';
      }
      final lyricData =
          _prefs?.getInt('lyricCacheVersion') == _lyricCacheVersion
          ? _decodePreference('lyricCache')
          : null;
      if (lyricData is Map<String, dynamic>) {
        for (final entry in lyricData.entries) {
          if (entry.value is Map<String, dynamic>) {
            _lyricCache[entry.key] = LyricsPayload.fromJson(
              entry.value as Map<String, dynamic>,
            );
          }
        }
      }
    } catch (_) {
      // Ignore a damaged cache and refresh it from the service.
    }
  }

  dynamic _decodePreference(String key) {
    final raw = _prefs?.getString(key);
    return raw == null || raw.isEmpty ? null : jsonDecode(raw);
  }

  List<Track> _restoreTracks(String key) =>
      ((_decodePreference(key) ?? []) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Track.fromJson)
          .toList();

  List<MusicPlaylist> _restorePlaylists(String key) =>
      ((_decodePreference(key) ?? []) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(MusicPlaylist.fromJson)
          .toList();

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  void _rebuildSources() {
    sources = SourceResolver([
      // 1) 已登录网易云且拥有 VIP 时，官方接口直接返回完整播放地址；
      //    无 VIP / 受限曲目（freeTrial）会返回 null，回退到下方解锁链。
      NeteaseOfficialAdapter(api),
      // 2) 破解音源：网易云镜像 + 酷我 bodian + 酷我多源兜底。
      UnlockSourceAdapter(),
      // 3) 用户自备的授权音源端点（最后兜底）。
      UserEndpointAdapter(adapterEndpoint),
    ]);
  }

  void _listenToPlayer() {
    _positionSub = player.positionStream.listen((value) {
      final delta = value - position;
      position = value;
      if (player.playing &&
          delta > Duration.zero &&
          delta < const Duration(seconds: 3) &&
          !privateMode) {
        // positionStream can tick several times per second. Keeping those
        // deltas in a scalar prevents a fresh stats map allocation per tick.
        _uncommittedListeningTime += delta;
      }
      _syncPlaybackTimeline();
    });
    _playerSub = player.playerStateStream.listen((value) {
      if (value.processingState == ProcessingState.completed &&
          !_advancingAfterCompletion &&
          hasCurrent) {
        _advancingAfterCompletion = true;
        unawaited(
          _advanceAfterCompletion().whenComplete(() {
            if (player.processingState != ProcessingState.completed) {
              _advancingAfterCompletion = false;
            }
          }),
        );
      } else if (value.processingState != ProcessingState.completed) {
        _advancingAfterCompletion = false;
      }
      notifyListeners();
    });
    _durationSub = player.durationStream.listen((value) {
      if (value != null) {
        duration = value;
        _syncPlaybackTimeline();
        if (value > Duration.zero &&
            value < const Duration(seconds: 20) &&
            !preparingPlayback &&
            !_switchingShortSource &&
            _activeSourceUri != null &&
            hasCurrent) {
          unawaited(_switchFromShortSource(value));
        }
      }
    });
  }

  Future<void> _switchFromShortSource(Duration detectedDuration) async {
    final uri = _activeSourceUri;
    if (_switchingShortSource || uri == null || !hasCurrent) return;
    _switchingShortSource = true;
    final track = current;
    final activeQueue = List<Track>.of(queue);
    sources.reject(track, quality, uri);
    _activeSourceUri = null;
    final notice = '检测到 ${detectedDuration.inSeconds} 秒试听音源，正在切换完整音源';
    message = notice;
    notifyListeners();
    try {
      await player.stop();
      await playTrack(track, from: activeQueue);
    } finally {
      _switchingShortSource = false;
      final settledDuration = player.duration;
      if (settledDuration != null &&
          settledDuration > Duration.zero &&
          settledDuration < const Duration(seconds: 20) &&
          _activeSourceUri != null) {
        unawaited(_switchFromShortSource(settledDuration));
      }
    }
  }

  void _syncPlaybackTimeline() {
    final previous = playbackTimeline.value;
    if (previous.position == position && previous.duration == duration) return;
    playbackTimeline.value = PlaybackTimeline(
      position: position,
      duration: duration,
    );
  }

  void setTab(int value) {
    tab = value;
    notifyListeners();
  }

  Future<void> refreshAll() async {
    refreshing = true;
    message = null;
    notifyListeners();
    final accountUpdated = await refreshAccount();
    final recommendationsUpdated = await refreshRecommendations();
    if (accountUpdated || recommendationsUpdated) {
      _dailyCacheDate = _todayKey();
      await persist();
    }
    refreshing = false;
    notifyListeners();
  }

  Future<void> playTrack(
    Track track, {
    List<Track>? from,
    Duration startAt = Duration.zero,
  }) async {
    if (preparingPlayback && current.id == track.id) return;
    final requestSerial = ++_playRequestSerial;
    preparingPlayback = true;
    _activeSourceUri = null;
    current = track;
    _coverPalette = _neutralPalette;
    _notifyThemeChanged();
    if (from != null) queue = List.of(from);
    if (queue.every((item) => item.id != track.id)) queue = [track, ...queue];
    recent = [
      track,
      ...recent.where((item) => item.id != track.id),
    ].take(40).toList();
    lyrics = [];
    instrumentalLyrics = false;
    lyricChoices = [];
    lyricChoicesTrackId = '';
    position = startAt;
    duration = track.duration;
    _syncPlaybackTimeline();
    message = null;
    final queueIndex = queue.indexWhere((item) => item.id == track.id);
    audioHandler.publishQueue(
      queue.map(_mediaItemForTrack).toList(),
      queueIndex < 0 ? 0 : queueIndex,
    );
    notifyListeners();
    unawaited(_extractCoverColor(track));
    unawaited(loadLyrics(track));
    Object? lastError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        final uri = await sources.resolve(track, quality);
        if (requestSerial != _playRequestSerial) return;
        if (uri == null) {
          lastError = '当前账号或地区没有可用的完整播放地址';
        } else {
          final previousMutation = _sourceMutation;
          final mutationDone = Completer<void>();
          _sourceMutation = mutationDone.future;
          await previousMutation.catchError((_) {});
          try {
            if (requestSerial != _playRequestSerial) return;
            final resolvedDuration = await player.setAudioSource(
              AudioSource.uri(
                uri,
                tag: MediaItem(
                  id: track.id,
                  album: track.album,
                  title: track.title,
                  artist: track.artist,
                  duration: track.duration,
                  artUri: _artUriForTrack(track),
                  artHeaders: track.coverUrl.isEmpty
                      ? null
                      : neteaseArtworkHeaders,
                ),
              ),
              initialPosition: startAt,
            );
            final detectedDuration = player.duration ?? resolvedDuration;
            if (detectedDuration != null &&
                detectedDuration > Duration.zero &&
                detectedDuration < const Duration(seconds: 20)) {
              sources.reject(track, quality, uri);
              await player.stop();
              throw StateError(
                '检测到 ${detectedDuration.inSeconds} 秒试听音源，正在自动切换',
              );
            }
            _activeSourceUri = uri;
          } finally {
            if (!mutationDone.isCompleted) mutationDone.complete();
          }
          if (requestSerial != _playRequestSerial) return;
          _commitListeningTime();
          if (!privateMode) {
            stats = stats.add(Duration.zero, newPlay: true);
          }
          preparingPlayback = false;
          message = null;
          notifyListeners();
          unawaited(persist());
          unawaited(
            audioHandler.play().catchError((Object error) {
              if (requestSerial == _playRequestSerial &&
                  current.id == track.id) {
                message = '播放失败：$error';
                notifyListeners();
              }
            }),
          );
          final index = queue.indexWhere((item) => item.id == track.id);
          if (queue.length > 1 && index >= 0) {
            final next = queue[(index + 1) % queue.length];
            if (next.id != track.id) unawaited(sources.prefetch(next, quality));
          }
          return;
        }
      } catch (error) {
        lastError = error;
        sources.invalidate(track, quality);
      }
      if (attempt < 5) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    }
    if (requestSerial != _playRequestSerial) return;
    preparingPlayback = false;
    message = '播放失败：$lastError';
    notifyListeners();
  }

  Future<void> togglePlay() async {
    if (preparingPlayback) return;
    if (player.playing) {
      await audioHandler.pause();
    } else if (player.audioSource != null) {
      await audioHandler.play();
    } else {
      if (hasCurrent) {
        await playTrack(current, from: queue, startAt: position);
      }
    }
  }

  MediaItem _mediaItemForTrack(Track track) => MediaItem(
    id: track.id,
    album: track.album,
    title: track.title,
    artist: track.artist,
    duration: track.duration,
    artUri: _artUriForTrack(track),
    artHeaders: track.coverUrl.isEmpty ? null : neteaseArtworkHeaders,
  );

  Uri? _artUriForTrack(Track track) {
    final url = neteaseArtworkUrl(track.coverUrl, size: 512);
    return url.isEmpty ? null : Uri.tryParse(url);
  }

  Future<void> seek(Duration value) => player.seek(value);

  Future<void> skip(int offset) async {
    if (queue.isEmpty) return;
    final currentIndex = queue.indexWhere((item) => item.id == current.id);
    if (shuffleEnabled && offset > 0 && queue.length > 1) {
      final candidates = queue.where((item) => item.id != current.id).toList();
      final next = candidates[math.Random().nextInt(candidates.length)];
      await playTrack(next, from: queue);
      return;
    }
    final next = (currentIndex + offset) % queue.length;
    await playTrack(queue[next < 0 ? next + queue.length : next], from: queue);
  }

  Future<void> _advanceAfterCompletion() async {
    if (repeatMode == PlaybackRepeatMode.one) {
      await playTrack(current, from: queue);
      return;
    }
    if (queue.length <= 1) {
      await playTrack(current, from: queue);
      return;
    }
    await skip(1);
  }

  Future<void> toggleShuffle() async {
    shuffleEnabled = !shuffleEnabled;
    await _prefs?.setBool('shuffleEnabled', shuffleEnabled);
    notifyListeners();
  }

  Future<void> cycleRepeatMode() async {
    repeatMode = repeatMode == PlaybackRepeatMode.all
        ? PlaybackRepeatMode.one
        : PlaybackRepeatMode.all;
    await _prefs?.setInt('repeatMode', repeatMode.index);
    await _prefs?.setString('repeatModeName', repeatMode.name);
    notifyListeners();
  }

  void enqueueNext(Track track) {
    if (!hasCurrent) {
      unawaited(playTrack(track, from: [track]));
      return;
    }
    if (track.id == current.id) {
      message = '这首歌正在播放';
      _clearMessageLater(message!);
      notifyListeners();
      return;
    }
    final next = queue.where((item) => item.id != track.id).toList();
    var currentIndex = next.indexWhere((item) => item.id == current.id);
    if (currentIndex < 0) {
      next.insert(0, current);
      currentIndex = 0;
    }
    next.insert(currentIndex + 1, track);
    queue = next;
    audioHandler.publishQueue(
      queue.map(_mediaItemForTrack).toList(),
      currentIndex,
    );
    message = '已设为下一首播放';
    _clearMessageLater(message!);
    unawaited(persist());
    unawaited(sources.prefetch(track, quality));
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= queue.length) return;
    if (newIndex > oldIndex) newIndex--;
    if (newIndex < 0 || newIndex >= queue.length || newIndex == oldIndex) {
      return;
    }
    final next = List<Track>.of(queue);
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    queue = next;
    unawaited(persist());
    notifyListeners();
  }

  void removeFromQueue(Track track) {
    if (track.id == current.id) {
      message = '正在播放的歌曲会保留在队列中';
      _clearMessageLater(message!);
      notifyListeners();
      return;
    }
    queue = queue.where((item) => item.id != track.id).toList();
    unawaited(persist());
    notifyListeners();
  }

  void clearUpcomingQueue() {
    queue = hasCurrent ? [current] : [];
    unawaited(persist());
    notifyListeners();
  }

  int cardShape(String id, int fallback) =>
      (homeCardShapes[id] ?? 4).clamp(0, 13);

  void setCardShape(String id, int value) => setCardShapes([id], value);

  void setCardShapes(Iterable<String> ids, int value) {
    final next = Map<String, int>.of(homeCardShapes);
    for (final id in ids) {
      next[id] = value.clamp(0, 13);
    }
    homeCardShapes = next;
    unawaited(
      _prefs?.setString('homeCardShapes', jsonEncode(homeCardShapes)) ??
          Future<void>.value(),
    );
    notifyListeners();
  }

  void _clearMessageLater(String notice) {
    _messageTimer?.cancel();
    _messageTimer = Timer(const Duration(seconds: 2), () {
      if (message != notice) return;
      message = null;
      notifyListeners();
    });
  }

  Future<void> setQuality(AudioQuality value) async {
    quality = value;
    await _prefs?.setInt('quality', value.index);
    notifyListeners();
    if (player.audioSource != null) {
      final resumeAt = position;
      await playTrack(current, from: queue);
      await seek(resumeAt);
    }
  }

  Future<void> loadLyrics([Track? source, bool force = false]) async {
    final target = source ?? current;
    if (target.id.isEmpty) return;
    final cached = _lyricCache[target.id];
    if (!force && cached != null && cached.hasLyrics) {
      if (current.id == target.id) _applyLyrics(cached);
      notifyListeners();
      return;
    }
    loadingLyrics = true;
    notifyListeners();
    try {
      final payload = await api.lyrics(target.id, track: target);
      _cacheLyrics(target.id, payload);
      if (current.id == target.id) _applyLyrics(payload);
    } catch (error) {
      message = '歌词获取失败：$error';
    } finally {
      loadingLyrics = false;
      notifyListeners();
    }
  }

  void _applyLyrics(LyricsPayload payload) {
    instrumentalLyrics = false;
    if (payload.ttml.isNotEmpty && karaokeLyrics) {
      try {
        final parsed = LyricsParser.parseTtml(payload.ttml);
        if (_useParsedLyrics(parsed)) return;
      } catch (_) {
        // Fall through to the platform lyric formats.
      }
    }
    if (payload.yrc.isNotEmpty && karaokeLyrics) {
      final parsed = LyricsParser.parseYrc(
        payload.yrc,
        translation: payload.translation,
      );
      if (_useParsedLyrics(parsed)) return;
    }
    if (payload.qrc.isNotEmpty && karaokeLyrics) {
      try {
        final parsed = LyricsParser.parseQrc(
          payload.qrc,
          translation: payload.translation,
        );
        if (_useParsedLyrics(parsed)) return;
      } catch (_) {
        // Continue with the plain lyric when QRC XML is malformed.
      }
    }
    if (payload.lrc.isNotEmpty) {
      final parsed = LyricsParser.parse(
        payload.lrc,
        translation: payload.translation,
      );
      if (_useParsedLyrics(parsed)) return;
    }
    lyrics = [];
  }

  bool _useParsedLyrics(List<LyricLine> parsed) {
    if (parsed.isEmpty) return false;
    final isInstrumental = LyricsParser.containsInstrumentalPlaceholder(parsed);
    final cleaned = LyricsParser.withoutCredits(parsed);
    if (cleaned.isNotEmpty) {
      instrumentalLyrics = false;
      lyrics = LyricsParser.withInterludes(cleaned);
      return true;
    }
    if (isInstrumental) {
      instrumentalLyrics = true;
      lyrics = [];
      return true;
    }
    return false;
  }

  Future<void> searchLyrics(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return;
    searchingLyrics = true;
    lyricChoices = [];
    lyricChoicesTrackId = current.id;
    notifyListeners();
    try {
      lyricChoices = await api.searchLyrics(query, preferredTrack: current);
      _sortLyricChoices();
    } catch (error) {
      message = '歌词搜索失败：$error';
    } finally {
      searchingLyrics = false;
      notifyListeners();
    }
  }

  String get lyricSourceOrderLabel =>
      lyricSourceOrder.map((source) => source.label).join(' › ');

  void moveLyricSource(int from, int to) {
    if (from < 0 ||
        to < 0 ||
        from >= lyricSourceOrder.length ||
        to >= lyricSourceOrder.length ||
        from == to) {
      return;
    }
    final source = lyricSourceOrder.removeAt(from);
    lyricSourceOrder.insert(to, source);
    _prefs?.setStringList(
      'lyricSourceOrder',
      lyricSourceOrder.map((source) => source.id).toList(),
    );
    _sortLyricChoices();
    notifyListeners();
  }

  void _sortLyricChoices() {
    final ranked = [
      for (var index = 0; index < lyricChoices.length; index++)
        (
          choice: lyricChoices[index],
          index: index,
          wordSynced: lyricChoices[index].isWordSynced,
        ),
    ];
    ranked.sort((a, b) {
      if (karaokeLyrics && a.wordSynced != b.wordSynced) {
        return a.wordSynced ? -1 : 1;
      }
      final sourceOrder = lyricSourceOrder
          .indexOf(a.choice.sourceType)
          .compareTo(lyricSourceOrder.indexOf(b.choice.sourceType));
      return sourceOrder != 0 ? sourceOrder : a.index.compareTo(b.index);
    });
    lyricChoices = ranked.map((entry) => entry.choice).toList();
  }

  void selectLyrics(LyricChoice choice) {
    final cachedTranslation = _lyricCache[current.id]?.translation ?? '';
    final payload = LyricsPayload(
      lrc: choice.payload.lrc,
      translation: choice.payload.translation.isNotEmpty
          ? choice.payload.translation
          : cachedTranslation,
      yrc: choice.payload.yrc,
      ttml: choice.payload.ttml,
      qrc: choice.payload.qrc,
    );
    _applyLyrics(payload);
    if (current.id.isNotEmpty) _cacheLyrics(current.id, payload);
    final hasTimedWords = lyrics.any(
      (line) => line.words.isNotEmpty || line.backgroundWords.isNotEmpty,
    );
    final notice = hasTimedWords ? '已切换为逐字歌词' : '已切换为普通歌词';
    message = notice;
    _clearMessageLater(notice);
    notifyListeners();
  }

  void _cacheLyrics(String trackId, LyricsPayload payload) {
    _lyricCache.remove(trackId);
    _lyricCache[trackId] = payload;
    while (_lyricCache.length > 30) {
      _lyricCache.remove(_lyricCache.keys.first);
    }
    unawaited(_persistLyricCache());
  }

  Future<void> _persistLyricCache() async {
    await _prefs?.setInt('lyricCacheVersion', _lyricCacheVersion);
    await _prefs?.setString(
      'lyricCache',
      jsonEncode(
        _lyricCache.map((key, payload) => MapEntry(key, payload.toJson())),
      ),
    );
  }

  Future<void> setLyricDelay(int milliseconds) async {
    lyricDelayMs = milliseconds.clamp(-5000, 5000);
    await _prefs?.setInt('lyricDelayMs', lyricDelayMs);
    notifyListeners();
  }

  Future<void> setLyricFrameRate(int value) async {
    lyricFrameRate = value.clamp(15, 60);
    await _prefs?.setInt('lyricFrameRate', lyricFrameRate);
    notifyListeners();
  }

  Future<void> setLyricScrollPreset(LyricScrollPreset preset) async {
    lyricScrollPreset = preset;
    if (preset != LyricScrollPreset.custom) {
      lyricScrollMass = preset.mass;
      lyricScrollStiffness = preset.stiffness;
      lyricScrollDamping = preset.damping;
    }
    await _persistLyricScrollMotion();
    notifyListeners();
  }

  void previewLyricScrollMotion({
    double? mass,
    double? stiffness,
    double? damping,
  }) {
    lyricScrollPreset = LyricScrollPreset.custom;
    lyricScrollMass = (mass ?? lyricScrollMass).clamp(.5, 2);
    lyricScrollStiffness = (stiffness ?? lyricScrollStiffness).clamp(80, 420);
    lyricScrollDamping = (damping ?? lyricScrollDamping).clamp(8, 48);
    notifyListeners();
  }

  Future<void> saveLyricScrollMotion() => _persistLyricScrollMotion();

  Future<void> _persistLyricScrollMotion() async {
    await Future.wait([
      _prefs?.setInt('lyricScrollPreset', lyricScrollPreset.index) ??
          Future.value(true),
      _prefs?.setDouble('lyricScrollMass', lyricScrollMass) ??
          Future.value(true),
      _prefs?.setDouble('lyricScrollStiffness', lyricScrollStiffness) ??
          Future.value(true),
      _prefs?.setDouble('lyricScrollDamping', lyricScrollDamping) ??
          Future.value(true),
    ]);
  }

  Future<void> search(String keyword) async {
    searchKeyword = keyword.trim();
    if (keyword.trim().isEmpty) {
      searchResults = [];
      notifyListeners();
      return;
    }
    searching = true;
    message = null;
    notifyListeners();
    try {
      final query = keyword.trim();
      final results = switch (searchSource) {
        MusicSearchSource.netease => [
          await api.search(query).catchError((_) => <Track>[]),
        ],
        MusicSearchSource.kuwo => [
          await searchUnlockSources(query).catchError((_) => <Track>[]),
        ],
        MusicSearchSource.all => await Future.wait([
          api.search(query).catchError((_) => <Track>[]),
          searchUnlockSources(query).catchError((_) => <Track>[]),
        ]),
      };
      final seen = <String>{};
      searchResults = [
        for (final group in results)
          for (final track in group)
            if (track.duration >= const Duration(seconds: 20) &&
                seen.add(track.id))
              track,
      ];
      if (searchResults.isEmpty) message = '没有找到匹配歌曲';
    } catch (error) {
      searchResults = [];
      message = '多音源搜索暂不可用：$error';
    } finally {
      searching = false;
      notifyListeners();
    }
  }

  void setSearchSource(MusicSearchSource value) {
    if (searchSource == value) return;
    searchSource = value;
    notifyListeners();
    if (searchKeyword.isNotEmpty) unawaited(search(searchKeyword));
  }

  Future<bool> refreshRecommendations() async {
    var success = false;
    try {
      final songs = await api.personalizedSongs();
      recommendations = songs;
      success = true;
    } catch (_) {}
    try {
      final lists = await api.recommendedPlaylists();
      recommendedPlaylists = lists;
      success = true;
    } catch (_) {}
    try {
      hotSearches = await api.hotSearch();
      success = true;
    } catch (_) {}
    if (!success) message ??= '推荐暂时无法刷新，请稍后重试';
    notifyListeners();
    return success;
  }

  Future<bool> refreshAccount() async {
    try {
      final profile = await api.account();
      if (profile == null) {
        loggedIn = false;
        userId = '';
        nickname = '未登录';
        avatarUrl = '';
        cloudPlaylists = [];
        cloudHistory = [];
        likedTrackIds = {};
        return true;
      }
      loggedIn = true;
      userId = profile.userId;
      nickname = profile.nickname;
      avatarUrl = profile.avatarUrl;
      final values = await Future.wait([
        api.userPlaylists(userId),
        api.listeningHistory(userId),
        api.likedIds(userId),
      ]);
      final incomingPlaylists = values[0] as List<MusicPlaylist>;
      cloudPlaylists = incomingPlaylists.map((playlist) {
        final cached = cloudPlaylists.where(
          (item) =>
              item.id == playlist.id &&
              item.hasCompleteTrackDetail &&
              // Reuse detail only while the server-reported count still
              // matches. A changed count invalidates stale persisted tracks.
              (playlist.trackCount <= 0 ||
                  item.tracks.length == playlist.trackCount),
        );
        if (cached.isEmpty) return playlist;
        final detail = cached.first;
        return MusicPlaylist(
          id: playlist.id,
          name: playlist.name,
          coverUrl: playlist.coverUrl,
          tracks: detail.tracks,
          description: playlist.description,
          trackCount: playlist.trackCount,
        );
      }).toList();
      cloudHistory = values[1] as List<Track>;
      likedTrackIds = values[2] as Set<String>;
      notifyListeners();
      return true;
    } catch (_) {
      loggedIn = api.hasAuthenticatedSession;
      notifyListeners();
      return false;
    }
  }

  Future<void> finishLogin(String newCookie) async {
    if (newCookie.isNotEmpty) await api.importCookie(newCookie);
    await refreshAccount();
    await refreshRecommendations();
    _dailyCacheDate = _todayKey();
    await persist();
  }

  Future<void> logout() async {
    await api.logout();
    loggedIn = false;
    userId = '';
    nickname = '未登录';
    avatarUrl = '';
    cloudPlaylists = [];
    cloudHistory = [];
    likedTrackIds = {};
    _dailyCacheDate = '';
    await persist();
    notifyListeners();
  }

  Future<MusicPlaylist> loadPlaylist(
    MusicPlaylist playlist, {
    bool forceRefresh = false,
  }) async {
    if (playlists.any((item) => item.id == playlist.id)) {
      return playlist;
    }
    if (!forceRefresh && playlist.hasCompleteTrackDetail) {
      return playlist;
    }
    try {
      final detail = await api.playlistDetail(playlist.id);
      cloudPlaylists = cloudPlaylists
          .map((item) => item.id == detail.id ? detail : item)
          .toList();
      unawaited(persist());
      if (forceRefresh) {
        final notice = '歌单已刷新，共 ${detail.displayTrackCount} 首';
        message = notice;
        _clearMessageLater(notice);
        notifyListeners();
      }
      return detail;
    } catch (error) {
      message = '歌单加载失败：$error';
      notifyListeners();
      return playlist;
    }
  }

  Future<void> createPlaylist(String name, {bool local = true}) async {
    if (name.trim().isEmpty) return;
    if (!local && loggedIn) {
      try {
        final created = await api.createPlaylist(name.trim());
        if (created != null) {
          cloudPlaylists = [created, ...cloudPlaylists];
          notifyListeners();
          return;
        }
      } catch (error) {
        message = '云歌单创建失败，已创建本地歌单：$error';
      }
    }
    playlists = [
      ...playlists,
      MusicPlaylist(
        id: 'local-${DateTime.now().millisecondsSinceEpoch}',
        name: name.trim(),
        coverUrl: '',
        tracks: const [],
      ),
    ];
    await persist();
    notifyListeners();
  }

  Future<MusicPlaylist?> importPlaylistToLocal(MusicPlaylist source) async {
    final isCloud = cloudPlaylists.any((item) => item.id == source.id);
    if (!isCloud) return source;
    final detail = await loadPlaylist(source, forceRefresh: true);
    if (detail.tracks.isEmpty) {
      message = '导入失败：没有读取到歌单曲目';
      notifyListeners();
      return null;
    }
    final imported = MusicPlaylist(
      id: 'local-import-${DateTime.now().millisecondsSinceEpoch}',
      name: detail.name,
      coverUrl: detail.coverUrl,
      tracks: List<Track>.of(detail.tracks),
      description: '从网易云音乐导入 · 本地歌单',
      trackCount: detail.tracks.length,
    );
    playlists = [imported, ...playlists];
    await persist();
    final notice = '已导入到本地歌单“${detail.name}”';
    message = notice;
    _clearMessageLater(notice);
    notifyListeners();
    return imported;
  }

  Future<void> addToPlaylist(Track track, MusicPlaylist target) async {
    final cloudTarget = cloudPlaylists.any((item) => item.id == target.id);
    if (cloudTarget) {
      if (!RegExp(r'^\d+$').hasMatch(track.id)) {
        message = '该歌曲来自其他音源，请添加到本地歌单';
        notifyListeners();
        return;
      }
      try {
        final ok = await api.addTracks(target.id, [track.id]);
        message = ok ? '已添加到 ${target.name}' : '添加失败';
        if (ok) {
          cloudPlaylists = cloudPlaylists.map((playlist) {
            if (playlist.id != target.id ||
                playlist.tracks.any((item) => item.id == track.id)) {
              return playlist;
            }
            return MusicPlaylist(
              id: playlist.id,
              name: playlist.name,
              coverUrl: playlist.coverUrl.isEmpty
                  ? track.coverUrl
                  : playlist.coverUrl,
              tracks: [...playlist.tracks, track],
              description: playlist.description,
              trackCount: math.max(
                playlist.trackCount + 1,
                playlist.tracks.length + 1,
              ),
            );
          }).toList();
          unawaited(persist());
        }
      } catch (error) {
        message = '添加失败：$error';
      }
      notifyListeners();
      return;
    }
    playlists = playlists.map((playlist) {
      if (playlist.id != target.id ||
          playlist.tracks.any((item) => item.id == track.id)) {
        return playlist;
      }
      return MusicPlaylist(
        id: playlist.id,
        name: playlist.name,
        coverUrl: playlist.coverUrl.isEmpty
            ? track.coverUrl
            : playlist.coverUrl,
        tracks: [...playlist.tracks, track],
        description: playlist.description,
      );
    }).toList();
    await persist();
    notifyListeners();
  }

  Future<void> toggleLike(Track track) async {
    final next = !likedTrackIds.contains(track.id);
    if (track.id.isNotEmpty && loggedIn) {
      try {
        if (!await api.like(track.id, next)) return;
      } catch (error) {
        message = '收藏失败：$error';
        notifyListeners();
        return;
      }
    }
    if (next) {
      likedTrackIds.add(track.id);
    } else {
      likedTrackIds.remove(track.id);
    }
    notifyListeners();
  }

  Future<void> updateSourceEndpoint(String sourceUrl) async {
    adapterEndpoint = sourceUrl.trim();
    await _prefs?.setString('adapterEndpoint', adapterEndpoint);
    _rebuildSources();
    notifyListeners();
  }

  void setSetting(String key, bool value) {
    switch (key) {
      case 'dynamicColor':
        dynamicColor = value;
      case 'gradientPlayerBackground':
        gradientPlayerBackground = value;
      case 'singleColorPlayerBackground':
        singleColorPlayerBackground = value;
      case 'efficientRendering':
        efficientRendering = value;
      case 'showTranslation':
        showTranslation = value;
      case 'karaokeLyrics':
        karaokeLyrics = value;
      case 'privateMode':
        privateMode = value;
    }
    _prefs?.setBool(key, value);
    if (key == 'karaokeLyrics') _sortLyricChoices();
    if (key == 'dynamicColor') _notifyThemeChanged();
    notifyListeners();
    if (key == 'dynamicColor' && value && hasCurrent) {
      unawaited(_extractCoverColor(current));
    }
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    await _prefs?.setString('themeMode', value.name);
    _notifyThemeChanged();
    notifyListeners();
  }

  Future<void> setFontWeightLevel(int value) async {
    fontWeightLevel = value.clamp(0, 2);
    await _prefs?.setInt('fontWeightLevel', fontWeightLevel);
    _notifyThemeChanged();
    notifyListeners();
  }

  Future<void> setCoverColorStyle(CoverColorStyle value) async {
    if (coverColorStyle == value) return;
    coverColorStyle = value;
    await _prefs?.setInt('coverColorStyle', value.index);
    if (hasCurrent && dynamicColor) {
      _coverPalette = _neutralPalette;
      _notifyThemeChanged();
      notifyListeners();
      await _extractCoverColor(current);
    } else {
      notifyListeners();
    }
  }

  String get themeModeLabel => switch (themeMode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };

  void _commitListeningTime() {
    if (_uncommittedListeningTime <= Duration.zero) return;
    stats = stats.add(_uncommittedListeningTime);
    _uncommittedListeningTime = Duration.zero;
  }

  Future<void> _persistPlaybackCheckpoint() {
    _commitListeningTime();
    _checkpointPersistenceRequested = true;
    return _schedulePersistence();
  }

  Future<void> persist() {
    _commitListeningTime();
    _fullPersistenceRequested = true;
    return _schedulePersistence();
  }

  Future<void> _schedulePersistence() {
    final running = _persistenceInFlight;
    if (running != null) return running;
    final future = _drainPersistenceRequests();
    _persistenceInFlight = future;
    return future;
  }

  Future<void> _drainPersistenceRequests() async {
    try {
      while (_fullPersistenceRequested || _checkpointPersistenceRequested) {
        if (_fullPersistenceRequested) {
          _fullPersistenceRequested = false;
          _checkpointPersistenceRequested = false;
          await _writeAllState();
        } else {
          _checkpointPersistenceRequested = false;
          await _writePlaybackCheckpoint();
        }
      }
    } finally {
      _persistenceInFlight = null;
    }
  }

  Future<void> _writePlaybackCheckpoint() async {
    if (hasCurrent) {
      await _prefs?.setInt('currentPositionMs', position.inMilliseconds);
    } else {
      await _prefs?.remove('currentPositionMs');
    }
    await _prefs?.setString('stats', jsonEncode(stats.toJson()));
  }

  Future<void> _writeAllState() async {
    await _prefs?.setString(
      'playlists',
      jsonEncode(playlists.map((item) => item.toJson()).toList()),
    );
    await _prefs?.setString(
      'recent',
      jsonEncode(recent.map((item) => item.toJson()).toList()),
    );
    await _prefs?.setString(
      'playQueue',
      jsonEncode(queue.map((item) => item.toJson()).toList()),
    );
    if (hasCurrent) {
      await _prefs?.setString('currentTrack', jsonEncode(current.toJson()));
      await _prefs?.setInt('currentPositionMs', position.inMilliseconds);
    } else {
      await _prefs?.remove('currentTrack');
      await _prefs?.remove('currentPositionMs');
    }
    await _prefs?.setString('stats', jsonEncode(stats.toJson()));
    await _prefs?.setString(
      'recommendations',
      jsonEncode(recommendations.map((item) => item.toJson()).toList()),
    );
    await _prefs?.setString(
      'recommendedPlaylists',
      jsonEncode(recommendedPlaylists.map((item) => item.toJson()).toList()),
    );
    await _prefs?.setString(
      'cloudPlaylists',
      jsonEncode(cloudPlaylists.map((item) => item.toJson()).toList()),
    );
    await _prefs?.setString(
      'cloudHistory',
      jsonEncode(cloudHistory.map((item) => item.toJson()).toList()),
    );
    await _prefs?.setString('hotSearches', jsonEncode(hotSearches));
    await _prefs?.setString(
      'likedTrackIds',
      jsonEncode(likedTrackIds.toList()),
    );
    await _prefs?.setString('homeCardShapes', jsonEncode(homeCardShapes));
    await _prefs?.setString(
      'accountCache',
      jsonEncode({
        'loggedIn': loggedIn,
        'userId': userId,
        'nickname': nickname,
        'avatarUrl': avatarUrl,
      }),
    );
    await _prefs?.setString('dailyCacheDate', _dailyCacheDate);
    await _persistLyricCache();
  }

  Future<void> _extractCoverColor(Track track) async {
    if (!dynamicColor || track.coverUrl.isEmpty) return;
    try {
      final imageBytes = await ArtworkImage.loadBytes(track.coverUrl, size: 96);
      if (imageBytes == null || current.id != track.id) return;
      final codec = await ui.instantiateImageCodec(
        imageBytes,
        targetWidth: 40,
        targetHeight: 40,
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      codec.dispose();
      if (bytes == null || current.id != track.id) return;
      final bins = <int, _ColorBucket>{};
      final brightnessSamples = <int>[];
      final chromaSamples = <int>[];
      final pixels = bytes.buffer.asUint8List();
      for (var index = 0; index + 3 < pixels.length; index += 16) {
        if (pixels[index + 3] < 32) continue;
        final r = pixels[index];
        final g = pixels[index + 1];
        final b = pixels[index + 2];
        final maxChannel = math.max(r, math.max(g, b));
        final minChannel = math.min(r, math.min(g, b));
        final chroma = maxChannel - minChannel;
        final brightness = (r * 299 + g * 587 + b * 114) ~/ 1000;
        brightnessSamples.add(brightness);
        chromaSamples.add(chroma);
        if (brightness < 22 || brightness > 238 || chroma < 12) {
          continue;
        }
        final key = ((r ~/ 32) << 6) | ((g ~/ 32) << 3) | (b ~/ 32);
        bins.putIfAbsent(key, _ColorBucket.new).add(r, g, b);
      }
      if (brightnessSamples.isEmpty) return;
      brightnessSamples.sort();
      chromaSamples.sort();
      final chroma90 = chromaSamples[((chromaSamples.length - 1) * .9).round()];
      // A black-and-white cover used to discard every useful pixel and leave
      // the blue/purple fallback palette on screen. Use the cover's own tone
      // distribution instead. Covers remain neutral when only a tiny
      // compression fringe is coloured; a truly low-saturation colour
      // cover still goes through the subdued-colour path below.
      if (_isPredominantlyMonochrome(chromaSamples) || bins.isEmpty) {
        if (current.id == track.id) {
          _coverPalette = List.unmodifiable(
            _monochromePalette(brightnessSamples),
          );
          _notifyThemeChanged();
          notifyListeners();
        }
        return;
      }
      final subdued = chroma90 <= 32;
      final candidates = bins.values.where((bucket) => bucket.isUsable).toList()
        ..sort((a, b) => _bucketScore(b).compareTo(_bucketScore(a)));
      final selected = <Color>[];
      for (final bucket in candidates) {
        final color = _polishCoverColor(bucket.color, subdued: subdued);
        final baseHueDistance = selected.isEmpty
            ? 0.0
            : _hueDistance(selected.first, color);
        final accepted = switch (coverColorStyle) {
          CoverColorStyle.analogous =>
            baseHueDistance <= 42 &&
                selected.every(
                  (existing) => _colorDistance(existing, color) > 22,
                ),
          CoverColorStyle.vibrant => selected.every(
            (existing) =>
                _colorDistance(existing, color) > 40 &&
                _hueDistance(existing, color) > 18,
          ),
          CoverColorStyle.bright => selected.every(
            (existing) => _colorDistance(existing, color) > 30,
          ),
          CoverColorStyle.balanced => selected.every(
            (existing) =>
                _colorDistance(existing, color) > 42 &&
                _hueDistance(existing, color) > 20,
          ),
          CoverColorStyle.diverse => selected.every(
            (existing) =>
                _colorDistance(existing, color) > 50 &&
                _hueDistance(existing, color) > 48,
          ),
        };
        if (accepted) {
          selected.add(color);
        }
        if (selected.length == 3) break;
      }
      if (selected.isEmpty) {
        if (current.id == track.id) {
          _coverPalette = List.unmodifiable(
            _monochromePalette(brightnessSamples),
          );
          _notifyThemeChanged();
          notifyListeners();
        }
        return;
      }
      while (selected.length < 3) {
        final hsl = HSLColor.fromColor(selected.first);
        final lightnessOffset = selected.length.isOdd ? .10 : -.10;
        selected.add(
          hsl
              .withLightness((hsl.lightness + lightnessOffset).clamp(.16, .84))
              .toColor(),
        );
      }
      if (current.id == track.id) {
        _coverPalette = List.unmodifiable(selected);
        _notifyThemeChanged();
        notifyListeners();
      }
    } catch (_) {
      // Keep the track's fallback seed if artwork cannot be decoded.
    }
  }

  double _colorDistance(Color left, Color right) {
    final red = left.r - right.r;
    final green = left.g - right.g;
    final blue = left.b - right.b;
    return math.sqrt(red * red + green * green + blue * blue) * 255;
  }

  void _notifyThemeChanged() {
    themeRevision.value = themeRevision.value + 1;
  }

  double _hueDistance(Color left, Color right) {
    final delta = (HSLColor.fromColor(left).hue - HSLColor.fromColor(right).hue)
        .abs();
    return math.min(delta, 360 - delta);
  }

  double _bucketScore(_ColorBucket bucket) {
    final hsl = bucket.hsl;
    final population = math.sqrt(bucket.count);
    return switch (coverColorStyle) {
      CoverColorStyle.analogous =>
        population *
            (1 + hsl.saturation * 1.8) *
            (1 - (hsl.lightness - .56).abs()),
      CoverColorStyle.vibrant =>
        population *
            (1 + hsl.saturation * 4.2) *
            (1 - (hsl.lightness - .54).abs()),
      CoverColorStyle.bright =>
        population *
            (1 + hsl.saturation * 1.5) *
            (1 - (hsl.lightness - .72).abs()),
      CoverColorStyle.balanced => bucket.score,
      CoverColorStyle.diverse =>
        population *
            (1 + hsl.saturation * 3.1) *
            (1 - (hsl.lightness - .58).abs()),
    };
  }

  List<Color> _monochromePalette(List<int> brightnessSamples) {
    int percentile(double value) =>
        brightnessSamples[((brightnessSamples.length - 1) * value).round()];

    Color gray(double value) {
      final channel = (value.clamp(0.0, 1.0) * 255).round();
      return Color.fromARGB(255, channel, channel, channel);
    }

    var low = (percentile(.20) / 255).clamp(.12, .78).toDouble();
    final middle = (percentile(.50) / 255).clamp(.18, .82).toDouble();
    var high = (percentile(.80) / 255).clamp(.24, .88).toDouble();
    if (high - low < .10) {
      low = (middle - .10).clamp(.10, .72).toDouble();
      high = (middle + .10).clamp(.28, .90).toDouble();
    }
    return [gray(middle), gray(low), gray(high)];
  }

  Color _polishCoverColor(Color source, {bool subdued = false}) {
    final hsl = HSLColor.fromColor(source);
    final saturation = subdued
        ? (hsl.saturation * 1.05).clamp(.04, .30)
        : switch (coverColorStyle) {
            CoverColorStyle.analogous => hsl.saturation.clamp(.34, 1.0),
            CoverColorStyle.vibrant => hsl.saturation.clamp(.72, 1.0),
            CoverColorStyle.bright => hsl.saturation.clamp(.42, 1.0),
            CoverColorStyle.balanced => hsl.saturation.clamp(.44, 1.0),
            CoverColorStyle.diverse => hsl.saturation.clamp(.58, 1.0),
          };
    final lightness = switch (coverColorStyle) {
      CoverColorStyle.analogous => hsl.lightness.clamp(.48, .62),
      CoverColorStyle.vibrant => hsl.lightness.clamp(.50, .60),
      CoverColorStyle.bright => hsl.lightness.clamp(.68, .78),
      CoverColorStyle.balanced => hsl.lightness.clamp(.48, .64),
      CoverColorStyle.diverse => hsl.lightness.clamp(.50, .64),
    };
    return hsl.withSaturation(saturation).withLightness(lightness).toColor();
  }

  @override
  void dispose() {
    persist();
    _saveTimer?.cancel();
    _messageTimer?.cancel();
    _positionSub?.cancel();
    _playerSub?.cancel();
    _durationSub?.cancel();
    playbackTimeline.dispose();
    themeRevision.dispose();
    player.dispose();
    super.dispose();
  }
}

class _ColorBucket {
  int count = 0;
  int redTotal = 0;
  int greenTotal = 0;
  int blueTotal = 0;

  void add(int red, int green, int blue) {
    count++;
    redTotal += red;
    greenTotal += green;
    blueTotal += blue;
  }

  int get red => redTotal ~/ count;
  int get green => greenTotal ~/ count;
  int get blue => blueTotal ~/ count;
  Color get color => Color.fromARGB(255, red, green, blue);
  HSLColor get hsl => HSLColor.fromColor(color);
  bool get isUsable =>
      hsl.saturation >= .18 && hsl.lightness >= .2 && hsl.lightness <= .86;
  double get score {
    final idealLightness = 1 - (hsl.lightness - .56).abs().clamp(0, .7);
    return math.sqrt(count) * (1 + hsl.saturation * 2.8) * idealLightness;
  }
}

class MelodyScope extends InheritedNotifier<MelodyState> {
  const MelodyScope({
    super.key,
    required MelodyState state,
    required super.child,
  }) : super(notifier: state);

  static MelodyState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MelodyScope>()!.notifier!;

  static MelodyState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MelodyScope>()!.notifier!;
}
