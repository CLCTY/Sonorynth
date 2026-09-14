import 'package:flutter_test/flutter_test.dart';
import 'package:sonorynth/app_state.dart';

void main() {
  test('tiny compression fringes do not tint a monochrome cover', () {
    final samples = <int>[...List.filled(99, 0), ...List.filled(1, 90)];
    expect(MelodyState.debugIsPredominantlyMonochrome(samples), isTrue);
  });

  test('coloured lettering on black artwork retains album colour', () {
    for (final count in [5, 10, 20]) {
      expect(MelodyState.debugIsPredominantlyMonochrome([
        ...List.filled(100 - count, 0), ...List.filled(count, 90),
      ]), isFalse);
    }
  });

  test('a genuinely coloured or subdued cover keeps its colour', () {
    expect(
      MelodyState.debugIsPredominantlyMonochrome(List.filled(100, 13)),
      isFalse,
    );
    expect(
      MelodyState.debugIsPredominantlyMonochrome([
        ...List.filled(70, 0),
        ...List.filled(30, 80),
      ]),
      isFalse,
    );
  });
}
