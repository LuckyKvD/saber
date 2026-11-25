import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

enum GuideKind { ruler, protractor }

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

  /// Angezeigter Winkel: rastet nahe an Vielfachen von 45 Grad ein,
  /// sonst frei.
  double get angle {
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
    }
  }

  /// Nur Lineal: Drehgriff nahe dem rechten Ende.
  Offset handleLocal(double ppc) => Offset(rulerLengthCm * ppc / 2 - 1.8 * ppc, 0);
  double handleRadius(double ppc) => 1.2 * ppc;

  bool hitHandle(Offset p, double ppc) {
    if (kind != GuideKind.ruler) return false;
    final (u, v) = toLocal(p);
    return (Offset(u, v) - handleLocal(ppc)).distance <=
        handleRadius(ppc) + 0.3 * ppc;
  }
}

/// Eine Kante, an der der Stift einrastet.
class GuideEdge {
  const GuideEdge(this.shape, this.type);

  final GuideShape shape;

  /// 0 Lineal oben, 1 Lineal unten, 2 Winkelmesser-Grundlinie, 3 Winkelmesser-Bogen.
  final int type;
}

/// Zustand der Zeichenhilfen. Gehört zu einer Notiz und einer Seite,
/// wird nicht gespeichert und erscheint nicht in Exporten.
class Guides {
  const Guides._();

  static Object? owner;
  static int pageIndex = 0;
  static GuideShape? ruler;
  static GuideShape? protractor;

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
      (ruler != null || protractor != null);

  static bool get anyVisible => ruler != null || protractor != null;

  static void _claim(Object coreInfo, int index) {
    if (owner != null && (!identical(owner, coreInfo) || pageIndex != index)) {
      ruler = null;
      protractor = null;
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
    grabbing = false;
    notifier.ping();
  }

  /// Welches Hilfsmittel liegt unter dem Punkt? Der Winkelmesser liegt oben.
  static GuideShape? pick(Offset p, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    final pr = protractor;
    if (pr != null && pr.hitBody(p, ppc)) return pr;
    final r = ruler;
    if (r != null && r.hitBody(p, ppc)) return r;
    return null;
  }

  static void moveBy(GuideShape shape, Offset delta, Size pageSize) {
    shape.center = Offset(
      (shape.center.dx + delta.dx).clamp(0, pageSize.width).toDouble(),
      (shape.center.dy + delta.dy).clamp(0, pageSize.height).toDouble(),
    );
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
    }
    return best;
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
      default:
        final r = GuideShape.protractorRadiusCm * ppc;
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
