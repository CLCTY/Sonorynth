import 'package:flutter_test/flutter_test.dart';
import 'package:melody_flow/models.dart';
import 'package:melody_flow/netease_api.dart';

class _FixedSource implements AuthorizedSourceAdapter {
  const _FixedSource(this.uri);

  final Uri uri;

  @override
  Future<Uri?> resolve(Track track, AudioQuality quality) async => uri;
}

void main() {
  test('rejected preview source falls through to the next adapter', () async {
    final preview = Uri.parse('https://example.test/preview.mp3');
    final complete = Uri.parse('https://example.test/complete.mp3');
    final resolver = SourceResolver([
      _FixedSource(preview),
      _FixedSource(complete),
    ]);
    const track = Track(
      id: '1',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      coverUrl: '',
    );

    expect(await resolver.resolve(track, AudioQuality.exhigh), preview);
    resolver.reject(track, AudioQuality.exhigh, preview);
    expect(await resolver.resolve(track, AudioQuality.exhigh), complete);
  });
}
