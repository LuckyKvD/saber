import 'dart:math' as math;
import 'dart:ui';

enum HeldShapeKind { line, rectangle, circle, ellipse, polygon }

/// Ergebnis der Formerkennung beim Halten des Stifts.
class HeldShape {
  const HeldShape._(
    this.kind, {
    this.outline = const [],
    this.rect,
    this.center,
    this.radius,
  });

  final HeldShapeKind kind;

  /// Linie: 2 Punkte. Polygon/Ellipse/Rechteck: geschlossener Umriss
  /// (erster Punkt wird am Ende nicht wiederholt).
  final List<Offset> outline;
  final Rect? rect;
  final Offset? center;
  final double? radius;

  bool get isClosed => kind != HeldShapeKind.line;

  /// Umriss als geschlossene Punktfolge, bei Bedarf verdichtet (für Striche).
  List<Offset> densePolyline({double step = 6}) {
    if (outline.isEmpty) return const [];
    final result = <Offset>[];
    final n = outline.length;
    final count = isClosed ? n : n - 1;
    for (var i = 0; i < count; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % n];
      final len = (b - a).distance;
      final segments = math.max(1, (len / step).ceil());
      for (var s = 0; s < segments; s++) {
        result.add(Offset.lerp(a, b, s / segments)!);
      }
    }
    result.add(isClosed ? outline.first : outline.last);
    return result;
  }
}

/// Eigene, geometrische Formerkennung (Linie, Dreieck, Viereck, Kreis/Ellipse).
/// Rein rechnerisch, ohne Vorlagen: Ecken stammen aus dem, was gezeichnet wurde.
class ShapeRecognizer {
  const ShapeRecognizer._();

  static HeldShape? recognize(List<Offset> raw) {
    final pts = _dedupe(raw);
    if (pts.length < 6) return null;

    final bounds = _bounds(pts);
    final diag = math.sqrt(
      bounds.width * bounds.width + bounds.height * bounds.height,
    );
    if (diag < 24) return null;

    final length = _pathLength(pts);
    final gap = (pts.first - pts.last).distance;

    // Offener Strich: nur gerade Linie.
    if (gap > 0.22 * length) {
      return _asLine(pts, diag);
    }

    // Geschlossener Strich.
    final loop = _resample(pts, 96);
    final polygon = _fitPolygon(loop, diag);
    final ellipse = _fitEllipse(loop, bounds);

    final polyErr = polygon == null ? double.infinity : polygon.$2;
    final ellErr = ellipse.$2;

    if (polyErr <= ellErr && polyErr < 0.035 * diag) {
      return _polygonResult(polygon!.$1);
    }
    if (ellErr < 0.035 * diag) return ellipse.$1;
    return null;
  }

  static HeldShape? _asLine(List<Offset> pts, double diag) {
    final a = pts.first;
    final b = pts.last;
    final chord = (b - a).distance;
    if (chord < 30) return null;
    var maxDev = 0.0;
    for (final p in pts) {
      maxDev = math.max(maxDev, _distToLine(p, a, b));
    }
    if (maxDev > 0.07 * chord) return null;
    return HeldShape._(HeldShapeKind.line, outline: [a, b]);
  }

  static HeldShape _polygonResult(List<Offset> v) {
    if (v.length == 4 && _isRectangleLike(v)) {
      final rect = _bounds(v);
      // Achsenparallel? Dann sauberes Rechteck, sonst gedrehtes Viereck.
      final axisAligned = _isAxisAligned(v, rect);
      if (axisAligned) {
        return HeldShape._(
          HeldShapeKind.rectangle,
          rect: rect,
          outline: [
            rect.topLeft,
            rect.topRight,
            rect.bottomRight,
            rect.bottomLeft,
          ],
        );
      }
    }
    return HeldShape._(HeldShapeKind.polygon, outline: v);
  }

  static bool _isRectangleLike(List<Offset> v) {
    for (var i = 0; i < 4; i++) {
      final a = v[i];
      final b = v[(i + 1) % 4];
      final c = v[(i + 2) % 4];
      final angle = _angle(b - a, c - b);
      if ((angle - 90).abs() > 14) return false;
    }
    return true;
  }

  static bool _isAxisAligned(List<Offset> v, Rect r) {
    final tol = 0.12 * math.max(r.width, r.height);
    final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
    for (final c in corners) {
      final nearest = v.map((p) => (p - c).distance).reduce(math.min);
      if (nearest > tol) return false;
    }
    return true;
  }

  /// Winkel zwischen Richtungen in Grad (Abbiegewinkel 0..180).
  static double _angle(Offset d1, Offset d2) {
    final cross = d1.dx * d2.dy - d1.dy * d2.dx;
    final dot = d1.dx * d2.dx + d1.dy * d2.dy;
    return math.atan2(cross.abs(), dot) * 180 / math.pi;
  }

  /// Polygon aus der geschlossenen, gleichmäßig abgetasteten Schleife.
  /// Gibt (Ecken, mittlerer Abstand) zurück oder null.
  static (List<Offset>, double)? _fitPolygon(List<Offset> loop, double diag) {
    // Ausgangspunkt: der Punkt, der am weitesten vom Schwerpunkt liegt
    // (garantiert eine Ecke bei Dreieck/Viereck).
    final centroid = _centroid(loop);
    var startIdx = 0;
    var best = -1.0;
    for (var i = 0; i < loop.length; i++) {
      final d = (loop[i] - centroid).distance;
      if (d > best) {
        best = d;
        startIdx = i;
      }
    }
    final rotated = [
      ...loop.sublist(startIdx),
      ...loop.sublist(0, startIdx),
      loop[startIdx],
    ];

    var verts = _rdp(rotated, 0.045 * diag);
    // Schlusspunkt (= Startpunkt) entfernen.
    if (verts.length > 1 && (verts.first - verts.last).distance < 1e-6) {
      verts = verts.sublist(0, verts.length - 1);
    }
    // Fast gerade "Ecken" entfernen.
    var changed = true;
    while (changed && verts.length > 3) {
      changed = false;
      for (var i = 0; i < verts.length; i++) {
        final prev = verts[(i - 1 + verts.length) % verts.length];
        final cur = verts[i];
        final next = verts[(i + 1) % verts.length];
        if (_angle(cur - prev, next - cur) < 25) {
          verts.removeAt(i);
          changed = true;
          break;
        }
      }
    }
    // Sehr nahe Ecken verschmelzen.
    changed = true;
    while (changed && verts.length > 3) {
      changed = false;
      for (var i = 0; i < verts.length; i++) {
        final next = verts[(i + 1) % verts.length];
        if ((verts[i] - next).distance < 0.12 * diag) {
          verts[i] = Offset.lerp(verts[i], next, 0.5)!;
          verts.removeAt((i + 1) % verts.length);
          changed = true;
          break;
        }
      }
    }
    if (verts.length != 3 && verts.length != 4) return null;

    var sum = 0.0;
    for (final p in loop) {
      var d = double.infinity;
      for (var i = 0; i < verts.length; i++) {
        d = math.min(
          d,
          _distToSegment(p, verts[i], verts[(i + 1) % verts.length]),
        );
      }
      sum += d;
    }
    return (verts, sum / loop.length);
  }

  static (HeldShape, double) _fitEllipse(List<Offset> loop, Rect bounds) {
    final c = bounds.center;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    var sum = 0.0;
    for (final p in loop) {
      final u = (p.dx - c.dx) / (rx == 0 ? 1 : rx);
      final v = (p.dy - c.dy) / (ry == 0 ? 1 : ry);
      final r = math.sqrt(u * u + v * v);
      // Abweichung in Bildpunkten, näherungsweise.
      sum += (r - 1).abs() * (rx + ry) / 2;
    }
    final err = sum / loop.length;

    final ratio = math.min(rx, ry) / math.max(rx, ry);
    if (ratio > 0.85) {
      final radius = (rx + ry) / 2;
      return (
        HeldShape._(HeldShapeKind.circle, center: c, radius: radius),
        err,
      );
    }
    final outline = <Offset>[
      for (var i = 0; i < 64; i++)
        Offset(
          c.dx + rx * math.cos(2 * math.pi * i / 64),
          c.dy + ry * math.sin(2 * math.pi * i / 64),
        ),
    ];
    return (HeldShape._(HeldShapeKind.ellipse, outline: outline), err);
  }

  // ---- Hilfsfunktionen ----

  static List<Offset> _dedupe(List<Offset> raw) {
    final out = <Offset>[];
    for (final p in raw) {
      if (!p.dx.isFinite || !p.dy.isFinite) continue;
      if (out.isEmpty || (out.last - p).distance > 0.5) out.add(p);
    }
    return out;
  }

  static Rect _bounds(List<Offset> pts) {
    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static double _pathLength(List<Offset> pts) {
    var sum = 0.0;
    for (var i = 1; i < pts.length; i++) {
      sum += (pts[i] - pts[i - 1]).distance;
    }
    return sum;
  }

  static Offset _centroid(List<Offset> pts) {
    var x = 0.0, y = 0.0;
    for (final p in pts) {
      x += p.dx;
      y += p.dy;
    }
    return Offset(x / pts.length, y / pts.length);
  }

  /// Gleichmäßige Abtastung entlang des Wegs (n Punkte, offener Pfad).
  static List<Offset> _resample(List<Offset> pts, int n) {
    final total = _pathLength(pts);
    if (total == 0) return List.of(pts);
    final step = total / n;
    final out = <Offset>[pts.first];
    var acc = 0.0;
    var prev = pts.first;
    for (var i = 1; i < pts.length; i++) {
      var cur = pts[i];
      var d = (cur - prev).distance;
      while (acc + d >= step && d > 0) {
        final t = (step - acc) / d;
        final q = Offset.lerp(prev, cur, t)!;
        out.add(q);
        prev = q;
        d = (cur - prev).distance;
        acc = 0;
      }
      acc += d;
      prev = cur;
    }
    return out;
  }

  static List<Offset> _rdp(List<Offset> pts, double eps) {
    if (pts.length < 3) return List.of(pts);
    var maxD = 0.0;
    var idx = 0;
    final a = pts.first;
    final b = pts.last;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = (a - b).distance < 1e-6
          ? (pts[i] - a).distance
          : _distToSegment(pts[i], a, b);
      if (d > maxD) {
        maxD = d;
        idx = i;
      }
    }
    if (maxD > eps) {
      final left = _rdp(pts.sublist(0, idx + 1), eps);
      final right = _rdp(pts.sublist(idx), eps);
      return [...left.sublist(0, left.length - 1), ...right];
    }
    return [a, b];
  }

  static double _distToLine(Offset p, Offset a, Offset b) {
    final len = (b - a).distance;
    if (len == 0) return (p - a).distance;
    final cross = (b.dx - a.dx) * (a.dy - p.dy) - (a.dx - p.dx) * (b.dy - a.dy);
    return cross.abs() / len;
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - Offset(a.dx + ab.dx * t, a.dy + ab.dy * t)).distance;
  }
}
