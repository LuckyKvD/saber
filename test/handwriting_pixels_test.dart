import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/math/handwriting_text.dart';

void main() {
  const ink = Color(0xFF263238);

  test('transparent und Tintenfarbe sind sauber', () {
    final px = Uint8List.fromList([
      0, 0, 0, 0, // leer
      0x26, 0x32, 0x38, 255, // volle Tinte
      0x13, 0x19, 0x1C, 128, // halbtransparent (vormultipliziert)
    ]);
    expect(handwritingPixelsMatch(px, ink), isTrue);
  });

  test('fremde Farben werden erkannt', () {
    final px = Uint8List(4 * 1000);
    for (var i = 0; i < 1000; i += 2) {
      px[i * 4] = 200;
      px[i * 4 + 1] = 40;
      px[i * 4 + 2] = 40;
      px[i * 4 + 3] = 255;
    }
    expect(handwritingPixelsMatch(px, ink), isFalse);
  });
}
