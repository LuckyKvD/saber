import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Eine Linie der Tabelle: [axis] 1 = waagerecht, 2 = senkrecht.
class TableLine {
  const TableLine(this.axis, this.points);

  final int axis;
  final List<Offset> points;
}

/// Feder: Erzeugt Tabellenlinien, die wie von Hand gezogen aussehen
/// (leicht wellig, schief und mit kleinem Überstand an den Enden).
abstract class TableBuilder {
  static const horizontal = 1;
  static const vertical = 2;

  /// Handgezogene Linie von [a] nach [b].
  static List<Offset> wobblyLine(
    Offset a,
    Offset b,
    math.Random rng, {
    double amplitude = 1.0,
    double step = 8,
  }) {
    final dir = b - a;
    final len = dir.distance;
    if (len < 1) return [a, b];
    final unit = dir / len;
    final normal = Offset(-unit.dy, unit.dx);
    final start = a - unit * (1 + rng.nextDouble() * 4);
    final end = b + unit * (1 + rng.nextDouble() * 4);
    final total = (end - start).distance;
    final n = math.max(2, (total / step).ceil());
    final p1 = rng.nextDouble() * 2 * math.pi;
    final p2 = rng.nextDouble() * 2 * math.pi;
    final f1 = 1.0 + rng.nextDouble() * 1.5;
    final f2 = 3.0 + rng.nextDouble() * 3;
    final tilt = (rng.nextDouble() - 0.5) * amplitude * 3;
    return [
      for (var i = 0; i <= n; i++)
        () {
          final t = i / n;
          final off =
              amplitude *
                  (0.6 * math.sin(2 * math.pi * f1 * t + p1) +
                      0.4 * math.sin(2 * math.pi * f2 * t + p2)) +
              tilt * (t - 0.5);
          return start + unit * (total * t) + normal * off;
        }(),
    ];
  }

  /// Neue Tabelle: [cols] × [rows] Zellen der Größe [cellW] × [cellH],
  /// linke obere Ecke bei [origin].
  static List<TableLine> grid({
    required Offset origin,
    required int cols,
    required int rows,
    required double cellW,
    required double cellH,
    required math.Random rng,
    double amplitude = 1.0,
  }) {
    final w = cols * cellW;
    final h = rows * cellH;
    return [
      for (var r = 0; r <= rows; r++)
        TableLine(
          horizontal,
          wobblyLine(
            origin + Offset(0, r * cellH),
            origin + Offset(w, r * cellH),
            rng,
            amplitude: amplitude,
          ),
        ),
      for (var c = 0; c <= cols; c++)
        TableLine(
          vertical,
          wobblyLine(
            origin + Offset(c * cellW, 0),
            origin + Offset(c * cellW, h),
            rng,
            amplitude: amplitude,
          ),
        ),
    ];
  }

  /// Lage der Linien einer bestehenden Tabelle.
  static ({List<double> ys, List<double> xs})? geometry(
    Iterable<TableLine> lines,
  ) {
    final ys = <double>[];
    final xs = <double>[];
    for (final l in lines) {
      if (l.points.isEmpty) continue;
      if (l.axis == horizontal) {
        ys.add(l.points.map((p) => p.dy).reduce((a, b) => a + b) /
            l.points.length);
      } else if (l.axis == vertical) {
        xs.add(l.points.map((p) => p.dx).reduce((a, b) => a + b) /
            l.points.length);
      }
    }
    final cy = _cluster(ys);
    final cx = _cluster(xs);
    if (cy.length < 2 || cx.length < 2) return null;
    return (ys: cy, xs: cx);
  }

  /// Fasst Werte zusammen, die weniger als [tolerance] auseinanderliegen
  /// (Teilstücke derselben Tabellenlinie).
  static List<double> _cluster(List<double> values, {double tolerance = 6}) {
    final sorted = [...values]..sort();
    final out = <double>[];
    var group = <double>[];
    for (final v in sorted) {
      if (group.isNotEmpty && v - group.last > tolerance) {
        out.add(group.reduce((a, b) => a + b) / group.length);
        group = [];
      }
      group.add(v);
    }
    if (group.isNotEmpty) {
      out.add(group.reduce((a, b) => a + b) / group.length);
    }
    return out;
  }

  /// Neue Linien, die [addRows] Zeilen unten und [addCols] Spalten rechts
  /// an die Tabelle [existing] anfügen. Gibt eine leere Liste zurück, wenn
  /// die Tabelle nicht erkannt wird.
  static List<TableLine> extend(
    Iterable<TableLine> existing, {
    required int addRows,
    required int addCols,
    required math.Random rng,
    double amplitude = 1.0,
  }) {
    final g = geometry(existing);
    if (g == null) return const [];
    final ys = [...g.ys];
    final xs = [...g.xs];
    final rowH = ys[ys.length - 1] - ys[ys.length - 2];
    final colW = xs[xs.length - 1] - xs[xs.length - 2];
    final out = <TableLine>[];

    for (var k = 0; k < addRows; k++) {
      final top = ys.last;
      final y = top + rowH;
      out.add(
        TableLine(
          horizontal,
          wobblyLine(Offset(xs.first, y), Offset(xs.last, y), rng,
              amplitude: amplitude),
        ),
      );
      for (final x in xs) {
        out.add(
          TableLine(
            vertical,
            wobblyLine(Offset(x, top), Offset(x, y), rng,
                amplitude: amplitude),
          ),
        );
      }
      ys.add(y);
    }

    for (var k = 0; k < addCols; k++) {
      final left = xs.last;
      final x = left + colW;
      out.add(
        TableLine(
          vertical,
          wobblyLine(Offset(x, ys.first), Offset(x, ys.last), rng,
              amplitude: amplitude),
        ),
      );
      for (final y in ys) {
        out.add(
          TableLine(
            horizontal,
            wobblyLine(Offset(left, y), Offset(x, y), rng,
                amplitude: amplitude),
          ),
        );
      }
      xs.add(x);
    }
    return out;
  }
}
