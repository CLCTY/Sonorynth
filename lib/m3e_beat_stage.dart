import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'artwork_image.dart';

/// The static alternative never mounts the animated stage or its image loader.
class AlbumBackground extends StatelessWidget {
  const AlbumBackground({
    super.key,
    required this.singleColor,
    required this.colors,
    required this.trackId,
    this.coverUrl = '',
    this.lowPower = false,
    this.animate = true,
  });
  final bool singleColor;
  final List<Color> colors;
  final String trackId;
  final String coverUrl;
  final bool lowPower;
  final bool animate;

  static List<Color> gradientColors(List<Color> palette, bool dark) {
    final source = HSLColor.fromColor(
      palette.isEmpty ? Colors.grey : palette.first,
    );
    final saturation = source.saturation < .03
        ? 0.0
        : (source.saturation * 1.15).clamp(.62, .92);
    final bottom = dark ? .32 : .74;
    return [
      HSLColor.fromAHSL(1, source.hue, saturation, bottom - .07).toColor(),
      HSLColor.fromAHSL(1, source.hue, saturation, bottom).toColor(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!singleColor) {
      return PaletteGradientStage(
        colors: colors,
        trackId: trackId,
        coverUrl: coverUrl,
        lowPower: lowPower,
        animate: animate,
      );
    }
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: gradientColors(
              colors,
              Theme.of(context).brightness == Brightness.dark,
            ),
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// An album-driven flowing mesh background.
///
/// A palette field with locally advected album texture, using a small mesh
/// and a throttled timer. The texture deforms instead of rotating as a whole.
class PaletteGradientStage extends StatefulWidget {
  const PaletteGradientStage({
    super.key,
    required this.colors,
    required this.trackId,
    this.coverUrl = '',
    this.lowPower = false,
    this.animate = true,
    this.debugTexture,
  });

  final List<Color> colors;
  final String trackId;
  final String coverUrl;
  final bool lowPower;
  final bool animate;
  @visibleForTesting
  final ui.Image? debugTexture;

  @visibleForTesting
  static bool debugIsNeutralPalette(List<Color> colors) =>
      _PaletteGradientPainter._isNeutralPalette(colors);

  @visibleForTesting
  static List<Color> debugBuildFieldPalette(
    List<Color> colors,
    Color base,
    bool dark,
  ) => _PaletteGradientPainter._buildFieldPalette(colors, base, dark);

  @override
  State<PaletteGradientStage> createState() => _PaletteGradientStageState();
}

class _PaletteGradientStageState extends State<PaletteGradientStage>
    with WidgetsBindingObserver {
  static const _imageTransitionDuration = 1.4;
  static final Float64List _identityMatrix = Float64List.fromList(const [
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);

  final ValueNotifier<double> _time = ValueNotifier(0);
  Timer? _flowTimer;
  bool _tickerModeEnabled = true;
  bool _appActive = true;
  double _flowSeconds = 0;
  double _imageTransitionStart = 0;
  double _paletteTransitionStart = 0;
  int _imageRequest = 0;

  ui.Image? _image;
  ui.Shader? _imageShader;
  ui.Image? _previousImage;
  ui.Shader? _previousImageShader;
  late List<Color> _paletteFrom;
  late List<Color> _paletteTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _paletteFrom = List<Color>.of(widget.colors);
    _paletteTo = List<Color>.of(widget.colors);
    final debugTexture = widget.debugTexture;
    if (debugTexture == null) {
      _loadCover(widget.coverUrl);
    } else {
      _image = _softenTexture(debugTexture);
      _imageShader = _shaderFor(_image!);
    }
  }

  Duration get _frameInterval => widget.lowPower
      ? const Duration(milliseconds: 100)
      : const Duration(microseconds: 55556);

  void _paintNextFrame({bool advance = true}) {
    if (!mounted) return;
    if (advance) {
      _flowSeconds +=
          _frameInterval.inMicroseconds / Duration.microsecondsPerSecond;
    }
    _completeImageTransitionIfNeeded();
    _time.value = _flowSeconds;
  }

  void _updateFlowTimer({bool restart = false}) {
    final shouldRun = widget.animate && _tickerModeEnabled && _appActive;
    if (!shouldRun) {
      _flowTimer?.cancel();
      _flowTimer = null;
      return;
    }
    if (_flowTimer != null && !restart) return;
    _flowTimer?.cancel();
    _paintNextFrame(advance: false);
    _flowTimer = Timer.periodic(_frameInterval, (_) => _paintNextFrame());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_tickerModeEnabled != enabled) {
      _tickerModeEnabled = enabled;
      _updateFlowTimer();
    } else if (_flowTimer == null) {
      _updateFlowTimer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    _updateFlowTimer();
  }

  bool _sameColors(List<Color> left, List<Color> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  ui.Shader _shaderFor(ui.Image image) => ui.ImageShader(
    image,
    TileMode.mirror,
    TileMode.mirror,
    _identityMatrix,
    filterQuality: FilterQuality.low,
  );

  // Preprocess only when artwork changes, never blur a full-screen frame.
  // Mirror sampling avoids introducing transparent/black texture borders.
  ui.Image _softenTexture(ui.Image source) {
    final recorder = ui.PictureRecorder();
    final shader = _shaderFor(source);
    Canvas(recorder).drawRect(
      Rect.fromLTWH(-12, -12, source.width + 24, source.height + 24),
      Paint()
        ..shader = shader
        ..imageFilter = ui.ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(source.width, source.height);
    } finally {
      picture.dispose();
      shader.dispose();
    }
  }

  Future<void> _loadCover(String rawUrl) async {
    final request = ++_imageRequest;
    if (_image != null) _replaceImage(null);
    if (rawUrl.trim().isEmpty) return;

    ui.Image? decoded;
    try {
      // Reuse the same 96 px disk entry as palette extraction, then decode an
      // independent 12 px texture. Upscaling this tiny image softens artwork
      // detail once, without a per-frame blur or an offscreen layer.
      final bytes = await ArtworkImage.loadBytes(rawUrl, size: 96);
      if (bytes == null || bytes.isEmpty) return;
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 12,
        targetHeight: 12,
      );
      try {
        final source = (await codec.getNextFrame()).image;
        try {
          decoded = _softenTexture(source);
        } finally {
          source.dispose();
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      decoded?.dispose();
      return;
    }

    if (!mounted || request != _imageRequest) {
      decoded.dispose();
      return;
    }
    _replaceImage(decoded);
  }

  void _replaceImage(ui.Image? next) {
    if (!mounted) {
      next?.dispose();
      return;
    }
    if (!widget.animate) {
      _previousImageShader?.dispose();
      _previousImageShader = null;
      _imageShader?.dispose();
      _imageShader = null;
      _previousImage?.dispose();
      _image?.dispose();
      _previousImage = null;
      _image = next;
      _imageShader = next == null ? null : _shaderFor(next);
      setState(() {});
      return;
    }

    final outgoingImage = _image;
    final outgoingShader = _imageShader;
    if (outgoingImage == null && next == null) return;
    if (outgoingImage != null) {
      _previousImageShader?.dispose();
      _previousImageShader = null;
      _previousImage?.dispose();
      _previousImage = outgoingImage;
      _previousImageShader = outgoingShader;
    }
    _image = next;
    _imageShader = next == null ? null : _shaderFor(next);
    _imageTransitionStart = _flowSeconds;
    setState(() {});
  }

  void _completeImageTransitionIfNeeded() {
    if (_previousImage == null ||
        _flowSeconds - _imageTransitionStart < _imageTransitionDuration) {
      return;
    }
    _previousImageShader?.dispose();
    _previousImageShader = null;
    _previousImage?.dispose();
    _previousImage = null;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant PaletteGradientStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate ||
        oldWidget.lowPower != widget.lowPower) {
      _updateFlowTimer(restart: true);
    }
    if (widget.debugTexture == null && oldWidget.coverUrl != widget.coverUrl) {
      _loadCover(widget.coverUrl);
    }
    final colorsChanged = !_sameColors(oldWidget.colors, widget.colors);
    if (!widget.animate && (oldWidget.animate || colorsChanged)) {
      // With no timer, transition time cannot advance. Snap to the new palette
      // so a paused/restored song never remains stuck on the previous colour.
      _paletteFrom = List<Color>.of(widget.colors);
      _paletteTo = List<Color>.of(widget.colors);
      _paletteTransitionStart = _flowSeconds;
    } else if (colorsChanged) {
      _paletteFrom = List<Color>.of(_paletteTo);
      _paletteTo = List<Color>.of(widget.colors);
      _paletteTransitionStart = _flowSeconds;
    }
  }

  @override
  void dispose() {
    _imageRequest++;
    WidgetsBinding.instance.removeObserver(this);
    _flowTimer?.cancel();
    _time.dispose();
    _imageShader?.dispose();
    _previousImageShader?.dispose();
    _imageShader = null;
    _previousImageShader = null;
    if (!identical(_image, widget.debugTexture)) _image?.dispose();
    if (!identical(_previousImage, widget.debugTexture)) {
      _previousImage?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // Keep the background's low-rate repaints from walking up to the Stack
      // and repainting lyrics, controls, and artwork with every flow frame.
      child: RepaintBoundary(
        child: CustomPaint(
          isComplex: true,
          willChange: widget.animate,
          painter: _PaletteGradientPainter(
            repaint: _time,
            time: _time,
            trackId: widget.trackId,
            paletteFrom: _paletteFrom,
            paletteTo: _paletteTo,
            paletteTransitionStart: _paletteTransitionStart,
            image: _image,
            imageShader: _imageShader,
            previousImage: _previousImage,
            previousImageShader: _previousImageShader,
            imageTransitionStart: _imageTransitionStart,
            base: Theme.of(context).colorScheme.surface,
            dark: Theme.of(context).brightness == Brightness.dark,
            lowPower: widget.lowPower,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PaletteGradientPainter extends CustomPainter {
  _PaletteGradientPainter({
    required Listenable repaint,
    required this.time,
    required this.trackId,
    required this.paletteFrom,
    required this.paletteTo,
    required this.paletteTransitionStart,
    required this.image,
    required this.imageShader,
    required this.previousImage,
    required this.previousImageShader,
    required this.imageTransitionStart,
    required this.base,
    required this.dark,
    required this.lowPower,
  }) : _seed = _hash(trackId),
       super(repaint: repaint) {
    _fromField = _buildFieldPalette(paletteFrom, base, dark);
    _toField = _buildFieldPalette(paletteTo, base, dark);
    _neutral = _isNeutralPalette(paletteTo);
    _textureColorFilter = _buildTextureColorFilter(
      dark,
      neutral: _neutral,
      subdued: _isSubduedPalette(paletteTo),
    );
  }

  static const _columns = 13;
  static const _rows = 19;
  static const _vertexCount = _columns * _rows;
  static const _paletteTransitionDuration = 1.4;
  static const _imageTransitionDuration = 1.4;

  final ValueNotifier<double> time;
  final String trackId;
  final List<Color> paletteFrom;
  final List<Color> paletteTo;
  final double paletteTransitionStart;
  final ui.Image? image;
  final ui.Shader? imageShader;
  final ui.Image? previousImage;
  final ui.Shader? previousImageShader;
  final double imageTransitionStart;
  final Color base;
  final bool dark;
  final bool lowPower;
  final int _seed;

  late final List<Color> _fromField;
  late final List<Color> _toField;
  late final bool _neutral;
  late final ColorFilter _textureColorFilter;
  Float32List? _positions;
  Float32List? _textureCoordinates;
  Int32List? _vertexColors;
  Uint16List? _indices;
  Size _meshSize = Size.zero;

  static int _hash(String value) {
    var hash = 2166136261;
    for (final code in value.codeUnits) {
      hash = ((hash ^ code) * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  static double _ease(double value) {
    final x = value.clamp(0.0, 1.0);
    return -(math.cos(math.pi * x) - 1) / 2;
  }

  double _unit(int salt) {
    final value = math.sin((_seed + salt * 7919) * .000013) * 43758.5453;
    return value - value.floorToDouble();
  }

  static List<Color> _buildFieldPalette(
    List<Color> source,
    Color base,
    bool dark,
  ) {
    final raw = source.isEmpty
        ? const <Color>[Color(0xff707070), Color(0xff565656), Color(0xff929292)]
        : source;
    final neutral = _isNeutralPalette(raw);
    final subdued = _isSubduedPalette(raw);
    final baseHsl = HSLColor.fromColor(base);
    final fieldBase = neutral
        ? HSLColor.fromAHSL(1, 0, 0, baseHsl.lightness).toColor()
        : base;
    final tuned = <Color>[];
    for (var index = 0; index < raw.length; index++) {
      final color = raw[index];
      final hsl = HSLColor.fromColor(color);
      final adjusted = hsl
          .withSaturation(
            neutral
                ? 0
                : subdued
                ? (hsl.saturation * 1.16).clamp(0, .36)
                : (hsl.saturation * 1.35).clamp(.45, .94),
          )
          .withLightness(
            // Map rather than clamp: preserve tonal variation between colours.
            ((dark ? .12 : .66) +
                    hsl.lightness * (dark ? .27 : .26) +
                    (index.isEven ? -.035 : .035))
                .clamp(dark ? .10 : .64, dark ? .42 : .94),
          )
          .toColor();
      // Light mode previously mixed nearly half of the album colour away once
      // the later surface veils were applied. Keep the same field and draw
      // count, but retain more of the source palette so it reads clearly.
      tuned.add(Color.lerp(fieldBase, adjusted, dark ? .92 : .94)!);
    }
    if (tuned.length == 1) {
      final hsl = HSLColor.fromColor(tuned.first);
      tuned.add(
        hsl.withLightness((hsl.lightness + .10).clamp(.12, .88)).toColor(),
      );
      tuned.add(
        hsl.withLightness((hsl.lightness - .10).clamp(.12, .88)).toColor(),
      );
    }

    final field = <Color>[];
    for (var i = 0; i < tuned.length; i++) {
      final current = tuned[i];
      final next = tuned[(i + 1) % tuned.length];
      field
        ..add(current)
        ..add(Color.lerp(current, next, .46)!);
    }
    return field;
  }

  static bool _isNeutralPalette(List<Color> colors) =>
      colors.isNotEmpty &&
      colors.every((color) => HSLColor.fromColor(color).saturation <= .02);

  static bool _isSubduedPalette(List<Color> colors) =>
      colors.isNotEmpty &&
      colors.every((color) => HSLColor.fromColor(color).saturation <= .32);

  static ColorFilter _buildTextureColorFilter(
    bool dark, {
    required bool neutral,
    required bool subdued,
  }) {
    final saturation = neutral
        ? 0.0
        : subdued
        ? 1.0
        : 3.0;
    // AMLL's album preprocessing combines contrast .4, saturation 3,
    // contrast 1.7, then brightness .75, as used by SPlayer's renderer.
    const exposure = .75;
    final brightness = (neutral || subdued ? 1.0 : .68) * exposure;
    final offset = neutral || subdued ? 0.0 : 40.96 * exposure;
    final inverse = 1 - saturation;
    final red = .30 * inverse;
    final green = .59 * inverse;
    final blue = .11 * inverse;
    return ColorFilter.matrix([
      (red + saturation) * brightness,
      green * brightness,
      blue * brightness,
      0,
      offset,
      red * brightness,
      (green + saturation) * brightness,
      blue * brightness,
      0,
      offset,
      red * brightness,
      green * brightness,
      (blue + saturation) * brightness,
      0,
      offset,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  void _ensureMesh(Size size) {
    if (_positions != null && _meshSize == size) return;
    _meshSize = size;
    _positions = Float32List(_vertexCount * 2);
    _textureCoordinates = Float32List(_vertexCount * 2);
    _vertexColors = Int32List(_vertexCount);
    _indices = Uint16List((_columns - 1) * (_rows - 1) * 6);

    var vertex = 0;
    final phase = _unit(41) * math.pi * 2;
    for (var y = 0; y < _rows; y++) {
      final v = y / (_rows - 1);
      for (var x = 0; x < _columns; x++) {
        final u = x / (_columns - 1);
        final edge = math.sin(math.pi * u) * math.sin(math.pi * v);
        final warpX =
            edge *
            (math.sin(v * math.pi * 2.1 + phase) * .050 +
                math.sin((u + v) * math.pi * 2.7 - phase * .7) * .020);
        final warpY =
            edge *
            (math.cos(u * math.pi * 2.0 - phase * .8) * .042 +
                math.sin((u - v) * math.pi * 2.4 + phase) * .018);
        _positions![vertex * 2] = (u + warpX) * size.width;
        _positions![vertex * 2 + 1] = (v + warpY) * size.height;
        vertex++;
      }
    }

    var offset = 0;
    for (var y = 0; y < _rows - 1; y++) {
      for (var x = 0; x < _columns - 1; x++) {
        final a = y * _columns + x;
        final b = a + 1;
        final c = a + _columns;
        final d = c + 1;
        if ((x + y + _seed).isEven) {
          _indices!.setRange(offset, offset + 6, [a, b, c, b, d, c]);
        } else {
          _indices!.setRange(offset, offset + 6, [a, b, d, a, d, c]);
        }
        offset += 6;
      }
    }
  }

  void _fillTextureCoordinates(
    Size size,
    ui.Image source,
    double seconds,
    int layer,
  ) {
    final aspect = size.width / size.height;
    seconds *= 1.25;
    final cropX = aspect < 1 ? aspect : 1.0;
    final cropY = aspect > 1 ? 1 / aspect : 1.0;
    final zoom = switch (layer) {
      0 => .92,
      1 => .64,
      _ => .45,
    };
    final driftX = switch (layer) {
      0 => 0.0,
      1 => -.14 + math.sin(seconds * .041 + _unit(37) * 5) * .045,
      _ => .13 + math.cos(seconds * .052 + _unit(39) * 5) * .038,
    };
    final driftY = switch (layer) {
      0 => 0.0,
      1 => -.10 + math.cos(seconds * .036 + _unit(43) * 5) * .040,
      _ => .15 + math.sin(seconds * .047 + _unit(47) * 5) * .042,
    };
    // Fixed orientation: motion comes from local advection, not a spinning cover.
    final angle = _unit(23 + layer * 13) * math.pi * 2;
    final sinAngle = math.sin(angle);
    final cosAngle = math.cos(angle);
    final sourceWidth = source.width.toDouble();
    final sourceHeight = source.height.toDouble();

    var vertex = 0;
    for (var y = 0; y < _rows; y++) {
      final v = y / (_rows - 1);
      for (var x = 0; x < _columns; x++) {
        final u = x / (_columns - 1);
        // A single smooth mesh warp carries the artwork colours together.
        // Opposite bends produce broad flowing folds without stacked spins.
        final bend = math.sin((v - .5) * math.pi * 2 + seconds * .36) * .24;
        final du = (u - .5 + bend) * cropX;
        final dv =
            (v - .5 + math.sin(u * math.pi * 2 - seconds * .29) * .16) * cropY;
        final rotateU = cosAngle * du - sinAngle * dv;
        final rotateV = sinAngle * du + cosAngle * dv;
        final rippleU =
            math.sin(v * math.pi * 2.0 + seconds * .43 + _unit(29) * 5) * .10;
        final rippleV =
            math.cos(u * math.pi * 2.0 - seconds * .37 + _unit(31) * 5) * .09;
        final sampleU = .5 + rotateU * zoom + rippleU + driftX;
        final sampleV = .5 + rotateV * zoom + rippleV + driftY;
        _textureCoordinates![vertex * 2] = sampleU * sourceWidth;
        _textureCoordinates![vertex * 2 + 1] = sampleV * sourceHeight;
        vertex++;
      }
    }
  }

  void _drawPalette(Canvas canvas, Size size, double seconds) {
    final paletteMix = _ease(
      (seconds - paletteTransitionStart) / _paletteTransitionDuration,
    );
    final backdrop = _neutral ? (dark ? Colors.black : Colors.white) : base;
    final colors = <Color>[
      for (final index in [0, 2, 4])
        Color.lerp(
          backdrop,
          Color.lerp(_fromField[index], _toField[index], paletteMix)!,
          dark ? .82 : .74,
        )!,
    ];
    final phase = _unit(7) * math.pi * 2;
    final driftX = math.sin(seconds * .48 + phase) * size.width * .32;
    final driftY = math.cos(seconds * .38 + phase) * size.height * .16;
    final bounds = Offset.zero & size;

    // The shader interpolates at screen resolution. Vertex colours made the
    // moving field look coarse and produced visible contours around the glow.
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-size.width * .32 + driftX, -size.height * .20 + driftY),
          Offset(size.width * 1.32 + driftX, size.height * 1.20 + driftY),
          [colors[0], colors[0], colors[1], colors[2]],
          const [0, .18, .60, 1],
        ),
    );

    final lightX = math.sin(seconds * .62 + phase + 1.1) * size.width * .58;
    final light = Colors.white;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-size.width * .85 + lightX, -size.height * .18),
          Offset(size.width * 1.35 + lightX, size.height * 1.18),
          [
            light.withValues(alpha: 0),
            light.withValues(alpha: dark ? .035 : .025),
            light.withValues(alpha: dark ? .20 : .13),
            light.withValues(alpha: dark ? .035 : .025),
            light.withValues(alpha: 0),
          ],
          const [0, .25, .50, .75, 1],
        ),
    );
  }

  void _drawTexture(
    Canvas canvas,
    Size size,
    ui.Image source,
    ui.Shader shader,
    double seconds,
    double opacity,
    int layer,
  ) {
    if (opacity <= .002) return;
    _fillTextureCoordinates(size, source, seconds, layer);
    final white = Colors.white.withValues(alpha: opacity).toARGB32();
    _vertexColors!.fillRange(0, _vertexColors!.length, white);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _positions!,
      textureCoordinates: _textureCoordinates,
      colors: _vertexColors,
      indices: _indices,
    );
    try {
      canvas.drawVertices(
        vertices,
        BlendMode.modulate,
        Paint()
          ..shader = shader
          ..filterQuality = FilterQuality.low
          ..colorFilter = _textureColorFilter,
      );
    } finally {
      vertices.dispose();
    }
  }

  void _drawTextureStack(
    Canvas canvas,
    Size size,
    ui.Image source,
    ui.Shader shader,
    double seconds,
    double opacity,
  ) {
    // Keep artwork texture as moving colour variation, not a recognisable
    // full-screen copy of the cover.
    const weights = <double>[1.0];
    for (var layer = 0; layer < weights.length; layer++) {
      _drawTexture(
        canvas,
        size,
        source,
        shader,
        seconds,
        opacity * weights[layer] * (dark ? .12 : .08),
        layer,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final seconds = time.value;
    _drawPalette(canvas, size, seconds);

    if (!lowPower) {
      _ensureMesh(size);
      final transition = previousImage == null
          ? 1.0
          : _ease((seconds - imageTransitionStart) / _imageTransitionDuration);
      final oldImage = previousImage;
      final oldShader = previousImageShader;
      if (oldImage != null && oldShader != null) {
        _drawTextureStack(
          canvas,
          size,
          oldImage,
          oldShader,
          seconds,
          1 - transition,
        );
      }
      final currentImage = image;
      final currentShader = imageShader;
      if (currentImage != null && currentShader != null) {
        _drawTextureStack(
          canvas,
          size,
          currentImage,
          currentShader,
          seconds,
          transition,
        );
      }
    }

    // AMLL is intentionally very saturated. A light theme-aware veil makes
    // this version one step quieter while keeping the flowing field obvious.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: dark ? .06 : 0),
    );
  }

  @override
  bool shouldRepaint(covariant _PaletteGradientPainter oldDelegate) =>
      oldDelegate.trackId != trackId ||
      !identical(oldDelegate.paletteFrom, paletteFrom) ||
      !identical(oldDelegate.paletteTo, paletteTo) ||
      oldDelegate.paletteTransitionStart != paletteTransitionStart ||
      !identical(oldDelegate.image, image) ||
      !identical(oldDelegate.previousImage, previousImage) ||
      oldDelegate.imageTransitionStart != imageTransitionStart ||
      oldDelegate.base != base ||
      oldDelegate.dark != dark ||
      oldDelegate.lowPower != lowPower;
}
