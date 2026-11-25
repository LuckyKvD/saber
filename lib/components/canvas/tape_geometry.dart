import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Anzahl der Klebeband-Muster.
const tapePatternCount = 9;

const tapePatternNames = [
  'Kreuze',
  'Linien',
  'Schachbrett',
  'Punkte',
  'Gitter',
  'Streifen',
  'Herzchen',
  'Wellen',
  'Halbkreise',
];

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
  for (final p in end) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

/// Zeichnet das Klebeband: einfarbig (halbtransparent) oder mit [pattern].
void drawTape(
  Canvas canvas,
  List<PointVector> points,
  double width,
  Color color, {
  int? pattern,
}) {
  final a = Offset(points.first.dx, points.first.dy);
  final b = Offset(points.last.dx, points.last.dy);
  final path = tapePath(a, b, width);

  if (pattern == null || pattern < 0 || pattern >= tapePatternCount) {
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: math.min(1.0, color.a + 0.25)),
    );
    return;
  }

  final delta = b - a;
  final length = delta.distance;
  canvas.save();
  canvas.clipPath(path);
  canvas.translate(a.dx, a.dy);
  canvas.rotate(math.atan2(delta.dy, delta.dx));
  // Leicht transparent, damit Schrift darunter noch zu ahnen ist.
  canvas.saveLayer(
    Rect.fromLTRB(-width, -width, length + width, width),
    Paint()..color = const Color(0xE6FFFFFF),
  );
  paintTapePattern(canvas, pattern, length, width);
  canvas.restore();
  canvas.restore();
}

/// Malt Muster [pattern] in ein Band der Länge [length] und Breite [width].
/// Koordinaten: x entlang des Bands (0..length), y quer (-width/2..width/2).
void paintTapePattern(Canvas canvas, int pattern, double length, double width) {
  final half = width / 2;
  final area = Rect.fromLTRB(-width, -half, length + width, half);
  final fill = Paint();
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void bg(int argb) => canvas.drawRect(area, fill..color = Color(argb));
  final x0 = -width, x1 = length + width;

  switch (pattern) {
    case 0: // Kreuze
      bg(0xFFBFE3F2);
      line
        ..color = const Color(0xFF2E5A88)
        ..strokeWidth = math.max(1, width * 0.025);
      final step = width * 0.16, r = width * 0.035;
      var row = 0;
      for (var y = -half + step / 2; y < half; y += step) {
        for (var x = x0 + (row.isOdd ? 0 : 0); x < x1; x += step) {
          canvas.drawLine(Offset(x - r, y), Offset(x + r, y), line);
          canvas.drawLine(Offset(x, y - r), Offset(x, y + r), line);
        }
        row++;
      }
    case 1: // Linien
      bg(0xFFF6F1D8);
      line
        ..color = const Color(0xFF8A8A7A)
        ..strokeWidth = math.max(1, width * 0.015);
      final step = width / 9;
      for (var y = -half + step / 2; y < half; y += step) {
        canvas.drawLine(Offset(x0, y), Offset(x1, y), line);
      }
    case 2: // Schachbrett
      final s = width / 3;
      var col = 0;
      for (var x = x0; x < x1; x += s) {
        for (var r = 0; r < 3; r++) {
          final dark = (col + r).isEven;
          canvas.drawRect(
            Rect.fromLTWH(x, -half + r * s, s + 0.5, s + 0.5),
            fill..color = Color(dark ? 0xFF8ECFC4 : 0xFFD0D8F0),
          );
        }
        col++;
      }
    case 3: // Punkte
      bg(0xFFC4857B);
      fill.color = const Color(0xFFFFFFFF);
      final step = width * 0.2;
      var row = 0;
      for (var y = -half + step / 2; y < half; y += step) {
        for (
          var x = x0 + (row.isOdd ? step / 2 : 0);
          x < x1;
          x += step
        ) {
          canvas.drawCircle(Offset(x, y), width * 0.04, fill);
        }
        row++;
      }
    case 4: // Gitter
      bg(0xFFF8C8D8);
      line
        ..color = const Color(0xFFFFE0C0)
        ..strokeWidth = math.max(1.5, width * 0.06);
      final step = width / 3;
      for (var y = -half + step / 2; y < half; y += step) {
        canvas.drawLine(Offset(x0, y), Offset(x1, y), line);
      }
      for (var x = x0; x < x1; x += step) {
        canvas.drawLine(Offset(x, -half), Offset(x, half), line);
      }
    case 5: // Streifen quer
      bg(0xFF3F66B0);
      line
        ..color = const Color(0xFF8FA8D8)
        ..strokeWidth = math.max(1, width * 0.03);
      final step = width * 0.08;
      for (var x = x0; x < x1; x += step) {
        canvas.drawLine(Offset(x, -half), Offset(x, half), line);
      }
    case 6: // Herzchen (kleine V-Zeichen)
      bg(0xFF4A5578);
      line
        ..color = const Color(0xFFFF8FB0)
        ..strokeWidth = math.max(1.2, width * 0.04);
      final step = width * 0.26, r = width * 0.06;
      var row = 0;
      for (var y = -half + step / 2; y < half; y += step) {
        for (
          var x = x0 + (row.isOdd ? step / 2 : 0);
          x < x1;
          x += step
        ) {
          canvas.drawPath(
            Path()
              ..moveTo(x - r, y - r)
              ..lineTo(x, y + r)
              ..lineTo(x + r, y - r),
            line,
          );
        }
        row++;
      }
    case 7: // Wellen
      bg(0xFF5B3A7A);
      line
        ..color = const Color(0xFFFF9BB0)
        ..strokeWidth = math.max(1.2, width * 0.045);
      final amp = width * 0.07, wave = width * 0.5;
      for (final y0 in [-half * 0.55, 0.0, half * 0.55]) {
        final path = Path()..moveTo(x0, y0);
        for (var x = x0; x <= x1; x += 2) {
          path.lineTo(x, y0 + amp * math.sin((x - x0) / wave * 2 * math.pi));
        }
        canvas.drawPath(path, line);
      }
    case 8: // Halbkreise
      bg(0xFF0F5C4A);
      fill.color = const Color(0xFFE8A93A);
      final step = width * 0.28, r = width * 0.1;
      var row = 0;
      for (var y = -half + step / 2; y < half + step; y += step) {
        for (
          var x = x0 + (row.isOdd ? step / 2 : 0);
          x < x1;
          x += step
        ) {
          canvas.drawArc(
            Rect.fromCircle(center: Offset(x, y), radius: r),
            0,
            math.pi,
            true,
            fill,
          );
        }
        row++;
      }
  }
}
