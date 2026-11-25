import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Umriss eines Klebebands von [a] nach [b] mit gezackten Enden.
Path tapePath(Offset a, Offset b, double width) {
  final delta = b - a;
  final length = delta.distance;
  final path = Path();
  if (length < 1) return path;

  final dir = delta / length;
  final normal = Offset(-dir.dy, dir.dx);
  final half = width / 2;
  final depth = math.min(width * 0.14, length / 4);
  final teeth = math.max(3, (width / 5).round());

  // Zackenlinie quer über ein Ende, von +normal nach -normal.
  List<Offset> edge(Offset center, Offset outward) {
    final pts = <Offset>[];
    for (var i = 0; i <= teeth; i++) {
      final t = i / teeth;
      final across = center + normal * (half - width * t);
      pts.add(i.isOdd ? across + outward * depth : across);
    }
    return pts;
  }

  final start = edge(a, -dir);
  final end = edge(b, dir).reversed.toList();

  path.moveTo(start.first.dx, start.first.dy);
  for (final p in start.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  // Untere Längskante entlang, dann das andere Ende zurück.
  for (final p in end) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// Zeichnet das Klebeband: halbtransparenter Körper plus dezente Randlinien.
void drawTape(
  Canvas canvas,
  List<PointVector> points,
  double width,
  Color color,
) {
  final a = Offset(points.first.dx, points.first.dy);
  final b = Offset(points.last.dx, points.last.dy);
  final path = tapePath(a, b, width);

  canvas.drawPath(path, Paint()..color = color);
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: math.min(1.0, color.a + 0.25)),
  );
}
