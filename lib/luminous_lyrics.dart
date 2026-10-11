import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'lyric_gyroscope.dart';
import 'lyrics_parser.dart';
import 'models.dart';

/// Original Flutter renderer inspired by Folia's Luminous word choreography.
/// Text is measured with its largest animated bounds before any motion is applied.
class LuminousLyrics extends StatefulWidget {
  const LuminousLyrics({
    super.key,
    required this.lines,
    required this.position,
    required this.playing,
    required this.ink,
    required this.accent,
    this.showTranslation = true,
    this.karaoke = true,
    this.gyroscope = true,
    this.onSeek,
  });
  final List<LyricLine> lines;
  final ValueListenable<Duration> position;
  final bool playing, showTranslation, karaoke, gyroscope;
  final Color ink, accent;
  final ValueChanged<Duration>? onSeek;

  @override
  State<LuminousLyrics> createState() => _LuminousLyricsState();
}

class _LuminousLyricsState extends State<LuminousLyrics>
    with WidgetsBindingObserver {
  final gyro = LyricGyroscope();
  bool foreground = true;
  bool motionAllowed = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    motionAllowed =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        !MediaQuery.disableAnimationsOf(context);
    syncSensor();
  }

  @override
  void didUpdateWidget(covariant LuminousLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncSensor();
  }

  void syncSensor() => gyro.setEnabled(
    foreground && motionAllowed && widget.playing && widget.gyroscope,
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    syncSensor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    gyro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Duration>(
    valueListenable: widget.position,
    builder: (context, position, _) {
      final index = LyricsParser.activeLine(widget.lines, position);
      final line = index >= 0 ? widget.lines[index] : null;
      final nextIndex = index + 1;
      final next = nextIndex < widget.lines.length
          ? widget.lines[nextIndex]
          : null;
      return LayoutBuilder(
        builder: (context, constraints) {
          final short = constraints.maxHeight < 260;
          return ClipRect(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: Semantics(
                      label: line?.isInterlude == true
                          ? '间奏'
                          : line?.text ?? '等待演唱',
                      child: ValueListenableBuilder<Offset>(
                        valueListenable: gyro,
                        builder: (context, tilt, _) => AnimatedSwitcher(
                          duration: motionAllowed
                              ? const Duration(milliseconds: 260)
                              : Duration.zero,
                          reverseDuration: motionAllowed
                              ? const Duration(milliseconds: 200)
                              : Duration.zero,
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (current, previous) => Stack(
                            fit: StackFit.expand,
                            children: [...previous, ?current],
                          ),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: AnimatedBuilder(
                                  animation: animation,
                                  child: child,
                                  builder: (_, child) => Transform.translate(
                                    offset: Offset(
                                      0,
                                      (1 - animation.value) * 6,
                                    ),
                                    child: child,
                                  ),
                                ),
                              ),
                          child: KeyedSubtree(
                            key: ObjectKey(line),
                            child: CustomPaint(
                              key: const ValueKey('luminous-stage'),
                              size: Size.infinite,
                              painter: LuminousPainter(
                                line: line,
                                position: position,
                                tilt: tilt,
                                ink: widget.ink,
                                accent: widget.accent,
                                textScaler: MediaQuery.textScalerOf(context),
                                karaoke: widget.karaoke,
                                motion: motionAllowed,
                                direction: Directionality.of(context),
                                fontFamily: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.fontFamily,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.max(
                        0,
                        (constraints.maxHeight - 32) * .32,
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration: motionAllowed
                            ? const Duration(milliseconds: 220)
                            : Duration.zero,
                        child: Column(
                          key: ObjectKey(line),
                          children: [
                            if (!short &&
                                line?.backgroundText?.isNotEmpty == true)
                              Text(
                                line!.backgroundText!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: widget.accent,
                                  fontSize: 16,
                                ),
                              ),
                            if (widget.showTranslation &&
                                line?.translation?.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  line!.translation!,
                                  maxLines: short ? 1 : 3,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: widget.ink.withValues(alpha: .8),
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            if (next != null)
                              TextButton(
                                onPressed: widget.onSeek == null
                                    ? null
                                    : () => widget.onSeek!(next.start),
                                child: Text(
                                  next.isInterlude ? '间奏 ···' : next.text,
                                  maxLines: short ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: widget.ink.withValues(alpha: .55),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class LuminousWordBox {
  const LuminousWordBox(this.word, this.center, this.size);
  final LyricWord word;
  final Offset center;
  final Size size;
}

class LuminousLayout {
  const LuminousLayout(this.words, this.fontSize);
  final List<LuminousWordBox> words;
  final double fontSize;
  static const motionInset = 28.0;
  static const maxScale = 1.12;
  static const maxRotation = .035;

  static TextPainter measure(
    String text,
    double font,
    TextScaler scaler,
    TextDirection direction,
    Color color, [
    String? fontFamily,
  ]) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: font,
        fontWeight: FontWeight.w700,
        color: color,
        fontFamily: fontFamily,
        height: 1.2,
      ),
    ),
    textDirection: direction,
    textScaler: scaler,
  )..layout();

  static LuminousLayout calculate(
    List<LyricWord> words,
    Size size,
    TextScaler scaler,
    TextDirection direction, [
    String? fontFamily,
  ]) {
    final width = math.max(1.0, size.width - motionInset * 2);
    final height = math.max(1.0, size.height - motionInset * 2);
    var font = math.min(48.0, math.max(28.0, size.width * .085));
    List<LuminousWordBox> boxes = [];
    // Scale to fit even long, unbroken words. Never use ellipsis on the main lyric.
    for (var attempt = 0; attempt < 60; attempt++) {
      final rows = <List<(LyricWord, Size, Size)>>[[]];
      final rowWidths = <double>[0];
      final rowHeights = <double>[0];
      final gap = font * .20;
      var tooWide = false;
      for (final word in words) {
        final painter = measure(
          word.text,
          font,
          scaler,
          direction,
          Colors.white,
          fontFamily,
        );
        final original = painter.size;
        painter.dispose();
        // Rotation can enlarge the bounds; account for both axes and glow.
        final bound = Size(
          (original.width + original.height * maxRotation) * maxScale + 12,
          (original.height + original.width * maxRotation) * maxScale + 12,
        );
        if (bound.width > width) tooWide = true;
        if (rows.last.isNotEmpty &&
            rowWidths.last + gap + bound.width > width) {
          rows.add([]);
          rowWidths.add(0);
          rowHeights.add(0);
        }
        rowWidths[rowWidths.length - 1] +=
            (rows.last.isEmpty ? 0 : gap) + bound.width;
        rowHeights[rowHeights.length - 1] = math.max(
          rowHeights.last,
          bound.height,
        );
        rows.last.add((word, original, bound));
      }
      final total =
          rowHeights.fold(0.0, (a, b) => a + b) + gap * (rows.length - 1);
      if (!tooWide && total <= height) {
        boxes = [];
        var y = (size.height - total) / 2;
        for (var row = 0; row < rows.length; row++) {
          var x = (size.width - rowWidths[row]) / 2;
          for (final item in rows[row]) {
            boxes.add(
              LuminousWordBox(
                item.$1,
                Offset(x + item.$3.width / 2, y + rowHeights[row] / 2),
                item.$2,
              ),
            );
            x += item.$3.width + gap;
          }
          y += rowHeights[row] + gap;
        }
        break;
      }
      font *= .86;
    }
    return LuminousLayout(boxes, font);
  }
}

class LuminousPainter extends CustomPainter {
  LuminousPainter({
    required this.line,
    required this.position,
    required this.tilt,
    required this.ink,
    required this.accent,
    required this.textScaler,
    required this.karaoke,
    required this.motion,
    required this.direction,
    this.fontFamily,
  });
  final LyricLine? line;
  final Duration position;
  final Offset tilt;
  final Color ink, accent;
  final TextScaler textScaler;
  final bool karaoke, motion;
  final TextDirection direction;
  final String? fontFamily;
  LuminousLayout? _layout;
  Size? _size;

  List<LyricWord> get words => line == null
      ? [const LyricWord('等待演唱', Duration.zero, Duration.zero)]
      : line!.isInterlude
      ? [LyricWord('···', line!.start, line!.end)]
      : karaoke && line!.words.isNotEmpty
      ? line!.words
      : RegExp(
              r'[\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]|[^\s\u3400-\u9fff\u3040-\u30ff\uac00-\ud7af]+\s*',
            )
            .allMatches(line!.text)
            .map((match) => LyricWord(match.group(0)!, line!.start, line!.end))
            .toList();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 60 || size.height < 60) return;
    final layout = _size == size && _layout != null
        ? _layout!
        : LuminousLayout.calculate(
            words,
            size,
            textScaler,
            direction,
            fontFamily,
          );
    _size = size;
    _layout = layout;
    final seconds = position.inMicroseconds / 1000000;
    final seed = (line?.start.inMilliseconds ?? 0) / 1000;
    final arrival = motion && line != null
        ? Curves.easeOutCubic.transform(
            ((position - line!.start).inMilliseconds / 220).clamp(0.0, 1.0),
          )
        : 1.0;
    for (var i = 0; i < layout.words.length; i++) {
      final box = layout.words[i];
      final word = box.word;
      final duration = math.max(1, (word.end - word.start).inMicroseconds);
      final progress = ((position - word.start).inMicroseconds / duration)
          .clamp(0.0, 1.0);
      final live = position >= word.start && position < word.end;
      final passed = position >= word.end;
      final phase = seed + i * 1.71;
      final pulse = live && motion ? math.sin(progress * math.pi) : 0.0;
      final offset = motion
          ? Offset(
              math.sin(phase) * 4 + tilt.dx * 5,
              math.sin(seconds * .85 + phase) * 6 +
                  tilt.dy * 5 -
                  pulse * 3 +
                  (1 - arrival) * 4,
            )
          : Offset.zero;
      canvas.save();
      canvas.translate(box.center.dx + offset.dx, box.center.dy + offset.dy);
      canvas.rotate(motion ? math.sin(phase) * LuminousLayout.maxRotation : 0);
      canvas.scale(1 + pulse * .12);
      final painter = LuminousLayout.measure(
        word.text,
        layout.fontSize,
        textScaler,
        direction,
        ink.withValues(
          alpha:
              (passed
                  ? .9
                  : live
                  ? 1
                  : .48) *
              (.5 + arrival * .5),
        ),
        fontFamily,
      );
      final origin = Offset(-painter.width / 2, -painter.height / 2);
      painter.paint(canvas, origin);
      if (live && karaoke && line?.words.isNotEmpty == true) {
        final glow = TextPainter(
          text: TextSpan(
            text: word.text,
            style: TextStyle(
              fontSize: layout.fontSize,
              fontFamily: fontFamily,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: accent,
              shadows: [
                Shadow(color: accent.withValues(alpha: .45), blurRadius: 6),
              ],
            ),
          ),
          textDirection: direction,
          textScaler: textScaler,
        )..layout();
        canvas.save();
        final filled = glow.width * progress;
        canvas.clipRect(
          Rect.fromLTWH(
            direction == TextDirection.rtl
                ? origin.dx + glow.width - filled
                : origin.dx,
            origin.dy - 6,
            filled,
            glow.height + 12,
          ),
        );
        glow.paint(canvas, origin);
        canvas.restore();
        glow.dispose();
      }
      painter.dispose();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant LuminousPainter oldDelegate) {
    if (oldDelegate.fontFamily == fontFamily &&
        oldDelegate.line == line &&
        oldDelegate.karaoke == karaoke &&
        oldDelegate.textScaler == textScaler &&
        oldDelegate.direction == direction) {
      _layout = oldDelegate._layout;
      _size = oldDelegate._size;
    }
    return oldDelegate.fontFamily != fontFamily ||
        oldDelegate.position != position ||
        oldDelegate.tilt != tilt ||
        oldDelegate.line != line ||
        oldDelegate.ink != ink ||
        oldDelegate.accent != accent ||
        oldDelegate.motion != motion ||
        oldDelegate.karaoke != karaoke ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.direction != direction;
  }
}
