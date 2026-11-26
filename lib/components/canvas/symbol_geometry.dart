import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';

/// Muster-Stift: Statt einer Linie setzt der Stift viele kleine Zeichen
/// entlang des Strichs. Der Strichstil ist `Stroke.styleSymbolBase + Nummer`.
const symbolBrushNames = [
  'Striche',
  'Punkte',
  'Sterne',
  'Herzen',
  'Kreuze',
  'Ausrufezeichen',
  'Doppelstriche',
  'Pfeile',
];

Path _heart(double g) {
  final path = Path();
  for (var i = 0; i <= 24; i++) {
    final t = i / 24 * 2 * pi;
    final x = 16 * pow(sin(t), 3).toDouble();
    final y =
        13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t);
    final p = Offset(x / 34 * g, -y / 34 * g + g * 0.03);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

Path _star(double g) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final r = i.isEven ? g * 0.5 : g * 0.22;
    final a = -pi / 2 + i * pi / 5;
    final p = Offset(r * cos(a), r * sin(a));
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  return path..close();
}

/// [symbol]: 1 Punkte, 2 Sterne, 3 Herzen, 4 Kreuze, 5 Ausrufezeichen,
/// 6 Doppelstriche, 7 Pfeile.
void drawSymbolBrush(
  Canvas canvas,
  List<PointVector> points,
  double size,
  Color color,
  int symbol,
) {
  if (points.isEmpty) return;
  final g = max(size * 1.8, 6.0);
  final spacing = g * 1.35;
  final fill = Paint()
    ..isAntiAlias = true
    ..color = color;
  final line = Paint()
    ..isAntiAlias = true
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = max(g * 0.2, 1.2);

  void put(Offset at, double angle) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    switch (symbol) {
      case 1:
        canvas.drawCircle(Offset.zero, g * 0.32, fill);
      case 2:
        canvas.drawPath(_star(g), fill);
      case 3:
        canvas.drawPath(_heart(g), fill);
      case 4:
        canvas.drawLine(Offset(-g * 0.35, -g * 0.35), Offset(g * 0.35, g * 0.35), line);
        canvas.drawLine(Offset(-g * 0.35, g * 0.35), Offset(g * 0.35, -g * 0.35), line);
      case 5:
        canvas.drawLine(Offset(0, -g * 0.5), Offset(0, g * 0.12), line);
        canvas.drawCircle(Offset(0, g * 0.4), g * 0.1, fill);
      case 6:
        canvas.rotate(angle);
        canvas.drawLine(Offset(-g * 0.14, -g * 0.4), Offset(-g * 0.14, g * 0.4), line);
        canvas.drawLine(Offset(g * 0.14, -g * 0.4), Offset(g * 0.14, g * 0.4), line);
      default:
        canvas.rotate(angle);
        final p = Path()
          ..moveTo(-g * 0.25, -g * 0.35)
          ..lineTo(g * 0.25, 0)
          ..lineTo(-g * 0.25, g * 0.35);
        canvas.drawPath(p, line..style = PaintingStyle.stroke);
    }
    canvas.restore();
  }

  if (points.length == 1) {
    put(points.first, 0);
    return;
  }
  var carried = 0.0;
  var prev = points.first;
  put(prev, (points[1] - prev).direction);
  for (final p in points.skip(1)) {
    final seg = p - prev;
    final len = seg.distance;
    if (len < 0.01) continue;
    final angle = seg.direction;
    var d = spacing - carried;
    while (d <= len) {
      put(prev + seg * (d / len), angle);
      d += spacing;
    }
    carried = len - (d - spacing);
    prev = p;
  }
}

/// Fineliner: gleichmäßige, harte Linie mit eckigen Enden (technischer Stil).
void drawLiner(
  Canvas canvas,
  List<PointVector> points,
  double size,
  Color color,
) {
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 1; i < points.length - 1; i++) {
    final mid = Offset(
      (points[i].dx + points[i + 1].dx) / 2,
      (points[i].dy + points[i + 1].dy) / 2,
    );
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);
  canvas.drawPath(
    path,
    Paint()
      ..isAntiAlias = true
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..strokeWidth = size,
  );
}
