import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import 'models.dart';

class LyricsParser {
  static final _lineTag = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _wordTag = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
  static final _creditLine = RegExp(
    r'^\s*(?:[【\[(]\s*)?(?:(?:作\s*[词詞]|作\s*曲|填\s*[词詞]|谱曲|譜曲|[词詞]|曲|[词詞]\s*(?:&|＆|、|/|／)\s*曲|[词詞]曲|编曲|編曲|lyric(?:s|ist)?|composer|songwriter|composition|arrang(?:er|ement))\s*(?:[：:|｜/／]|-{1,2}|—|\s{2,})\s*\S|(?:lyrics?|words|music|written|composed)\s+by\s+\S)',
    caseSensitive: false,
  );
  static final _instrumentalPlaceholder = RegExp(
    r'^\s*(?:纯音乐(?:，|,|　|\s)*(?:请)?欣赏|此歌曲为纯音乐|该歌曲为纯音乐|instrumental(?:\s+(?:music|track))?)\s*[.!。！]*\s*$',
    caseSensitive: false,
  );

  static Duration _time(RegExpMatch match) {
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final fraction = match.group(3) ?? '0';
    final millis = fraction.length == 3
        ? int.parse(fraction)
        : fraction.length == 2
        ? int.parse(fraction) * 10
        : int.parse(fraction) * 100;
    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  static List<LyricLine> parse(String source, {String? translation}) {
    final raw = <({Duration start, String text, List<LyricWord> words})>[];
    for (final input in const LineSplitter().convert(source)) {
      final lineMatch = _lineTag.firstMatch(input);
      if (lineMatch == null) continue;
      final start = _time(lineMatch);
      final content = input.substring(lineMatch.end).trim();
      if (content.isEmpty || content.startsWith('offset:')) continue;
      final matches = _wordTag.allMatches(content).toList();
      final words = <LyricWord>[];
      if (matches.isNotEmpty) {
        for (var i = 0; i < matches.length; i++) {
          final begin = matches[i].end;
          final finish = i + 1 < matches.length
              ? matches[i + 1].start
              : content.length;
          final text = content.substring(begin, finish);
          if (text.isEmpty) continue;
          final wordStart = _time(matches[i]);
          final wordEnd = i + 1 < matches.length
              ? _time(matches[i + 1])
              : wordStart + const Duration(milliseconds: 700);
          words.add(LyricWord(text, wordStart, wordEnd));
        }
      }
      raw.add((
        start: start,
        text: content.replaceAll(_wordTag, ''),
        words: words,
      ));
    }

    raw.sort((a, b) => a.start.compareTo(b.start));
    final translations = translation == null
        ? <Duration, String>{}
        : _plainMap(translation);
    final merged = <({Duration start, String text, List<LyricWord> words})>[];
    for (final item in raw) {
      if (merged.isNotEmpty &&
          merged.last.start == item.start &&
          item.words.isEmpty) {
        translations[item.start] = item.text;
      } else {
        merged.add(item);
      }
    }
    return List.generate(merged.length, (index) {
      final item = merged[index];
      final end = index + 1 < merged.length
          ? merged[index + 1].start
          : item.start + const Duration(seconds: 6);
      return LyricLine(
        start: item.start,
        end: end,
        text: item.text,
        translation: translations[item.start],
        words: item.words,
      );
    });
  }

  static Map<Duration, String> _plainMap(String source) {
    final result = <Duration, String>{};
    for (final input in const LineSplitter().convert(source)) {
      final match = _lineTag.firstMatch(input);
      if (match != null) {
        result[_time(match)] = input.substring(match.end).trim();
      }
    }
    return result;
  }

  static List<LyricLine> parseYrc(String source, {String? translation}) {
    // NetEase YRC: [lineStart,lineDuration](wordStart,wordDuration,0)word
    final linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
    final wordPattern = RegExp(r'\((\d+),(\d+),\d+\)([^()]*)');
    final result = <LyricLine>[];
    final translations = translation == null
        ? <Duration, String>{}
        : _plainMap(translation);
    for (final input in const LineSplitter().convert(source)) {
      final line = linePattern.firstMatch(input);
      if (line == null) continue;
      final start = Duration(milliseconds: int.parse(line.group(1)!));
      final end = start + Duration(milliseconds: int.parse(line.group(2)!));
      final words = wordPattern.allMatches(line.group(3)!).map((match) {
        final wordStart = Duration(milliseconds: int.parse(match.group(1)!));
        return LyricWord(
          match.group(3)!,
          wordStart,
          wordStart + Duration(milliseconds: int.parse(match.group(2)!)),
        );
      }).toList();
      result.add(
        LyricLine(
          start: start,
          end: end,
          text: words.map((e) => e.text).join(),
          words: words,
          translation: translations[start],
        ),
      );
    }
    return result;
  }

  /// QQ QRC uses absolute millisecond word timestamps after each word.
  static List<LyricLine> parseQrc(String source, {String? translation}) {
    String content(String value) {
      if (!value.contains('<Lyric_1')) return value;
      final document = XmlDocument.parse(value);
      for (final lyric in document.findAllElements('Lyric_1')) {
        final text = lyric.getAttribute('LyricContent');
        if (text != null && text.isNotEmpty) return text;
      }
      return '';
    }

    final linePattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
    final wordPattern = RegExp(r'((?:(?!\(\d+,\d+\)).)*)\((\d+),(\d+)\)');
    final translations = translation == null
        ? <Duration, String>{}
        : _plainMap(content(translation));
    String? cleanTranslation(String? value) {
      final text = value?.trim();
      if (text == null ||
          text.isEmpty ||
          text == '//' ||
          text.contains('享有本翻译作品的著作权')) {
        return null;
      }
      return text;
    }

    String? translationAt(Duration start) {
      final exact = translations[start];
      if (exact != null) return cleanTranslation(exact);
      String? closest;
      var smallestGap = 121;
      for (final entry in translations.entries) {
        final gap = (entry.key.inMilliseconds - start.inMilliseconds).abs();
        if (gap < smallestGap) {
          smallestGap = gap;
          closest = entry.value;
        }
      }
      return cleanTranslation(closest);
    }

    final result = <LyricLine>[];
    for (final input in const LineSplitter().convert(content(source))) {
      final match = linePattern.firstMatch(input.trim());
      if (match == null) continue;
      final startMs = int.parse(match.group(1)!);
      final durationMs = int.parse(match.group(2)!);
      final body = match.group(3)!;
      final words = <LyricWord>[];
      var lastEnd = 0;
      for (final word in wordPattern.allMatches(body)) {
        final text = word.group(1)!;
        final wordStart = int.parse(word.group(2)!);
        final wordEnd = wordStart + int.parse(word.group(3)!);
        if (text.isNotEmpty && wordEnd > wordStart) {
          words.add(
            LyricWord(
              text,
              Duration(milliseconds: wordStart),
              Duration(milliseconds: wordEnd),
            ),
          );
        }
        lastEnd = word.end;
      }
      final trailing = body.substring(lastEnd);
      if (words.isNotEmpty && trailing.isNotEmpty) {
        final last = words.removeLast();
        words.add(LyricWord(last.text + trailing, last.start, last.end));
      }
      final text = words.isEmpty
          ? body.trim()
          : words.map((w) => w.text).join();
      if (text.isEmpty) continue;
      final start = Duration(milliseconds: startMs);
      result.add(
        LyricLine(
          start: start,
          end: Duration(milliseconds: startMs + durationMs),
          text: text,
          words: words,
          translation: translationAt(start),
        ),
      );
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static List<LyricLine> parseTtml(String source) {
    final document = XmlDocument.parse(source);
    final lines = <LyricLine>[];
    final appleTranslations = _appleAuxiliaryText(document, 'translations');
    final paragraphs = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'p')
        .toList();
    final agentSides = <String, bool>{};
    for (final paragraph in paragraphs) {
      final start = _ttmlTime(_xmlAttribute(paragraph, 'begin'));
      final end = _ttmlTime(_xmlAttribute(paragraph, 'end'));
      if (start == null || end == null || end <= start) continue;
      final words = <LyricWord>[];
      final backgroundWords = <LyricWord>[];
      String? backgroundText;
      String? backgroundTranslation;
      String? translation;
      final translations = paragraph.descendants.whereType<XmlElement>().where(
        (element) => _role(element) == 'x-translation',
      );
      if (translations.isNotEmpty) {
        translation = translations.first.innerText.trim();
      }
      final backgrounds = paragraph.descendants.whereType<XmlElement>().where(
        (element) => _role(element) == 'x-bg',
      );
      for (final background in backgrounds) {
        // Only parse the outermost background container. Nested x-bg nodes are
        // part of the same harmony track and would otherwise be duplicated.
        if (_hasAncestorRole(background, 'x-bg', stopAt: paragraph)) continue;
        backgroundWords.addAll(
          _timedLeafWords(
            background,
            ignoredRoles: const {'x-translation', 'x-roman'},
            includeRoot: false,
          ),
        );
        if (backgroundWords.isEmpty) {
          final bgStart = _ttmlTime(_xmlAttribute(background, 'begin'));
          final bgEnd = _ttmlTime(_xmlAttribute(background, 'end'));
          final content = _visibleText(
            background,
            ignoredRoles: const {'x-translation', 'x-roman'},
          ).trim();
          if (content.isNotEmpty &&
              bgStart != null &&
              bgEnd != null &&
              bgEnd > bgStart) {
            backgroundWords.add(LyricWord(content, bgStart, bgEnd));
          }
        }
        backgroundText = backgroundWords.map((word) => word.text).join();
        if (backgroundText.isEmpty) {
          backgroundText = _visibleText(
            background,
            ignoredRoles: const {'x-translation', 'x-roman'},
          ).trim();
        }
        final bgTranslations = background.descendants
            .whereType<XmlElement>()
            .where((element) => _role(element) == 'x-translation');
        if (bgTranslations.isNotEmpty) {
          backgroundTranslation = bgTranslations.first.innerText.trim();
        }
      }
      words.addAll(
        _timedLeafWords(
          paragraph,
          ignoredRoles: const {'x-translation', 'x-roman', 'x-bg'},
          includeRoot: false,
        ),
      );
      final lineText = _visibleText(
        paragraph,
        ignoredRoles: const {'x-translation', 'x-roman', 'x-bg'},
      ).trim();
      if (lineText.isEmpty) continue;
      final displayWords = _restoreTtmlSpacing(words, lineText);
      final lineKey = _xmlAttribute(paragraph, 'key');
      translation ??= lineKey == null ? null : appleTranslations[lineKey];
      final agent = _normalizeAgent(_xmlAttribute(paragraph, 'agent'));
      if (agent != null && agent.isNotEmpty) {
        agentSides.putIfAbsent(agent, () => agentSides.length.isOdd);
      }
      lines.add(
        LyricLine(
          start: start,
          end: end,
          text: lineText,
          words: displayWords,
          translation: translation,
          agent: agent,
          alignRight: agent == null ? false : agentSides[agent] ?? false,
          backgroundText: backgroundText,
          backgroundWords: backgroundWords,
          backgroundTranslation: backgroundTranslation,
        ),
      );
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
    return lines;
  }

  /// Removes only standalone credit metadata with an explicit label and
  /// separator. Natural lyric sentences containing words such as “作词” or
  /// “作曲” are retained. Timings and word data of every retained line remain
  /// untouched.
  static List<LyricLine> withoutCredits(List<LyricLine> source) {
    final result = <LyricLine>[];
    for (final line in source) {
      if (_creditLine.hasMatch(line.text) ||
          _instrumentalPlaceholder.hasMatch(line.text)) {
        continue;
      }
      final translation = line.translation;
      final backgroundText = line.backgroundText;
      final cleanTranslation =
          translation != null && _creditLine.hasMatch(translation)
          ? null
          : translation;
      final cleanBackground =
          backgroundText != null && _creditLine.hasMatch(backgroundText)
          ? null
          : backgroundText;
      if (cleanTranslation == translation &&
          cleanBackground == backgroundText) {
        result.add(line);
        continue;
      }
      result.add(
        LyricLine(
          start: line.start,
          end: line.end,
          text: line.text,
          translation: cleanTranslation,
          words: line.words,
          isInterlude: line.isInterlude,
          agent: line.agent,
          alignRight: line.alignRight,
          backgroundText: cleanBackground,
          backgroundWords: cleanBackground == null
              ? const []
              : line.backgroundWords,
          backgroundTranslation: cleanBackground == null
              ? null
              : line.backgroundTranslation,
        ),
      );
    }
    return result;
  }

  static bool containsInstrumentalPlaceholder(Iterable<LyricLine> source) =>
      source.any((line) => _instrumentalPlaceholder.hasMatch(line.text));

  /// Adds a timeline item for a genuine instrumental break. Explicit word
  /// timings are preferred; plain LRC lines use a conservative reading-time
  /// estimate because their nominal end is usually the next line's start.
  static List<LyricLine> withInterludes(
    List<LyricLine> source, {
    Duration minimumGap = const Duration(seconds: 5),
  }) {
    if (source.isEmpty) return source;
    final lines = [...source]..sort((a, b) => a.start.compareTo(b.start));
    final result = <LyricLine>[];

    void addBreak(Duration start, Duration end) {
      if (end - start < minimumGap) return;
      result.add(
        LyricLine(start: start, end: end, text: '', isInterlude: true),
      );
    }

    addBreak(Duration.zero, lines.first.start);
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      result.add(line);
      if (index + 1 >= lines.length) continue;
      final next = lines[index + 1];
      var vocalEnd = line.end;
      if (line.words.isNotEmpty) {
        vocalEnd = line.words
            .map((word) => word.end)
            .fold(line.start, (latest, end) => end > latest ? end : latest);
      } else if (line.end >= next.start) {
        final estimatedMs = (1800 + line.text.runes.length * 115).clamp(
          2400,
          4400,
        );
        vocalEnd = line.start + Duration(milliseconds: estimatedMs);
      }
      if (vocalEnd > next.start) vocalEnd = next.start;
      addBreak(vocalEnd, next.start);
    }
    return result;
  }

  static String? _xmlAttribute(XmlElement element, String name) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == name) return attribute.value;
    }
    return null;
  }

  static String? _role(XmlElement element) {
    final value = _xmlAttribute(element, 'role')?.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }

  static bool _hasAncestorRole(
    XmlElement element,
    String role, {
    required XmlElement stopAt,
  }) {
    XmlNode? current = element.parent;
    while (current is XmlElement && current != stopAt) {
      if (_role(current) == role) return true;
      current = current.parent;
    }
    return false;
  }

  static String _visibleText(
    XmlElement root, {
    required Set<String> ignoredRoles,
  }) {
    final output = StringBuffer();
    void visit(XmlNode node) {
      if (node is XmlText) {
        if (!node.value.contains('\n') && !node.value.contains('\r')) {
          output.write(node.value);
        }
        return;
      }
      if (node is! XmlElement || ignoredRoles.contains(_role(node))) return;
      for (final child in node.children) {
        visit(child);
      }
    }

    for (final child in root.children) {
      visit(child);
    }
    return output.toString();
  }

  static List<LyricWord> _timedLeafWords(
    XmlElement root, {
    required Set<String> ignoredRoles,
    required bool includeRoot,
  }) {
    List<LyricWord> visit(XmlElement element, bool mayUseElement) {
      if (ignoredRoles.contains(_role(element))) return const [];
      final childWords = <LyricWord>[];
      for (final child in element.childElements) {
        childWords.addAll(visit(child, true));
      }
      // Prefer the deepest timed spans. This preserves syllable timings when
      // legacy AMLL files wrap a whole phrase in another span.
      if (childWords.isNotEmpty) return childWords;
      if (!mayUseElement || element.name.local != 'span') return const [];
      final start = _ttmlTime(_xmlAttribute(element, 'begin'));
      final end = _ttmlTime(_xmlAttribute(element, 'end'));
      final content = _visibleText(element, ignoredRoles: ignoredRoles);
      if (content.isEmpty || start == null || end == null || end <= start) {
        return const [];
      }
      return [LyricWord(content, start, end)];
    }

    return visit(root, includeRoot);
  }

  /// Timed TTML spans are often emitted as separate XML elements while the
  /// separating space lives in a plain text node between them. The timed-word
  /// traversal intentionally ignores those untimed nodes, so restore only the
  /// separators that are present in the complete visible line. This avoids
  /// turning English into `Helloworld` without inserting spaces into CJK text
  /// or into a word that was deliberately split into timed syllables.
  static List<LyricWord> _restoreTtmlSpacing(
    List<LyricWord> words,
    String lineText,
  ) {
    if (words.length < 2 || !RegExp(r'\s').hasMatch(lineText)) return words;
    var cursor = 0;
    final restored = <LyricWord>[];
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      var text = word.text;
      final needle = text.trim();
      if (needle.isEmpty) {
        restored.add(word);
        continue;
      }
      final found = lineText.indexOf(needle, cursor);
      if (found < 0) {
        restored.add(word);
        continue;
      }
      cursor = found + needle.length;
      if (index + 1 < words.length &&
          !RegExp(r'\s$').hasMatch(text) &&
          !RegExp(r'^\s').hasMatch(words[index + 1].text)) {
        final nextNeedle = words[index + 1].text.trim();
        final nextAt = nextNeedle.isEmpty
            ? -1
            : lineText.indexOf(nextNeedle, cursor);
        if (nextAt >= cursor &&
            RegExp(r'\s').hasMatch(lineText.substring(cursor, nextAt))) {
          text = '$text ';
        }
      }
      restored.add(LyricWord(text, word.start, word.end));
    }
    return restored;
  }

  static String? _normalizeAgent(String? raw) {
    if (raw == null) return null;
    var value = raw.trim();
    final url = RegExp(r'^url\(\s*#([^\)]+)\s*\)$').firstMatch(value);
    if (url != null) value = url.group(1)!;
    if (value.startsWith('#')) value = value.substring(1);
    return value.isEmpty ? null : value;
  }

  static Map<String, String> _appleAuxiliaryText(
    XmlDocument document,
    String containerName,
  ) {
    final containers = document.descendants.whereType<XmlElement>().where(
      (element) => element.name.local.toLowerCase() == containerName,
    );
    if (containers.isEmpty) return const {};
    // AMLL currently exposes one selected translation track. Follow document
    // order so the result is deterministic when several languages exist.
    final tracks = containers.first.childElements.where(
      (element) => element.name.local.toLowerCase() == 'translation',
    );
    if (tracks.isEmpty) return const {};
    final result = <String, String>{};
    for (final text in tracks.first.descendants.whereType<XmlElement>().where(
      (element) => element.name.local.toLowerCase() == 'text',
    )) {
      final key = _xmlAttribute(text, 'for');
      final value = _visibleText(text, ignoredRoles: const {'x-roman'}).trim();
      if (key != null && key.isNotEmpty && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  static Duration? _ttmlTime(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final value = raw.trim();
    if (value.endsWith('ms')) {
      return Duration(
        milliseconds: double.parse(
          value.substring(0, value.length - 2),
        ).round(),
      );
    }
    if (value.endsWith('s')) {
      return Duration(
        milliseconds:
            (double.parse(value.substring(0, value.length - 1)) * 1000).round(),
      );
    }
    // AMLL also permits seconds-only clock values without a suffix, including
    // values over 60 seconds (for example 45.404, 95 or 95.000).
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) {
      return Duration(
        microseconds: (double.parse(value) * Duration.microsecondsPerSecond)
            .round(),
      );
    }
    // Real AMLL files commonly omit the leading zero in MM:SS (for example
    // 1:02.927). Parse colon-separated fields explicitly so both M:SS and
    // HH:MM:SS remain valid without confusing minutes with hours.
    final parts = value.split(':');
    if (parts.length != 2 && parts.length != 3) return null;
    final secondsMatch = RegExp(
      r'^(\d{1,2})(?:\.(\d+))?$',
    ).firstMatch(parts.last);
    if (secondsMatch == null) return null;
    final seconds = int.parse(secondsMatch.group(1)!);
    if (seconds >= 60) return null;
    var hours = 0;
    late final int minutes;
    if (parts.length == 2) {
      minutes = int.tryParse(parts[0]) ?? -1;
    } else {
      hours = int.tryParse(parts[0]) ?? -1;
      minutes = int.tryParse(parts[1]) ?? -1;
      if (minutes >= 60) return null;
    }
    if (hours < 0 || minutes < 0) return null;
    final fraction = secondsMatch.group(2) ?? '';
    final milliseconds = fraction.isEmpty
        ? 0
        : int.parse('${fraction}000'.substring(0, 3));
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  static int activeLine(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var low = 0;
    var high = lines.length - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid].start <= position) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return high.clamp(0, lines.length - 1);
  }

  static double wordProgress(LyricWord word, Duration position) {
    final span = word.end.inMilliseconds - word.start.inMilliseconds;
    if (span <= 0) return position >= word.start ? 1 : 0;
    return clampDouble(
      (position.inMilliseconds - word.start.inMilliseconds) / span,
      0,
      1,
    );
  }
}
