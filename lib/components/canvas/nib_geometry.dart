import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Geometrie einer flachen Kalligrafie-Feder (PROTOTYP).
///
/// Die Feder ist ein schmales Rechteck der Länge [size] im Winkel [angle].
/// Der Strich ist die Fläche, die dieses Rechteck beim Schreiben überstreicht.
/// Dadurch ist die Linie dünn, wenn sich der Stift entlang der Federkante
/// bewegt, und breit, wenn er quer dazu zieht.

/// Dicke der Federkante im Verhältnis zur Federbreite.
const double _edgeRatio = 0.08;

/// Leichte Glättung der Rohpunkte (3-Punkt-Mittel, Endpunkte bleiben).
List<Offset> _smooth(List<Offset> pts) {
  if (pts.length < 3) return pts;
  return [
    pts.first,
    for (int i = 1; i < pts.length - 1; i++)
      Offset(
        (pts[i - 1].dx + 2 * pts[i].dx + pts[i + 1].dx) / 4,
        (pts[i - 1].dy + 2 * pts[i].dy + pts[i + 1].dy) / 4,
      ),
    pts.last,
  ];
}

List<Offset> _nibCorners(Offset c, Offset h, Offset v) => [
  c + h + v,
  c + h - v,
  c - h + v,
  c - h - v,
];

/// Konvexe Hülle (Monotone Chain), immer gegen den Uhrzeigersinn.
List<Offset> _hull(List<Offset> input) {
  final pts = [...input]
    ..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  if (pts.length < 3) return pts;

  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

  final lower = <Offset>[];
  for (final p in pts) {
    while (lower.length >= 2 &&
        cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Offset>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 &&
        cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

/// Liefert für jedes Teilstück des Strichs ein konvexes Polygon.
List<List<Offset>> nibHulls(
  List<Offset> points, {
  required double size,
  required double angle,
}) {
  final pts = _smooth([
    for (final p in points)
      if (p.isFinite) Offset(p.dx, p.dy),
  ]);
  if (pts.isEmpty) return const [];

  final half = size / 2;
  final h = Offset(math.cos(angle) * half, math.sin(angle) * half);
  final v = Offset(-math.sin(angle) * half * _edgeRatio * 2,
      math.cos(angle) * half * _edgeRatio * 2);

  if (pts.length == 1) {
    return [_hull(_nibCorners(pts.first, h, v))];
  }

  final hulls = <List<Offset>>[];
  for (int i = 0; i < pts.length - 1; i++) {
    final hull = _hull([
      ..._nibCorners(pts[i], h, v),
      ..._nibCorners(pts[i + 1], h, v),
    ]);
    if (hull.length >= 3) hulls.add(hull);
  }
  return hulls;
}

/// Ein [Path] aus allen Teilpolygonen. Alle haben dieselbe Umlaufrichtung,
/// daher ergibt die Nicht-Null-Füllregel die saubere Vereinigung.
Path nibPath(
  List<Offset> points, {
  required double size,
  required double angle,
}) {
  final path = Path()..fillType = PathFillType.nonZero;
  for (final hull in nibHulls(points, size: size, angle: angle)) {
    path.addPolygon(hull, true);
  }
  return path;
}
