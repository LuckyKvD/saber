import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/guide_tools.dart';

/// Eigene Ebene für Lineal und Winkelmesser. Sie wird unabhängig von den
/// Strichen neu gezeichnet und verarbeitet Berührungen selbst:
/// ein Finger verschiebt, zwei Finger verschieben und drehen frei.
class GuideOverlay extends StatefulWidget {
  const GuideOverlay({
    super.key,
    required this.coreInfo,
    required this.pageIndex,
    required this.pageSize,
  });

  final Object coreInfo;
  final int pageIndex;
  final Size pageSize;

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay> {
  final _ids = <int>[];
  final _positions = <int, Offset>{};
  GuideShape? _active;
  bool _rotating = false;

  double get _ppc => Guides.pxPerCm(widget.pageSize);

  /// Lage dieser Seite relativ zur Besitzerseite des Hilfsmittels
  /// (Doppelblatt: Partnerseite).
  Offset get _shift => Offset(
    Guides.offsetXFor(widget.coreInfo, widget.pageIndex),
    0,
  );
  Offset _own(Offset local) => local - _shift;

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    if (_ids.isEmpty) {
      final shape = Guides.pick(_own(e.localPosition), widget.pageSize);
      if (shape == null) return;
      _active = shape;
      _rotating = shape.hitHandle(_own(e.localPosition), _ppc);
      Guides.grabbing = true;
    } else if (_active == null) {
      return;
    }
    _ids.add(e.pointer);
    _positions[e.pointer] = _own(e.localPosition);
  }

  static double _wrap(double a) {
    while (a > math.pi) a -= 2 * math.pi;
    while (a < -math.pi) a += 2 * math.pi;
    return a;
  }

  void _move(PointerMoveEvent e) {
    final shape = _active;
    final prev = _positions[e.pointer];
    if (shape == null || prev == null) return;
    final now = _own(e.localPosition);
    final size = widget.pageSize;

    if (_ids.length >= 2 && (e.pointer == _ids[0] || e.pointer == _ids[1])) {
      // Zwei Finger: starre Bewegung (verschieben und drehen).
      final other = e.pointer == _ids[0] ? _ids[1] : _ids[0];
      final otherPos = _positions[other]!;
      final focal0 = (prev + otherPos) / 2;
      final focal1 = (now + otherPos) / 2;
      final v0 = prev - otherPos;
      final v1 = now - otherPos;
      if (v0.distance > 1 && v1.distance > 1) {
        final dAngle = _wrap(v1.direction - v0.direction);
        shape.rawAngle += dAngle;
        final rel = shape.center - focal0;
        final c = math.cos(dAngle);
        final s = math.sin(dAngle);
        final rotated = Offset(rel.dx * c - rel.dy * s, rel.dx * s + rel.dy * c);
        shape.center = focal1 + rotated;
        Guides.moveBy(shape, Offset.zero, size);
      }
    } else if (_ids.length == 1) {
      if (_rotating && shape.kind == GuideKind.compass) {
        // Zirkel: Griff stellt Radius und Richtung ein.
        final d = now - shape.center;
        shape.radiusCm = (d.distance / _ppc).clamp(1.0, 12.0).toDouble();
        shape.rawAngle = d.direction;
      } else if (_rotating) {
        final a0 = (prev - shape.center).direction;
        final a1 = (now - shape.center).direction;
        shape.rawAngle += _wrap(a1 - a0);
      } else {
        Guides.moveBy(shape, now - prev, size);
      }
    }
    _positions[e.pointer] = now;
    Guides.notifier.ping();
  }

  void _up(PointerEvent e) {
    if (!_positions.containsKey(e.pointer)) return;
    _positions.remove(e.pointer);
    _ids.remove(e.pointer);
    _rotating = false;
    if (_ids.isEmpty) {
      _active = null;
      Guides.grabbing = false;
      Guides.settle();
    }
  }

  @override
  void dispose() {
    if (_ids.isNotEmpty) Guides.grabbing = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: RepaintBoundary(
        child: CustomPaint(
          size: widget.pageSize,
          painter: _GuidePainter(widget.coreInfo, widget.pageIndex, widget.pageSize),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.coreInfo, this.pageIndex, this.pageSize)
    : super(repaint: Guides.notifier);

  final Object coreInfo;
  final int pageIndex;
  final Size pageSize;

  static const _ink = Color(0xFF3E2F00);

  static ui.Picture? _rulerPicture;
  static double _rulerPpc = 0;
  static ui.Picture? _halfPicture;
  static ui.Picture? _fullPicture;
  static double _protractorPpc = 0;

  @override
  bool? hitTest(Offset position) {
    if (Guides.offsetFor(coreInfo, pageIndex) == null) return false;
    final dx = Guides.offsetXFor(coreInfo, pageIndex);
    return Guides.pick(position - Offset(dx, 0), pageSize) != null;
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final offsetY = Guides.offsetFor(coreInfo, pageIndex);
    if (offsetY == null) return;
    // Oben und unten nie über den eigenen Seitenrand hinaus zeichnen (sonst
    // erscheint das Hilfsmittel doppelt); seitlich darf es überstehen.
    canvas.clipRect(Rect.fromLTRB(-100000, 0, 100000, size.height));
    final offsetX = Guides.offsetXFor(coreInfo, pageIndex);
    if (offsetY != 0 || offsetX != 0) canvas.translate(offsetX, offsetY);
    final ppc = Guides.pxPerCm(pageSize);
    final ruler = Guides.ruler;
    if (ruler != null) _paintRuler(canvas, ruler, ppc);
    final protractor = Guides.protractor;
    if (protractor != null) _paintProtractor(canvas, protractor, ppc);
    final triangle = Guides.triangle;
    if (triangle != null) _paintTriangle(canvas, triangle, ppc);
    final compass = Guides.compass;
    if (compass != null) _paintCompass(canvas, compass, ppc);
  }

  static ui.Picture? _trianglePicture;
  static double _trianglePpc = 0;

  void _paintTriangle(Canvas canvas, GuideShape t, double ppc) {
    if (_trianglePicture == null || _trianglePpc != ppc) {
      _trianglePicture = _recordTriangle(ppc);
      _trianglePpc = ppc;
    }
    canvas.save();
    canvas.translate(t.center.dx, t.center.dy);
    canvas.rotate(t.angle);
    canvas.drawPicture(_trianglePicture!);
    canvas.restore();
  }

  ui.Picture _recordTriangle(double ppc) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final half = GuideShape.triangleHypCm * ppc / 2;
    final h = GuideShape.triangleHeightCm * ppc;
    final a = Offset(-half, 0);
    final b = Offset(half, 0);
    final apex = Offset(0, -h);

    // Ausschnitt in der Mitte (verkleinertes Dreieck um den Inkreismittelpunkt).
    final rIn = GuideShape.triangleInradiusCm;
    final k = (rIn - 1.5) / rIn;
    final c = Offset(0, -rIn * ppc);
    Offset shrink(Offset v) => c + (v - c) * k;
    final outer = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(apex.dx, apex.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
    final inner = Path()
      ..moveTo(shrink(a).dx, shrink(a).dy)
      ..lineTo(shrink(apex).dx, shrink(apex).dy)
      ..lineTo(shrink(b).dx, shrink(b).dy)
      ..close();
    final body = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(body, Paint()..color = const Color(0x66FFD54F));
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF8D6E00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final tick = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    // Hypotenuse: cm-Skala 0 bis 16 (Striche nach oben in den Körper).
    final mm = (GuideShape.triangleHypCm * 10).round();
    for (var i = 0; i <= mm; i++) {
      final x = -half + i * ppc / 10;
      final tl = i % 10 == 0
          ? ppc * 0.45
          : i % 5 == 0
          ? ppc * 0.3
          : ppc * 0.18;
      canvas.drawLine(Offset(x, 0), Offset(x, -tl), tick);
      if (i % 10 == 0 && i > 0 && i < mm) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i ~/ 10}',
            style: TextStyle(color: _ink, fontSize: ppc * 0.38),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, -ppc * 0.5 - tp.height));
      }
    }
    // Schenkel: cm-Skala ab der Spitze (rechter Winkel), Striche nach innen.
    final legMm = (GuideShape.triangleHeightCm * math.sqrt2 * 10).floor();
    final s2 = math.sqrt1_2;
    for (final left in [true, false]) {
      final d = Offset(left ? -s2 : s2, s2);
      final n = Offset(left ? s2 : -s2, s2);
      for (var i = 0; i <= legMm; i++) {
        final tl = i % 10 == 0
            ? ppc * 0.45
            : i % 5 == 0
            ? ppc * 0.3
            : ppc * 0.18;
        final pt = apex + d * (i * ppc / 10);
        canvas.drawLine(pt, pt + n * tl, tick);
      }
    }
    // Mittelmarke an der Hypotenuse und Drehgriff in der Mitte.
    canvas.drawLine(Offset(0, 0), Offset(0, -ppc * 0.9), tick..strokeWidth = 1.5);
    final hc = Offset(0, -rIn * ppc);
    final hr = 1.0 * ppc;
    canvas.drawCircle(hc, hr, Paint()..color = const Color(0x55FFFFFF));
    final ring = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(hc, hr, ring);
    canvas.drawArc(
      Rect.fromCircle(center: hc, radius: hr * 0.55),
      -math.pi * 0.8,
      math.pi * 1.5,
      false,
      ring,
    );
    return recorder.endRecording();
  }

  void _paintCompass(Canvas canvas, GuideShape cp, double ppc) {
    final r = cp.radiusCm * ppc;
    canvas.save();
    canvas.translate(cp.center.dx, cp.center.dy);
    canvas.rotate(cp.angle);
    final line = Paint()
      ..color = const Color(0xFF8D6E00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Kreis (zeigt, wo gezeichnet würde) und Schenkel von der Spitze zum Griff.
    canvas.drawCircle(Offset.zero, r, line..color = const Color(0x998D6E00));
    canvas.drawLine(Offset.zero, Offset(r, 0), line..color = const Color(0xFF8D6E00));
    canvas.drawCircle(Offset.zero, ppc * 0.25, Paint()..color = _ink);
    final tick = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    for (var i = 0; i <= (cp.radiusCm * 10).floor(); i++) {
      final x = i * ppc / 10;
      final tl = i % 10 == 0
          ? ppc * 0.4
          : i % 5 == 0
          ? ppc * 0.28
          : ppc * 0.16;
      canvas.drawLine(Offset(x, 0), Offset(x, -tl), tick);
    }
    final hr = 0.9 * ppc;
    final hc = Offset(r, 0);
    canvas.drawCircle(hc, hr, Paint()..color = const Color(0x88FFFFFF));
    final ring = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(hc, hr, ring);
    canvas.drawArc(
      Rect.fromCircle(center: hc, radius: hr * 0.55),
      -math.pi * 0.8,
      math.pi * 1.5,
      false,
      ring,
    );
    // Radiusanzeige, nie kopfüber.
    if (math.cos(cp.angle) < 0) canvas.rotate(math.pi);
    final label = TextPainter(
      text: TextSpan(
        text: 'r = ${cp.radiusCm.toStringAsFixed(1).replaceAll('.', ',')} cm',
        style: TextStyle(
          color: _ink,
          fontSize: ppc * 0.7,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(-label.width / 2, ppc * 0.5));
    canvas.restore();
  }

  void _paintRuler(Canvas canvas, GuideShape ruler, double ppc) {
    if (_rulerPicture == null || _rulerPpc != ppc) {
      _rulerPicture = _recordRuler(ppc);
      _rulerPpc = ppc;
    }
    canvas.save();
    canvas.translate(ruler.center.dx, ruler.center.dy);
    canvas.rotate(ruler.angle);
    canvas.drawPicture(_rulerPicture!);

    // Winkelanzeige, nie kopfüber.
    if (math.cos(ruler.angle) < 0) canvas.rotate(math.pi);
    final label = TextPainter(
      text: TextSpan(
        text: ruler.degreesLabel,
        style: TextStyle(
          color: _ink,
          fontSize: ppc * 0.9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
  }

  ui.Picture _recordRuler(double ppc) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final len = GuideShape.rulerLengthCm * ppc;
    final wid = GuideShape.rulerWidthCm * ppc;

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: len, height: wid),
      Radius.circular(ppc * 0.2),
    );
    canvas.drawRRect(body, Paint()..color = const Color(0x66FFD54F));
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF8D6E00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final tick = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    final mm = (GuideShape.rulerLengthCm * 10).round();
    for (var i = 0; i <= mm; i++) {
      final x = -len / 2 + i * ppc / 10;
      final tl = i % 10 == 0
          ? ppc * 0.45
          : i % 5 == 0
          ? ppc * 0.3
          : ppc * 0.18;
      canvas.drawLine(Offset(x, -wid / 2), Offset(x, -wid / 2 + tl), tick);
      canvas.drawLine(Offset(x, wid / 2), Offset(x, wid / 2 - tl), tick);
      if (i % 10 == 0 && i > 0 && i < mm) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${i ~/ 10}',
            style: TextStyle(color: _ink, fontSize: ppc * 0.38),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, -wid / 2 + ppc * 0.5));
      }
    }

    _brand(canvas, 'LuckyKvD', Offset(-len / 2 + 9.5 * ppc, 0.2 * ppc), ppc * 1.15);

    final h = Offset(len / 2 - 1.8 * ppc, 0);
    final hr = 1.2 * ppc;
    canvas.drawCircle(h, hr, Paint()..color = const Color(0x55FFFFFF));
    final ring = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(h, hr, ring);
    canvas.drawArc(
      Rect.fromCircle(center: h, radius: hr * 0.55),
      -math.pi * 0.8,
      math.pi * 1.5,
      false,
      ring,
    );
    return recorder.endRecording();
  }

  void _paintProtractor(Canvas canvas, GuideShape p, double ppc) {
    if (_protractorPpc != ppc || _halfPicture == null || _fullPicture == null) {
      _halfPicture = _recordProtractor(ppc, full: false);
      _fullPicture = _recordProtractor(ppc, full: true);
      _protractorPpc = ppc;
    }
    canvas.save();
    canvas.translate(p.center.dx, p.center.dy);
    canvas.rotate(p.angle);
    canvas.drawPicture(p.full ? _fullPicture! : _halfPicture!);
    canvas.restore();
  }

  ui.Picture _recordProtractor(double ppc, {required bool full}) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final r = GuideShape.protractorRadiusCm * ppc;
    final ri = GuideShape.protractorInnerCm * ppc;
    final strip = GuideShape.protractorStripCm * ppc;

    // Körper wie ein echter Winkelmesser: Außenform mit Ausschnitt in der Mitte.
    final outerCircle = Rect.fromCircle(center: Offset.zero, radius: r);
    final innerCircle = Rect.fromCircle(center: Offset.zero, radius: ri);
    Path outer;
    Path inner;
    if (full) {
      outer = Path()..addOval(outerCircle);
      inner = Path()..addOval(innerCircle);
    } else {
      outer = Path()
        ..moveTo(-r, strip)
        ..lineTo(-r, 0)
        ..arcTo(outerCircle, math.pi, math.pi, false)
        ..lineTo(r, strip)
        ..close();
      inner = Path()
        ..moveTo(-ri, -ppc * 0.05)
        ..arcTo(innerCircle, math.pi, math.pi, false)
        ..lineTo(ri, -ppc * 0.05)
        ..close();
    }
    final body = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(body, Paint()..color = const Color(0x66FFD54F));
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF8D6E00)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final tick = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    final steps = full ? 360 : 180;
    for (var d = 0; d <= steps; d++) {
      if (full && d == 360) break;
      final a = d * math.pi / 180;
      // Winkel gegen den Uhrzeigersinn ab der rechten Grundlinie.
      final dir = Offset(math.cos(a), -math.sin(a));
      final tl = d % 10 == 0
          ? ppc * 0.5
          : d % 5 == 0
          ? ppc * 0.35
          : ppc * 0.2;
      canvas.drawLine(dir * r, dir * (r - tl), tick);
      if (d % 10 == 0) {
        _radialNumber(canvas, '$d', dir * (r - ppc * 0.95), a, ppc * 0.32, 1);
        if (!full) {
          _radialNumber(
            canvas,
            '${180 - d}',
            dir * (r - ppc * 1.5),
            a,
            ppc * 0.28,
            0.7,
          );
        }
      }
    }

    // Grundlinie, Mittellinie und Mittelpunkt.
    final line = Paint()
      ..color = _ink
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), line);
    canvas.drawLine(Offset(0, -ppc * 0.8), Offset(0, full ? ppc * 0.8 : strip), line);
    // Schriftzug rund auf dem Bogen, direkt am Innenrand der Skala.
    _arcText(canvas, 'Claude', ri + ppc * 0.42, ppc * 0.5);
    return recorder.endRecording();
  }

  /// Schriftzug entlang eines Bogens, oben mittig, Fuß zur Mitte.
  void _arcText(Canvas canvas, String text, double radius, double fontSize) {
    final painters = <TextPainter>[];
    var total = 0.0;
    for (final ch in text.split('')) {
      final tp = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            color: _ink.withValues(alpha: 0.75),
            fontFamily: 'Dekko',
            fontSize: fontSize,
            fontStyle: FontStyle.italic,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add(tp);
      total += tp.width;
    }
    var offset = 0.0;
    final start = math.pi / 2 + total / radius / 2;
    for (final tp in painters) {
      final theta = start - (offset + tp.width / 2) / radius;
      canvas.save();
      canvas.translate(radius * math.cos(theta), -radius * math.sin(theta));
      canvas.rotate(math.pi / 2 - theta);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
      offset += tp.width;
    }
  }

  /// Kleiner Schriftzug auf dem Hilfsmittel (Schreibschrift-artige Schrift).
  void _brand(Canvas canvas, String text, Offset center, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _ink.withValues(alpha: 0.75),
          fontFamily: 'Dekko',
          fontSize: fontSize,
          fontStyle: FontStyle.italic,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  /// Zahl, die mit dem Fuß zur Mitte zeigt (wie auf dem echten Winkelmesser).
  void _radialNumber(
    Canvas canvas,
    String text,
    Offset at,
    double angle,
    double fontSize,
    double alpha,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _ink.withValues(alpha: alpha),
          fontSize: fontSize,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(math.pi / 2 - angle);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }
}
