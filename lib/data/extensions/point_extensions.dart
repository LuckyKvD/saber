import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:bson/bson.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

extension PointExtensions on PointVector {
  @Deprecated(
    'Use fromBsonBinary instead; fromJson is only for backward compatibility',
  )
  static Point fromJson({
    required Map<String, dynamic> json,
    Offset offset = .zero,
  }) => Point(json['x'] + offset.dx, json['y'] + offset.dy, json['p']);

  /// [json] ist ein [BsonBinary] (Paket `bson`) oder ein [Uint8List]
  /// (schneller Feder-Leser `FastBson`).
  static PointVector fromBsonBinary({
    required Object json,
    Offset offset = .zero,
  }) {
    final Uint8List bytes = json is BsonBinary
        ? json.byteList
        : json as Uint8List;
    final data = ByteData.sublistView(bytes);
    final count = bytes.length ~/ 4;
    return PointVector(
      data.getFloat32(0, Endian.little) + offset.dx,
      data.getFloat32(4, Endian.little) + offset.dy,
      count == 2 ? null : data.getFloat32(8, Endian.little),
    );
  }

  BsonBinary toBsonBinary() {
    final point = Float32List.fromList([x, y, ?pressure]);
    return BsonBinary.from(point.buffer.asUint8List());
  }

  PointVector operator +(Offset offset) =>
      PointVector(x + offset.dx, y + offset.dy, pressure);
}
