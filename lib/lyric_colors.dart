import 'package:flutter/material.dart';

/// Album-derived singer roles; neutrals stay neutral instead of inventing hues.
Color albumLyricRoleColor(List<Color> palette, bool dark, int role) {
  final colors = palette.isEmpty ? const [Colors.grey] : palette;
  final chromatic = colors
      .where((c) => HSLColor.fromColor(c).saturation > .08)
      .toList();
  if (chromatic.isEmpty) {
    return HSLColor.fromAHSL(
      1,
      0,
      0,
      (dark ? const [.94, .78, .64] : const [.12, .25, .36])[role % 3],
    ).toColor();
  }
  final source = HSLColor.fromColor(chromatic[role % chromatic.length]);
  final first = HSLColor.fromColor(chromatic.first);
  final delta = (source.hue - first.hue).abs();
  final similar = delta < 24 || delta > 336;
  final hue = role > 0 && similar
      ? (first.hue + (role == 1 ? 32 : -32) + 360) % 360
      : source.hue;
  return HSLColor.fromAHSL(
    1,
    hue,
    (source.saturation * 1.22).clamp(.78, .96),
    (dark ? const [.66, .64, .62] : const [.30, .32, .34])[role % 3],
  ).toColor();
}
