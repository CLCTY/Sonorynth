import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public interface has no legacy display name in any letter case', () {
    final ui = File('lib/ui.dart').readAsStringSync();
    expect(ui, contains("subtitle: 'SONORYNTH'"));
    for (final file in Directory('lib').listSync().whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      expect(
        RegExp(r'melody[ _-]*flow', caseSensitive: false)
            .hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });
  test('public copy excludes restricted source adapters', () {
    expect(File('lib/unlock_source.dart').existsSync(), isFalse);
    final code = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final token in [
      'UnlockSourceAdapter',
      'searchUnlockSources',
      'MusicSearchSource.kuwo',
      'music-api.gdstudio.xyz',
      'antiserver.kuwo.cn',
      'bd-api.kuwo.cn',
    ]) {
      expect(code, isNot(contains(token)), reason: token);
    }
    expect(code, contains("item['freeTrialInfo'] != null"));
  });
}
