import 'dart:typed_data';

import 'package:bson/bson.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/editor/fast_bson.dart';

/// Macht die Ausgabe des Pakets `bson` und die des schnellen Lesers
/// vergleichbar (Binärdaten als Liste, Int64 als int).
dynamic normalize(dynamic value) {
  if (value is BsonBinary) return value.byteList.toList();
  if (value is Uint8List) return value.toList();
  if (value is Int64) return value.toInt();
  if (value is Map) {
    return {for (final e in value.entries) e.key.toString(): normalize(e.value)};
  }
  if (value is List) return value.map(normalize).toList();
  return value;
}

void main() {
  test('FastBson liefert dasselbe wie das Paket bson', () {
    final points = <BsonBinary>[
      for (var i = 0; i < 50; i++)
        BsonBinary.from(
          Float32List.fromList([i * 1.5, i * -2.25, 0.5]).buffer.asUint8List(),
        ),
      BsonBinary.from(
        Float32List.fromList([3.0, 4.0]).buffer.asUint8List(),
      ),
    ];
    final doc = <String, dynamic>{
      'v': 19,
      'ni': 7,
      'b': null,
      'p': 'lined',
      'l': 40,
      'lt': 1.5,
      'neg': -12345,
      'color': 0xFFAA5511,
      'big': 4294967296 * 5,
      'flag': true,
      'off': false,
      'text': 'Grüße – äöü 日本',
      'empty': <dynamic>[],
      'emptyMap': <String, dynamic>{},
      'z': [
        {
          'i': 0,
          'strokes': [
            {'p': points, 'c': 0xFF112233, 'pe': true, 'pr': 0.25},
            {'p': <BsonBinary>[], 'c': 0xFF000000, 'pe': false},
          ],
          'nested': [
            [1, 2, 3],
            [4.5, 'x', null],
          ],
        },
      ],
      'a': [
        BsonBinary.from(Uint8List.fromList(List.generate(300, (i) => i % 256))),
      ],
    };

    final bytes = BsonCodec.serialize(doc).byteList;
    final expected = normalize(BsonCodec.deserialize(BsonBinary.from(bytes)));
    final actual = normalize(FastBson.decode(Uint8List.fromList(bytes)));

    expect(actual, expected);
  });

  test('FastBson meldet kaputte Daten als FormatException', () {
    expect(
      () => FastBson.decode(Uint8List.fromList([1, 2, 3])),
      throwsA(anything),
    );
  });
}
