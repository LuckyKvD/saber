import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Glitzerstift: Funkeln auf und neben dem Strich. Die Verteilung ist aus
/// den Punkten abgeleitet (kein Zufall), damit der Strich immer gleich aussieht.
double _rand(int n, int salt) {
  var x = (n * 73856093) ^ (salt * 19349663);
  x &= 0x7FFFFFFF;
  x = ((x ^ (x >> 13)) * 1274126177) & 0x7FFFFFFF;
  x = x ^ (x >> 16);
  return (x & 0xFFFF) / 65535.0;
}

void _star(Canvas canvas, Offset c, double r, Paint paint) {
  final path = Path()
    ..moveTo(c.dx, c.dy - r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
    ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
    ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
    ..close();
  canvas.drawPath(path, paint);
}

/// Zeichnet Glanzlicht und Funken über den bereits gezeichneten Strich.
void drawGlitter(
  Canvas canvas,
  List<PointVector> points,
  double size,
  Color base,
) {
  if (points.isEmpty) return;

  // Glanzlinie leicht versetzt (Gel-Look).
  if (points.length >= 2) {
    final gloss = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      gloss.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      gloss.shift(Offset(-size * 0.12, -size * 0.12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = max(size * 0.22, 1)
        ..color = Color.lerp(base, Colors.white, 0.65)!.withValues(alpha: 0.55),
    );
  }

  final palette = [
    Colors.white,
    Color.lerp(base, Colors.white, 0.7)!,
    const Color(0xFFFFE9A8),
    const Color(0xFFFFFFFF),
  ];
  final spacing = max(size * 0.55, 2.5);
  final paint = Paint()..isAntiAlias = true;

  var carry = 0.0;
  var counter = 0;
  void sparkle(Offset pos, Offset dir) {
    counter++;
    final normal = Offset(-dir.dy, dir.dx);
    final side = (_rand(counter, 1) - 0.5) * size * 1.05;
    final along = (_rand(counter, 2) - 0.5) * spacing;
    final c = pos + normal * side + dir * along;
    final r = size * (0.06 + 0.16 * _rand(counter, 3));
    paint.color = palette[(_rand(counter, 4) * palette.length).floor() %
            palette.length]
        .withValues(alpha: 0.75 + 0.25 * _rand(counter, 5));
    if (_rand(counter, 6) > 0.78) {
      _star(canvas, c, r * 2.8 + 1, paint);
    } else {
      canvas.drawCircle(c, max(r, 0.5), paint);
    }
  }

  if (points.length == 1) {
    sparkle(Offset(points.first.dx, points.first.dy), const Offset(1, 0));
    return;
  }

  for (var i = 1; i < points.length; i++) {
    final a = Offset(points[i - 1].dx, points[i - 1].dy);
    final b = Offset(points[i].dx, points[i].dy);
    final delta = b - a;
    final len = delta.distance;
    if (len == 0) continue;
    final dir = delta / len;
    var d = spacing - carry;
    while (d <= len) {
      sparkle(a + dir * d, dir);
      d += spacing;
    }
    carry = len - (d - spacing);
  }
}

/// Regenbogen-Glitzer: Die Farbe wandert entlang des Strichs durch den
/// Farbkreis. Funkeln kommt anschließend über [drawGlitter].
void drawRainbow(Canvas canvas, List<PointVector> points, double size) {
  if (points.isEmpty) return;
  final period = max(size * 16, 60.0);
  if (points.length == 1) {
    canvas.drawCircle(
      points.first,
      size / 2,
      Paint()
        ..isAntiAlias = true
        ..color = HSVColor.fromAHSV(1, 300, 0.8, 1).toColor(),
    );
    return;
  }
  final paint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = size;
  var travelled = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    travelled += (b - a).distance;
    final hue = (travelled / period * 360) % 360;
    paint.color = HSVColor.fromAHSV(1, hue, 0.8, 1).toColor();
    canvas.drawLine(a, b, paint);
  }
}
