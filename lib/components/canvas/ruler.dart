import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Unveränderliche Momentaufnahme des Lineals für den Seiten-Painter.
@immutable
class RulerData {
  const RulerData({
    required this.center,
    required this.angle,
    required this.pxPerCm,
  });

  final Offset center;

  /// Drehung im Bogenmaß (0 = waagerecht).
  final double angle;

  /// Seitenpunkte pro Zentimeter.
  final double pxPerCm;

  @override
  bool operator ==(Object other) =>
      other is RulerData &&
      other.center == center &&
      other.angle == angle &&
      other.pxPerCm == pxPerCm;

  @override
  int get hashCode => Object.hash(center, angle, pxPerCm);
}

/// Zustand des virtuellen Lineals. Gehört zu genau einer Notiz und einer Seite.
/// Das Lineal wird nicht gespeichert und erscheint nicht in Exporten.
class RulerState {
  const RulerState._();

  static Object? owner;
  static int pageIndex = 0;
  static Offset center = Offset.zero;
  static double angle = 0;

  static const lengthCm = 30.0;
  static const widthCm = 4.0;

  /// Annahme: Die Seitenbreite entspricht der Breite von A4 (21 cm).
  static double pxPerCm(Size pageSize) => pageSize.width / 21;

  static bool isActiveFor(Object coreInfo, int index) =>
      owner != null && identical(owner, coreInfo) && index == pageIndex;

  static RulerData? dataFor(Object coreInfo, int index, Size pageSize) {
    if (!isActiveFor(coreInfo, index)) return null;
    return RulerData(
      center: center,
      angle: angle,
      pxPerCm: pxPerCm(pageSize),
    );
  }

  static void show(Object coreInfo, int index, Size pageSize) {
    owner = coreInfo;
    pageIndex = index;
    center = Offset(pageSize.width / 2, pageSize.height * 0.35);
    angle = 0;
  }

  static void clear() {
    owner = null;
    pageIndex = 0;
  }

  // Koordinaten im Lineal: u entlang der Kante, v quer dazu.
  static (double, double) _local(Offset p) {
    final d = p - center;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return (d.dx * c + d.dy * s, -d.dx * s + d.dy * c);
  }

  static bool hitBody(Offset p, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    final (u, v) = _local(p);
    return u.abs() <= lengthCm * ppc / 2 && v.abs() <= widthCm * ppc / 2;
  }

  /// Drehgriff: Kreis nahe dem rechten Ende.
  static Offset handleLocal(double ppc) =>
      Offset(lengthCm * ppc / 2 - 1.8 * ppc, 0);
  static double handleRadius(double ppc) => 1.2 * ppc;

  static bool hitHandle(Offset p, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    final (u, v) = _local(p);
    final h = handleLocal(ppc);
    return (Offset(u, v) - h).distance <= handleRadius(ppc) + 0.3 * ppc;
  }

  /// Dreht das Lineal so, dass der Griff zum Finger zeigt. Rastet nahe
  /// an Vielfachen von 15 Grad ein.
  static void rotateTowards(Offset p) {
    final d = p - center;
    if (d.distance < 1) return;
    var deg = math.atan2(d.dy, d.dx) * 180 / math.pi;
    final snapped = (deg / 15).roundToDouble() * 15;
    if ((deg - snapped).abs() < 1.5) deg = snapped;
    angle = deg * math.pi / 180;
  }

  static void moveBy(Offset delta, Size pageSize) {
    center = Offset(
      (center.dx + delta.dx).clamp(0, pageSize.width).toDouble(),
      (center.dy + delta.dy).clamp(0, pageSize.height).toDouble(),
    );
  }

  /// Welche Längskante liegt nahe am Punkt? -1 oben, +1 unten, sonst null.
  static int? edgeNear(Offset p, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    final (u, v) = _local(p);
    final half = widthCm * ppc / 2;
    const reach = 30.0;
    if (u.abs() > lengthCm * ppc / 2 + reach) return null;
    if ((v.abs() - half).abs() > reach) return null;
    return v < 0 ? -1 : 1;
  }

  /// Punkt auf die gewählte Kante projizieren (innerhalb der Lineal-Länge).
  static Offset project(Offset p, int sign, Size pageSize) {
    final ppc = pxPerCm(pageSize);
    final (u, _) = _local(p);
    final halfLen = lengthCm * ppc / 2;
    final uu = u.clamp(-halfLen, halfLen).toDouble();
    final vv = sign * widthCm * ppc / 2;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return center + Offset(uu * c - vv * s, uu * s + vv * c);
  }

  /// Winkel der Kante zur Waagerechten in Grad, 0 bis unter 180.
  static double get degrees {
    final deg = (angle * 180 / math.pi) % 180;
    final d = deg < 0 ? deg + 180 : deg;
    return d >= 179.95 ? 0 : d;
  }

  static String get degreesLabel {
    final d = degrees;
    if ((d - d.round()).abs() < 0.05) return '${d.round() % 180}°';
    return '${d.toStringAsFixed(1).replaceAll('.', ',')}°';
  }
}
