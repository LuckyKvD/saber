import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tools/shape_recognizer.dart';

/// Zeichnet einen Weg entlang der Ecken mit leichtem, deterministischem Zittern.
List<Offset> path(List<Offset> corners, {bool close = true, double jitter = 2}) {
  final pts = <Offset>[];
  final n = close ? corners.length : corners.length - 1;
  var k = 0;
  for (var i = 0; i < n; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % corners.length];
    for (var s = 0; s < 20; s++) {
      final t = s / 20;
      final j = math.sin(k * 1.7) * jitter;
      k++;
      pts.add(Offset.lerp(a, b, t)! + Offset(j, -j));
    }
  }
  pts.add(close ? corners.first + const Offset(3, 2) : corners.last);
  return pts;
}

void main() {
  test('erkennt Dreieck (rechtwinklig, nicht normiert)', () {
    final r = ShapeRecognizer.recognize(
      path(const [Offset(0, 0), Offset(0, 200), Offset(120, 200)]),
    );
    expect(r?.kind, HeldShapeKind.polygon);
    expect(r!.outline.length, 3);
  });

  test('erkennt Dreieck, wenn Start mitten auf einer Kante liegt', () {
    final pts = path(const [Offset(100, 0), Offset(200, 180), Offset(0, 180)]);
    final shifted = [...pts.sublist(30), ...pts.sublist(0, 30)];
    final r = ShapeRecognizer.recognize(shifted);
    expect(r?.kind, HeldShapeKind.polygon);
    expect(r!.outline.length, 3);
  });

  test('erkennt achsenparalleles Rechteck', () {
    final r = ShapeRecognizer.recognize(
      path(const [Offset(0, 0), Offset(200, 0), Offset(200, 140), Offset(0, 140)]),
    );
    expect(r?.kind, HeldShapeKind.rectangle);
    expect(r!.rect!.width, closeTo(200, 6));
    expect(r.rect!.height, closeTo(140, 6));
  });

  test('erkennt Kreis', () {
    final pts = [
      for (var i = 0; i <= 80; i++)
        Offset(
          100 + 80 * math.cos(2 * math.pi * i / 80) + math.sin(i * 1.3),
          100 + 80 * math.sin(2 * math.pi * i / 80),
        ),
    ];
    final r = ShapeRecognizer.recognize(pts);
    expect(r?.kind, HeldShapeKind.circle);
    expect(r!.radius, closeTo(80, 6));
  });

  test('erkennt gerade Linie', () {
    final r = ShapeRecognizer.recognize(
      path(const [Offset(0, 0), Offset(300, 40)], close: false),
    );
    expect(r?.kind, HeldShapeKind.line);
  });

  test('Kritzeln wird nicht umgewandelt', () {
    final pts = [
      for (var i = 0; i < 60; i++)
        Offset(i * 5.0, 40 * math.sin(i * 0.5) + 30 * math.cos(i * 1.9)),
    ];
    expect(ShapeRecognizer.recognize(pts), isNull);
  });
}
