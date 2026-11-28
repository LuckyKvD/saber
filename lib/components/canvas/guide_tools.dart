import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

enum GuideKind { ruler, protractor, triangle, compass }

/// Ein Zeichenhilfsmittel (Lineal oder Winkelmesser) auf einer Seite.
class GuideShape {
  GuideShape(this.kind, this.center);

  final GuideKind kind;
  Offset center;

  /// Ungerasteter Drehwinkel im Bogenmaß (0 = waagerecht).
  double rawAngle = 0;

  /// Nur Winkelmesser: Vollkreis statt Halbkreis.
  bool full = false;

  static const rulerLengthCm = 30.0;
  static const rulerWidthCm = 4.0;
  static const protractorRadiusCm = 6.0;
  static const protractorInnerCm = 3.4;

  /// Streifen unter der Grundlinie des Halbkreis-Winkelmessers.
  static const protractorStripCm = 1.0;

  /// Geodreieck: gleichschenklig-rechtwinklig, Hypotenuse unten.
  static const triangleHypCm = 16.0;
  static const triangleHeightCm = 8.0;

  /// Abstand des Inkreismittelpunkts von der Hypotenuse.
  static final triangleInradiusCm =
      (2 * triangleHeightCm * math.sqrt2 - triangleHypCm) / 2;

  /// Nur Zirkel: eingestellter Radius.
  double radiusCm = 5;

  /// Angezeigter Winkel: rastet nahe an Vielfachen von 45 Grad ein,
  /// sonst frei.
  double get angle {
    if (kind == GuideKind.compass) return rawAngle;
    final deg = rawAngle * 180 / math.pi;
    final snapped = (deg / 45).roundToDouble() * 45;
    return (deg - snapped).abs() < 1.5 ? snapped * math.pi / 180 : rawAngle;
  }

  /// Kantenwinkel in Grad, 0 bis unter 180.
  double get degrees {
    final deg = (angle * 180 / math.pi) % 180;
    final d = deg < 0 ? deg + 180 : deg;
    return d >= 179.95 ? 0 : d;
  }

  String get degreesLabel {
    final d = degrees;
    if ((d - d.round()).abs() < 0.05) return '${d.round() % 180}°';
    return '${d.toStringAsFixed(1).replaceAll('.', ',')}°';
  }

  /// Seitenpunkt in Koordinaten des Hilfsmittels: u entlang der Grundkante,
  /// v quer dazu (nach unten positiv, beim Winkelmesser liegt der Bogen bei v < 0).
  (double, double) toLocal(Offset p) {
    final d = p - center;
    final a = angle;
    final c = math.cos(a);
    final s = math.sin(a);
    return (d.dx * c + d.dy * s, -d.dx * s + d.dy * c);
  }

  Offset toPage(double u, double v) {
    final a = angle;
    final c = math.cos(a);
    final s = math.sin(a);
    return center + Offset(u * c - v * s, u * s + v * c);
  }

  bool hitBody(Offset p, double ppc) {
    final (u, v) = toLocal(p);
    switch (kind) {
      case GuideKind.ruler:
        return u.abs() <= rulerLengthCm * ppc / 2 &&
            v.abs() <= rulerWidthCm * ppc / 2;
      case GuideKind.protractor:
        final r = protractorRadiusCm * ppc;
        if (full) return math.sqrt(u * u + v * v) <= r;
        if (v <= 0) return math.sqrt(u * u + v * v) <= r;
        return v <= protractorStripCm * ppc && u.abs() <= r;
      case GuideKind.triangle:
        final h = triangleHeightCm * ppc;
        if (v > 0 || v < -h) return false;
        return u.abs() <= triangleHypCm * ppc / 2 + v;
      case GuideKind.compass:
        // Nur Nadelspitze und Griff greifen (der Kreis selbst bleibt frei).
        if (math.sqrt(u * u + v * v) <= 1.5 * ppc) return true;
        return (Offset(u, v) - handleLocal(ppc)).distance <=
            handleRadius(ppc) + 0.3 * ppc;
    }
  }

  /// Drehgriff: Lineal nahe dem rechten Ende, Geodreieck in der Mitte,
  /// Zirkel am Kreisrand (stellt Radius und Richtung ein).
  Offset handleLocal(double ppc) {
    switch (kind) {
      case GuideKind.ruler:
        return Offset(rulerLengthCm * ppc / 2 - 1.8 * ppc, 0);
      case GuideKind.triangle:
        return Offset(0, -triangleInradiusCm * ppc);
      case GuideKind.compass:
        return Offset(radiusCm * ppc, 0);
      case GuideKind.protractor:
        return Offset.zero;
    }
  }

  double handleRadius(double ppc) => kind == GuideKind.ruler ? 1.2 * ppc : 1.0 * ppc;

  bool hitHandle(Offset p, double ppc) {
    if (kind == GuideKind.protractor) return false;
    final (u, v) = toLocal(p);
    return (Offset(u, v) - handleLocal(ppc)).distance <=
        handleRadius(ppc) + 0.3 * ppc;
  }
}

/// Eine Kante, an der der Stift einrastet.
class GuideEdge {
  const GuideEdge(this.shape, this.type);

  final GuideShape shape;

  /// 0 Lineal oben, 1 Lineal unten, 2 Winkelmesser-Grundlinie,
  /// 3 Winkelmesser-Außenbogen, 4 Winkelmesser-Innenbogen,
  /// 5 Geodreieck-Hypotenuse, 6/7 Geodreieck-Schenkel, 8 Zirkelkreis.
  final int type;
}

/// Zustand der Zeichenhilfen. Gehört zu einer Notiz und einer Seite,
/// wird nicht gespeichert und erscheint nicht in Exporten.
class Guides {
  const Guides._();

  static Object? owner;
  static int pageIndex = 0;

  /// Seitengrößen der Notiz, damit Hilfsmittel auf andere Seiten wechseln können.
  static List<Size> pageSizes = const [];
  static GuideShape? ruler;
  static GuideShape? protractor;
  static GuideShape? triangle;
  static GuideShape? compass;

  /// Alle sichtbaren Hilfsmittel.
  static List<GuideShape> get all => [
    ?ruler,
    ?protractor,
    ?triangle,
    ?compass,
  ];

  /// Wird gesetzt, solange ein Finger ein Hilfsmittel hält.
  /// Dann bewegt sich die Seite nicht mit.
  static bool grabbing = false;

  static final notifier = _GuideNotifier();

  /// Annahme: Die Seitenbreite entspricht der Breite von A4 (21 cm).
  static double pxPerCm(Size pageSize) => pageSize.width / 21;

  static bool isActiveFor(Object coreInfo, int index) =>
      owner != null &&
      identical(owner, coreInfo) &&
      index == pageIndex &&
      anyVisible;

  /// Wo steht das Hilfsmittel auf Seite [index]? `null` = dort nicht zeichnen.
  /// Auf der Besitzerseite 0, auf der Nachbarseite der Versatz, damit das
  /// Hilfsmittel beim Ziehen über den Seitenrand auf beiden Seiten sichtbar ist.
  static double? offsetFor(Object coreInfo, int index) {
    if (owner == null || !identical(owner, coreInfo) || !anyVisible) {
      return null;
    }
    if (index == pageIndex) return 0;
    if (spread && index == partnerOf(pageIndex)) return 0;
    if (!verticalPages) return null;
    if (index == pageIndex - 1 && index >= 0 && index < pageSizes.length) {
      return pageSizes[index].height;
    }
    if (index == pageIndex + 1 &&
        pageIndex < pageSizes.length &&
        index < pageSizes.length) {
      return -pageSizes[pageIndex].height;
    }
    return null;
  }

  /// Doppelblatt (Buch, Querformat): Seite 1 allein rechts, dann 2/3, 4/5 …
  static bool spread = false;

  /// Die andere Seite des Doppelblatts (null, wenn die Seite allein steht).
  static int? partnerOf(int index) {
    if (!spread || index <= 0) return null;
    final p = index.isOdd ? index + 1 : index - 1;
    return p >= 0 && p < pageSizes.length ? p : null;
  }

  /// Seitlicher Versatz, mit dem das Hilfsmittel auf der Partnerseite liegt.
  static double offsetXFor(Object coreInfo, int index) {
    if (owner == null || !identical(owner, coreInfo)) return 0;
    if (index == pageIndex || index != partnerOf(pageIndex)) return 0;
    if (pageIndex >= pageSizes.length) return 0;
    // Besitzer links (ungerade): Partner rechts, Hilfsmittel liegt links davon.
    return pageIndex.isOdd
        ? -pageSizes[pageIndex].width
        : pageSizes[index].width;
  }

  static bool get anyVisible => all.isNotEmpty;

  static void _claim(Object coreInfo, int index) {
    if (owner != null && (!identical(owner, coreInfo) || pageIndex != index)) {
      ruler = null;
      protractor = null;
      triangle = null;
      compass = null;
    }
    owner = coreInfo;
    pageIndex = index;
  }

  static void toggleRuler(Object coreInfo, int index, Size pageSize) {
    _claim(coreInfo, index);
    ruler = ruler == null
        ? GuideShape(
            GuideKind.ruler,
            Offset(pageSize.width / 2, pageSize.height * 0.35),
          )
        : null;
    _afterChange();
  }

  /// Aus -> Halbkreis -> Vollkreis -> Aus.
  static void cycleProtractor(Object coreInfo, int index, Size pageSize) {
    _claim(coreInfo, index);
    final p = protractor;
    if (p == null) {
      protractor = GuideShape(
        GuideKind.protractor,
        Offset(pageSize.width / 2, pageSize.height * 0.6),
      );
    } else if (!p.full) {
      p.full = true;
    } else {
      protractor = null;
    }
    _afterChange();
  }

  static void toggleTriangle(Object coreInfo, int index, Size pageSize) {
    _claim(coreInfo, index);
    triangle = triangle == null
        ? GuideShape(
            GuideKind.triangle,
            Offset(pageSize.width / 2, pageSize.height * 0.45),
          )
        : null;
    _afterChange();
  }

  static void toggleCompass(Object coreInfo, int index, Size pageSize) {
    _claim(coreInfo, index);
    compass = compass == null
        ? GuideShape(
            GuideKind.compass,
            Offset(pageSize.width / 2, pageSize.height * 0.4),
          )
        : null;
    _afterChange();
  }

  static void _afterChange() {
    if (!anyVisible) {
      owner = null;
      grabbing = false;
    }
    notifier.ping();
  }

  static void clear() {
    owner = null;
    ruler = null;
    protractor = null;
    triangle = null;
    compass = null;
    grabbing = false;
    notifier.ping();
  }

  /// Welches Hilfsmittel liegt unter dem Punkt? Der Winkelmesser liegt oben.
  static GuideShape? pick(Offset p, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    for (final shape in [compass, triangle, protractor, ruler]) {
      if (shape != null && shape.hitBody(p, ppc)) return shape;
    }
    return null;
  }

  /// Nur bei vertikal untereinander liegenden Seiten wechselt ein Hilfsmittel
  /// beim Ziehen auf die Nachbarseite.
  static bool verticalPages = true;

  /// Wie weit ein Hilfsmittel beim Ziehen über den Seitenrand hinaus darf
  /// (nur dort, wo eine Nachbarseite existiert).
  static double _overshoot(Size pageSize) => 8 * pxPerCm(pageSize);

  static void moveBy(GuideShape shape, Offset delta, Size pageSize) {
    final partner = partnerOf(pageIndex);
    final canRight = partner != null && pageIndex.isOdd;
    final canLeft = partner != null && pageIndex.isEven;
    final canUp = verticalPages && pageIndex > 0;
    final canDown =
        verticalPages && pageIndex + 1 < pageSizes.length;
    final over = _overshoot(pageSize);
    shape.center = Offset(
      (shape.center.dx + delta.dx)
          .clamp(canLeft ? -over : 0, pageSize.width + (canRight ? over : 0))
          .toDouble(),
      (shape.center.dy + delta.dy)
          .clamp(canUp ? -over : 0, pageSize.height + (canDown ? over : 0))
          .toDouble(),
    );
  }

  /// Beim Loslassen: Liegt der Mittelpunkt außerhalb der Seite, wandert das
  /// Hilfsmittel (und sein Partner) auf die Nachbarseite.
  static void settle() {
    if (spread && anyVisible) {
      final partner = partnerOf(pageIndex);
      if (partner != null && pageIndex < pageSizes.length) {
        final lead = all.first;
        final size = pageSizes[pageIndex];
        double? shift;
        if (pageIndex.isOdd && lead.center.dx > size.width) {
          shift = -size.width;
        } else if (pageIndex.isEven && lead.center.dx < 0) {
          shift = pageSizes[partner].width;
        }
        if (shift != null) {
          final target = pageSizes[partner];
          for (final shape in all) {
            if (shape == null) continue;
            shape.center = Offset(
              (shape.center.dx + shift).clamp(0, target.width).toDouble(),
              shape.center.dy.clamp(0, target.height).toDouble(),
            );
          }
          pageIndex = partner;
          grabbing = false;
          notifier.ping();
        }
      }
      return;
    }
    if (!verticalPages || !anyVisible) return;
    if (pageIndex < 0 || pageIndex >= pageSizes.length) return;
    final lead = all.first;
    final dy = lead.center.dy;
    final size = pageSizes[pageIndex];
    var shift = 0.0;
    var next = pageIndex;
    if (dy < 0 && pageIndex > 0) {
      next = pageIndex - 1;
      shift = pageSizes[next].height;
    } else if (dy > size.height && pageIndex + 1 < pageSizes.length) {
      next = pageIndex + 1;
      shift = -size.height;
    } else {
      return;
    }
    final target = pageSizes[next];
    for (final shape in all) {
      if (shape == null) continue;
      shape.center = Offset(
        shape.center.dx.clamp(0, target.width).toDouble(),
        (shape.center.dy + shift).clamp(0, target.height).toDouble(),
      );
    }
    pageIndex = next;
    grabbing = false;
    notifier.ping();
  }

  /// Hilfsmittel auf die Seite verschieben, die gerade im Bild ist.
  static void moveToPage(int index) {
    if (!anyVisible || index == pageIndex) return;
    // Doppelblatt: beide Seiten sind im Bild, das Hilfsmittel bleibt.
    if (spread && index == partnerOf(pageIndex)) return;
    if (index < 0 || index >= pageSizes.length) return;
    if (pageIndex >= pageSizes.length) return;
    final old = pageSizes[pageIndex];
    final size = pageSizes[index];
    for (final shape in all) {
      if (shape == null) continue;
      shape.center = Offset(
        shape.center.dx.clamp(0, size.width).toDouble(),
        (shape.center.dy / old.height * size.height)
            .clamp(0, size.height)
            .toDouble(),
      );
    }
    pageIndex = index;
    grabbing = false;
    notifier.ping();
  }

  /// Nächstliegende Kante in Reichweite des Stifts.
  static GuideEdge? edgeNear(Offset p, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    const reach = 30.0;
    GuideEdge? best;
    var bestDistance = reach;

    final r = ruler;
    if (r != null) {
      final (u, v) = r.toLocal(p);
      final half = GuideShape.rulerWidthCm * ppc / 2;
      if (u.abs() <= GuideShape.rulerLengthCm * ppc / 2 + reach) {
        final d = (v.abs() - half).abs();
        if (d < bestDistance) {
          bestDistance = d;
          best = GuideEdge(r, v < 0 ? 0 : 1);
        }
      }
    }
    final pr = protractor;
    if (pr != null) {
      final (u, v) = pr.toLocal(p);
      final radius = GuideShape.protractorRadiusCm * ppc;
      if (u.abs() <= radius + reach) {
        final d = v.abs();
        if (d < bestDistance) {
          bestDistance = d;
          best = GuideEdge(pr, 2);
        }
      }
      final dist = math.sqrt(u * u + v * v);
      final d = (dist - radius).abs();
      if (d < bestDistance && (pr.full || v <= reach)) {
        bestDistance = d;
        best = GuideEdge(pr, 3);
      }
      // Innenkante des Ausschnitts.
      final inner = GuideShape.protractorInnerCm * ppc;
      final di = (dist - inner).abs();
      if (di < bestDistance && (pr.full || v <= reach)) {
        bestDistance = di;
        best = GuideEdge(pr, 4);
      }
    }
    final tr = triangle;
    if (tr != null) {
      final (u, v) = tr.toLocal(p);
      final q = Offset(u, v);
      final segments = _triangleSegments(ppc);
      for (var i = 0; i < segments.length; i++) {
        final d = (q - _nearestOnSegment(q, segments[i].$1, segments[i].$2))
            .distance;
        if (d < bestDistance) {
          bestDistance = d;
          best = GuideEdge(tr, 5 + i);
        }
      }
    }
    final cp = compass;
    if (cp != null) {
      final (u, v) = cp.toLocal(p);
      final d = (math.sqrt(u * u + v * v) - cp.radiusCm * ppc).abs();
      if (d < bestDistance) {
        bestDistance = d;
        best = GuideEdge(cp, 8);
      }
    }
    return best;
  }

  /// Hypotenuse, linker und rechter Schenkel in Hilfsmittel-Koordinaten.
  static List<(Offset, Offset)> _triangleSegments(double ppc) {
    final a = Offset(-GuideShape.triangleHypCm * ppc / 2, 0);
    final b = Offset(GuideShape.triangleHypCm * ppc / 2, 0);
    final apex = Offset(0, -GuideShape.triangleHeightCm * ppc);
    return [(a, b), (a, apex), (apex, b)];
  }

  static Offset _nearestOnSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 < 1e-9) return a;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2)
        .clamp(0.0, 1.0)
        .toDouble();
    return a + ab * t;
  }

  /// Punkt auf die gewählte Kante projizieren.
  static Offset project(GuideEdge edge, Offset p, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    final s = edge.shape;
    final (u, v) = s.toLocal(p);
    switch (edge.type) {
      case 0 || 1:
        final halfLen = GuideShape.rulerLengthCm * ppc / 2;
        final sign = edge.type == 0 ? -1 : 1;
        return s.toPage(
          u.clamp(-halfLen, halfLen).toDouble(),
          sign * GuideShape.rulerWidthCm * ppc / 2,
        );
      case 2:
        final r = GuideShape.protractorRadiusCm * ppc;
        return s.toPage(u.clamp(-r, r).toDouble(), 0);
      case 5 || 6 || 7:
        final seg = _triangleSegments(ppc)[edge.type - 5];
        final q = _nearestOnSegment(Offset(u, v), seg.$1, seg.$2);
        return s.toPage(q.dx, q.dy);
      case 8:
        final r = s.radiusCm * ppc;
        final len = math.sqrt(u * u + v * v);
        if (len < 1e-6) return s.toPage(r, 0);
        return s.toPage(u / len * r, v / len * r);
      default:
        final r =
            (edge.type == 4
                ? GuideShape.protractorInnerCm
                : GuideShape.protractorRadiusCm) *
            ppc;
        var uu = u;
        var vv = v;
        if (!s.full && vv > 0) {
          // Unterhalb der Grundlinie gibt es keinen Bogen: zum Ende klemmen.
          vv = 0;
          uu = uu >= 0 ? r : -r;
        }
        final len = math.sqrt(uu * uu + vv * vv);
        if (len < 1e-6) return s.toPage(r, 0);
        return s.toPage(uu / len * r, vv / len * r);
    }
  }
}

class _GuideNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}
