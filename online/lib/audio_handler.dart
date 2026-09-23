// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

class MelodyAudioHandler extends BaseAudioHandler with SeekHandler {
  MelodyAudioHandler() {
    player.playbackEventStream.listen(
      _broadcastState,
      onError: (Object error, StackTrace stackTrace) {
        playbackState.add(
          playbackState.value.copyWith(
            processingState: AudioProcessingState.error,
          ),
        );
      },
    );
  }

  final AudioPlayer player = AudioPlayer(handleInterruptions: false);
  Future<void> Function(int offset)? onSkip;
  int _queueIndex = 0;
  late AudioSession _session;
  bool _userWantsPlayback = false;
  bool _resumeAfterInterruption = false;
  int _routeCheckSerial = 0;

  Future<void> initialize() async {
    _session = await AudioSession.instance;
    await _session.configure(
      const AudioSessionConfiguration.music().copyWith(
        androidWillPauseWhenDucked: false,
      ),
    );
    _session.interruptionEventStream.listen(_handleInterruption);
    _session.becomingNoisyEventStream.listen((_) {
      unawaited(_handleBecomingNoisy());
    });
  }

  void publishQueue(List<MediaItem> items, int index) {
    if (items.isEmpty) return;
    _queueIndex = index.clamp(0, items.length - 1);
    queue.add(items);
    mediaItem.add(items[_queueIndex]);
    _broadcastState(player.playbackEvent);
  }

  @override
  Future<void> play() {
    _userWantsPlayback = true;
    return player.play();
  }

  @override
  Future<void> pause() {
    _userWantsPlayback = false;
    _resumeAfterInterruption = false;
    return player.pause();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    _userWantsPlayback = false;
    _resumeAfterInterruption = false;
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async => onSkip?.call(1);

  @override
  Future<void> skipToPrevious() async => onSkip?.call(-1);

  void _handleInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          unawaited(player.setVolume(math.min(player.volume, .32)));
          return;
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          _resumeAfterInterruption = _userWantsPlayback && player.playing;
          if (_resumeAfterInterruption) unawaited(player.pause());
      }
      return;
    }
    switch (event.type) {
      case AudioInterruptionType.duck:
        unawaited(player.setVolume(1));
        return;
      case AudioInterruptionType.pause:
      case AudioInterruptionType.unknown:
        final shouldResume = _resumeAfterInterruption && _userWantsPlayback;
        _resumeAfterInterruption = false;
        if (shouldResume) unawaited(player.play());
    }
  }

  Future<void> _handleBecomingNoisy() async {
    final serial = ++_routeCheckSerial;
    // Bluetooth profile transitions can briefly look like a disconnect. Wait
    // for the route to settle and confirm twice before treating it as unplugged.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (serial != _routeCheckSerial || await _hasPrivateOutput()) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (serial != _routeCheckSerial || await _hasPrivateOutput()) return;
    if (_userWantsPlayback && player.playing) await pause();
  }

  Future<bool> _hasPrivateOutput() async {
    final devices = await _session.getDevices(
      includeInputs: false,
      includeOutputs: true,
    );
    return devices.any(
      (device) =>
          device.isOutput &&
          const {
            AudioDeviceType.bluetoothA2dp,
            AudioDeviceType.bluetoothLe,
            AudioDeviceType.bluetoothSco,
            AudioDeviceType.wiredHeadphones,
            AudioDeviceType.wiredHeadset,
            AudioDeviceType.usbAudio,
            AudioDeviceType.hearingAid,
          }.contains(device.type),
    );
  }

  void _broadcastState(PlaybackEvent event) {
    final playing = player.playing;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {MediaAction.seek},
        processingState: switch (player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: _queueIndex,
      ),
    );
  }
}
