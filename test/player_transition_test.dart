import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:sonorynth/app_state.dart';

import 'package:sonorynth/models.dart';

import 'package:sonorynth/ui.dart';

class TransitionState extends ChangeNotifier implements MelodyState {
  TransitionState({this.isPlaying = false, this.coverShape = 4});

  final bool isPlaying;

  final int coverShape;

  @override
  Track get current => const Track(
    id: 'transition',

    title: '在你的身边',

    artist: '盛哲',

    album: '测试专辑',

    coverUrl: '',
  );

  @override
  bool get hasCurrent => true;

  @override
  bool get playing => isPlaying;

  @override
  bool get preparingPlayback => false;

  @override
  bool get gradientPlayerBackground => false;

  @override
  bool get singleColorPlayerBackground => false;

  @override
  bool get efficientRendering => true;

  @override
  List<Color> get coverPalette => const [Color(0xFF6750A4)];

  @override
  bool get uiElementAnimations => true;

  @override
  bool get lyricBlur => true;

  @override
  bool get shuffleEnabled => false;

  @override
  PlaybackRepeatMode get repeatMode => PlaybackRepeatMode.all;

  @override
  FontWeight get emphasisWeight => FontWeight.w600;

  @override
  String? get message => null;

  @override
  AudioQuality get quality => AudioQuality.standard;

  @override
  int cardShape(String id, int fallback) =>
      id == 'player_cover' ? coverShape : fallback;

  @override
  bool isLiked(Track track) => false;

  @override
  final playbackTimeline = ValueNotifier(
    const PlaybackTimeline(
      position: Duration(seconds: 90),

      duration: Duration(seconds: 240),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final floating in [true, false]) {
    testWidgets(
      'shared elements match ${floating ? "floating" : "attached"} source and reverse',

      (tester) async {
        final state = TransitionState();

        tester.view.devicePixelRatio = 1;

        tester.view.physicalSize = const Size(384, 832);

        final boundary = GlobalKey();

        final navigator = GlobalKey<NavigatorState>();

        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,

            child: MelodyScope(
              state: state,

              child: MaterialApp(
                navigatorKey: navigator,

                theme: ThemeData(
                  useMaterial3: true,

                  colorScheme: ColorScheme.fromSeed(
                    seedColor: const Color(0xff466b58),
                  ),
                ),

                home: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,

                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),

                      child: floating
                          ? FloatingMiniPlayer(state: state)
                          : MiniPlayer(state: state),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        Finder hero(String tag) =>
            find.byWidgetPredicate((w) => w is Hero && w.tag == tag);

        Finder flight(String tag) => find.byKey(ValueKey('player-flight-$tag'));

        final initialCover = tester.getRect(hero('now-cover'));

        expect(initialCover.width, floating ? 42 : 54);

        await tester.tap(find.text('在你的身边'));

        await tester.pump();

        await tester.pump();

        expect(tester.takeException(), isNull);

        for (final tag in [
          'now-cover',

          'now-title',

          'now-artist',

          'now-play',
        ]) {
          expect(
            flight(tag),

            findsOneWidget,

            reason: '$tag must have a real shared-element flight',
          );
        }

        final startCover = tester.getRect(flight('now-cover'));

        expect((startCover.width - initialCover.width).abs(), lessThan(1));

        expect((startCover.top - initialCover.top).abs(), lessThan(1));

        for (var frame = 0; frame < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 30));

          expect(
            tester
                .getRect(flight('now-title'))
                .overlaps(tester.getRect(flight('now-cover'))),

            isFalse,

            reason:
                'frame $frame: title ${tester.getRect(flight('now-title'))} cover ${tester.getRect(flight('now-cover'))}',
          );
        }

        final midCover = tester.getRect(flight('now-cover'));

        expect(midCover.width, greaterThan(initialCover.width));

        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);

        final fullCover = tester.getRect(hero('now-cover'));

        expect(fullCover.width, greaterThan(midCover.width));

        navigator.currentState!.pop();

        await tester.pump();

        await tester.pump(const Duration(milliseconds: 120));

        expect(flight('now-cover'), findsOneWidget);

        final closingCover = tester.getRect(flight('now-cover'));

        expect(
          closingCover.width,

          inExclusiveRange(initialCover.width, fullCover.width),
        );

        await tester.pumpAndSettle();

        expect(tester.getRect(hero('now-cover')), initialCover);

        expect(tester.takeException(), isNull);

        // Re-open, cancel one drag, then finish a gesture dismissal.

        await tester.tap(find.text('在你的身边'));

        await tester.pumpAndSettle();

        final gesture = await tester.startGesture(const Offset(190, 30));

        await gesture.moveBy(const Offset(0, 90));

        await tester.pump(const Duration(milliseconds: 40));

        await gesture.up();

        await tester.pumpAndSettle();

        expect(find.byTooltip('收起播放器'), findsOneWidget);

        expect(navigator.currentState!.userGestureInProgress, isFalse);

        final canceled = await tester.startGesture(const Offset(190, 30));

        await canceled.moveBy(const Offset(0, 90));

        await tester.pump(const Duration(milliseconds: 40));

        await canceled.cancel();

        await tester.pumpAndSettle();

        expect(find.byTooltip('收起播放器'), findsOneWidget);

        expect(navigator.currentState!.userGestureInProgress, isFalse);

        await tester.flingFrom(
          const Offset(190, 30),

          const Offset(0, 600),

          900,
        );

        await tester.pumpAndSettle();

        expect(find.byTooltip('收起播放器'), findsNothing);

        expect(navigator.currentState!.userGestureInProgress, isFalse);

        expect(tester.getRect(hero('now-cover')), initialCover);

        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());

        state.playbackTimeline.dispose();

        state.dispose();

        tester.view.resetPhysicalSize();

        tester.view.resetDevicePixelRatio();
      },
    );
  }

  for (final floating in [true, false]) {
    for (final playing in [true, false]) {
      testWidgets(
        'handoff has no white fill and matches ${playing ? "pause" : "play"} shape ($floating)',

        (tester) async {
          final state = TransitionState(
            isPlaying: playing,

            coverShape: playing ? 5 : 4,
          );

          tester.view.devicePixelRatio = 1;

          tester.view.physicalSize = const Size(384, 832);

          final boundary = GlobalKey();

          final navigator = GlobalKey<NavigatorState>();

          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,

              child: MelodyScope(
                state: state,

                child: MaterialApp(
                  navigatorKey: navigator,

                  theme: ThemeData(
                    useMaterial3: true,

                    canvasColor: Colors.white,

                    colorScheme: ColorScheme.fromSeed(
                      seedColor: Colors.green,

                      brightness: Brightness.dark,
                    ),

                    scaffoldBackgroundColor: const Color(0xff121a22),
                  ),

                  home: Scaffold(
                    body: Align(
                      alignment: Alignment.bottomCenter,

                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),

                        child: floating
                            ? FloatingMiniPlayer(state: state)
                            : MiniPlayer(state: state),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );

          await tester.pump(const Duration(milliseconds: 360));

          Finder element(String tag, bool flying) => flying
              ? find.byKey(ValueKey('player-flight-$tag'))
              : find.byWidgetPredicate(
                  (widget) => widget is Hero && widget.tag == tag,
                );

          Future<void> verify(String phase, bool flying) async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;

            final picture = (await tester.runAsync(() => render.toImage()))!;

            final data = (await tester.runAsync(
              () => picture.toByteData(format: ui.ImageByteFormat.rawRgba),
            ))!;

            List<int> sample(Rect rect, double x, double y) {
              final px = (rect.left + x * rect.width).floor().clamp(
                0,

                picture.width - 1,
              );

              final py = (rect.top + y * rect.height).floor().clamp(
                0,

                picture.height - 1,
              );

              final index = (py * picture.width + px) * 4;

              return [
                data.getUint8(index),

                data.getUint8(index + 1),

                data.getUint8(index + 2),
              ];
            }

            final cover = tester.getRect(element('now-cover', flying));

            for (final point in [
              const Offset(.5, .07),

              const Offset(.93, .5),

              const Offset(.5, .93),

              const Offset(.07, .5),
            ]) {
              final pixel = sample(cover, point.dx, point.dy);

              expect(
                pixel[1],

                lessThan(140),

                reason: '$phase: no white canvas behind cover',
              );

              expect(
                pixel[2],

                lessThan(140),

                reason: '$phase: no white canvas behind cover',
              );
            }

            final button = tester.getRect(element('now-play', flying));

            final fill = sample(button, .5, .2);

            final corner = sample(button, .1, .12);

            final difference =
                (fill[0] - corner[0]).abs() +
                (fill[1] - corner[1]).abs() +
                (fill[2] - corner[2]).abs();

            expect(
              difference < 45,

              playing,

              reason:
                  '$phase: corner must match actual button, difference $difference',
            );

            picture.dispose();
          }

          await verify('source', false);

          await tester.tap(find.text('在你的身边'));

          await tester.pump();

          await tester.pump();

          await verify('first opening frame', true);

          await tester.pump(const Duration(milliseconds: 270));

          await verify('last opening frame', true);

          await tester.pump(const Duration(milliseconds: 10));

          await tester.pump(const Duration(milliseconds: 16));

          expect(
            element('now-cover', true),

            findsNothing,

            reason: 'opening finishes within one frame of 280ms',
          );

          await verify('full page handoff', false);

          navigator.currentState!.pop();

          await tester.pump();

          await tester.pump(const Duration(milliseconds: 230));

          await verify('last closing frame', true);

          await tester.pump(const Duration(milliseconds: 10));

          await tester.pump(const Duration(milliseconds: 16));

          expect(
            element('now-cover', true),

            findsNothing,

            reason: 'closing finishes within one frame of 240ms',
          );

          await verify('mini player handoff', false);

          expect(tester.takeException(), isNull);

          await tester.pumpWidget(const SizedBox());

          state.playbackTimeline.dispose();

          state.dispose();

          tester.view.resetPhysicalSize();

          tester.view.resetDevicePixelRatio();
        },
      );
    }
  }
}
