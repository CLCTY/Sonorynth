enum AudioQuality {
  standard('标准', 'standard', 128),
  higher('较高', 'higher', 192),
  exhigh('极高', 'exhigh', 320),
  lossless('无损', 'lossless', 999),
  hires('Hi-Res', 'hires', 1999);

  const AudioQuality(this.label, this.apiValue, this.kbps);
  final String label;
  final String apiValue;
  final int kbps;
}

const neteaseArtworkHeaders = <String, String>{
  'Referer': 'https://music.163.com/',
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36',
};

String neteaseArtworkUrl(String raw, {int size = 600}) {
  var value = raw.trim();
  if (value.isEmpty || value == 'null') return '';
  if (value.startsWith('//')) value = 'https:$value';
  if (value.startsWith('http://')) {
    value = 'https://${value.substring('http://'.length)}';
  }
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme) return value;
  return uri
      .replace(
        queryParameters: {...uri.queryParameters, 'param': '${size}y$size'},
      )
      .toString();
}

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.coverUrl,
    this.audioUrl,
    this.duration = const Duration(minutes: 3, seconds: 30),
    this.seedColor = 0xff315c4d,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String coverUrl;
  final String? audioUrl;
  final Duration duration;
  final int seedColor;

  String get sourceLabel => '网易云音乐';

  factory Track.fromNetease(Map<String, dynamic> json) {
    final nested = json['song'] is Map<String, dynamic>
        ? json['song'] as Map<String, dynamic>
        : json;
    final artists = (nested['ar'] ?? nested['artists'] ?? []) as List<dynamic>;
    final albumValue = nested['al'] ?? nested['album'] ?? const {};
    final album = albumValue is Map<String, dynamic>
        ? albumValue
        : const <String, dynamic>{};
    String firstText(Iterable<dynamic> values) {
      for (final value in values) {
        final text = value?.toString().trim() ?? '';
        if (text.isNotEmpty && text != 'null') return text;
      }
      return '';
    }

    final durationValue = nested['dt'] ?? nested['duration'] ?? 0;
    return Track(
      id: firstText([nested['id']]),
      title: firstText([nested['name'], '未知歌曲']),
      artist: artists
          .map((e) => e is Map<String, dynamic> ? e['name'] : null)
          .where((name) => name != null && '$name'.isNotEmpty)
          .join(' / '),
      album: firstText([album['name']]),
      coverUrl: neteaseArtworkUrl(
        firstText([
          album['picUrl'],
          album['blurPicUrl'],
          nested['picUrl'],
          nested['coverUrl'],
        ]),
      ),
      duration: Duration(
        milliseconds: durationValue is num
            ? durationValue.round()
            : int.tryParse('$durationValue') ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'coverUrl': coverUrl,
    'audioUrl': audioUrl,
    'duration': duration.inMilliseconds,
    'seedColor': seedColor,
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: '${json['id']}',
    title: '${json['title']}',
    artist: '${json['artist']}',
    album: '${json['album']}',
    coverUrl: neteaseArtworkUrl('${json['coverUrl']}'),
    audioUrl: json['audioUrl'] as String?,
    duration: Duration(milliseconds: json['duration'] as int? ?? 0),
    seedColor: json['seedColor'] as int? ?? 0xff315c4d,
  );
}

class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    required this.coverUrl,
    required this.tracks,
    this.description = '',
    this.trackCount = 0,
  });
  final String id;
  final String name;
  final String coverUrl;
  final List<Track> tracks;
  final String description;
  final int trackCount;

  int get displayTrackCount => tracks.isEmpty ? trackCount : tracks.length;
  bool get hasCompleteTrackDetail =>
      tracks.isNotEmpty && (trackCount <= 0 || tracks.length == trackCount);

  factory MusicPlaylist.fromNetease(
    Map<String, dynamic> json, {
    List<Track> tracks = const [],
  }) => MusicPlaylist(
    id: '${json['id']}',
    name: '${json['name'] ?? '未命名歌单'}',
    coverUrl: neteaseArtworkUrl(
      '${json['coverImgUrl'] ?? json['picUrl'] ?? ''}',
    ),
    tracks: tracks,
    description: '${json['description'] ?? json['copywriter'] ?? ''}',
    trackCount: (json['trackCount'] as num?)?.toInt() ?? tracks.length,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'coverUrl': coverUrl,
    'description': description,
    'tracks': tracks.map((e) => e.toJson()).toList(),
    'trackCount': displayTrackCount,
  };

  factory MusicPlaylist.fromJson(Map<String, dynamic> json) => MusicPlaylist(
    id: '${json['id']}',
    name: '${json['name']}',
    coverUrl: neteaseArtworkUrl('${json['coverUrl'] ?? ''}'),
    description: '${json['description'] ?? ''}',
    tracks: ((json['tracks'] ?? []) as List<dynamic>)
        .map((e) => Track.fromJson(e as Map<String, dynamic>))
        .toList(),
    trackCount: (json['trackCount'] as num?)?.toInt() ?? 0,
  );
}

class LyricWord {
  const LyricWord(this.text, this.start, this.end);
  final String text;
  final Duration start;
  final Duration end;
}

class LyricLine {
  const LyricLine({
    required this.start,
    required this.end,
    required this.text,
    this.translation,
    this.words = const [],
    this.isInterlude = false,
    this.agent,
    this.alignRight = false,
    this.backgroundText,
    this.backgroundWords = const [],
    this.backgroundTranslation,
  });
  final Duration start;
  final Duration end;
  final String text;
  final String? translation;
  final List<LyricWord> words;
  final bool isInterlude;
  final String? agent;
  final bool alignRight;
  final String? backgroundText;
  final List<LyricWord> backgroundWords;
  final String? backgroundTranslation;
}

class ListeningStats {
  const ListeningStats({this.days = const {}, this.totalPlays = 0});
  final Map<String, ListeningDay> days;
  final int totalPlays;

  static String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  ListeningDay _day(DateTime date) =>
      days[dateKey(date)] ?? const ListeningDay();

  int get todaySeconds => _day(DateTime.now()).seconds;
  int get todayPlays => _day(DateTime.now()).plays;
  int get weekSeconds => currentWeek.fold(0, (sum, day) => sum + day.seconds);
  int get weekPlays => currentWeek.fold(0, (sum, day) => sum + day.plays);
  int get streakDays {
    var cursor = DateTime.now();
    if (_day(cursor).seconds == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (_day(cursor).seconds > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  List<ListeningDaySummary> get currentWeek {
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - 1));
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return List.generate(7, (index) {
      final date = start.add(Duration(days: index));
      final value = _day(date);
      return ListeningDaySummary(
        label: labels[index],
        seconds: value.seconds,
        plays: value.plays,
        isToday: dateKey(date) == dateKey(today),
      );
    });
  }

  String get todayLabel => '${todaySeconds ~/ 60} 分钟';
  String get weekLabel =>
      '${weekSeconds ~/ 3600} 小时 ${(weekSeconds % 3600) ~/ 60} 分';

  ListeningStats add(Duration delta, {bool newPlay = false, DateTime? now}) {
    final date = now ?? DateTime.now();
    final key = dateKey(date);
    final current = days[key] ?? const ListeningDay();
    final updated = Map<String, ListeningDay>.from(days);
    updated[key] = ListeningDay(
      milliseconds: current.milliseconds + delta.inMilliseconds,
      plays: current.plays + (newPlay ? 1 : 0),
    );
    final cutoff = date.subtract(const Duration(days: 400));
    updated.removeWhere((key, _) {
      final parsed = DateTime.tryParse(key);
      return parsed != null && parsed.isBefore(cutoff);
    });
    return ListeningStats(
      days: updated,
      totalPlays: totalPlays + (newPlay ? 1 : 0),
    );
  }

  Map<String, dynamic> toJson() => {
    'days': days.map((key, value) => MapEntry(key, value.toJson())),
    'totalPlays': totalPlays,
  };

  factory ListeningStats.fromJson(Map<String, dynamic> json) {
    final rawDays = json['days'];
    if (rawDays is Map<String, dynamic>) {
      return ListeningStats(
        days: rawDays.map(
          (key, value) => MapEntry(
            key,
            ListeningDay.fromJson(value as Map<String, dynamic>),
          ),
        ),
        totalPlays: (json['totalPlays'] as num?)?.toInt() ?? 0,
      );
    }
    final legacyToday = (json['todaySeconds'] as num?)?.toInt() ?? 0;
    return ListeningStats(
      days: legacyToday > 0
          ? {dateKey(DateTime.now()): ListeningDay(seconds: legacyToday)}
          : const {},
      totalPlays: (json['totalPlays'] as num?)?.toInt() ?? 0,
    );
  }
}

class ListeningDay {
  const ListeningDay({int seconds = 0, int? milliseconds, this.plays = 0})
    : milliseconds = milliseconds ?? seconds * 1000;
  final int milliseconds;
  final int plays;
  int get seconds => milliseconds ~/ 1000;

  Map<String, dynamic> toJson() => {
    'milliseconds': milliseconds,
    'plays': plays,
  };

  factory ListeningDay.fromJson(Map<String, dynamic> json) => ListeningDay(
    milliseconds:
        (json['milliseconds'] as num?)?.toInt() ??
        ((json['seconds'] as num?)?.toInt() ?? 0) * 1000,
    plays: (json['plays'] as num?)?.toInt() ?? 0,
  );
}

class ListeningDaySummary {
  const ListeningDaySummary({
    required this.label,
    required this.seconds,
    required this.plays,
    required this.isToday,
  });
  final String label;
  final int seconds;
  final int plays;
  final bool isToday;
}
