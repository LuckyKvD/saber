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

  void _down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    if (_ids.isEmpty) {
      final shape = Guides.pick(e.localPosition, widget.pageSize);
      if (shape == null) return;
      _active = shape;
      _rotating = shape.hitHandle(e.localPosition, _ppc);
      Guides.grabbing = true;
    } else if (_active == null) {
      return;
    }
    _ids.add(e.pointer);
    _positions[e.pointer] = e.localPosition;
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
    final now = e.localPosition;
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
      if (_rotating) {
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

  bool get _active => Guides.isActiveFor(coreInfo, pageIndex);

  @override
  bool? hitTest(Offset position) {
    if (!_active) return false;
    return Guides.pick(position, pageSize) != null;
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) => true;

  @override
  void paint(Canvas canvas, Size size) {
    if (!_active) return;
    final ppc = Guides.pxPerCm(pageSize);
    final ruler = Guides.ruler;
    if (ruler != null) _paintRuler(canvas, ruler, ppc);
    final protractor = Guides.protractor;
    if (protractor != null) _paintProtractor(canvas, protractor, ppc);
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

    _brand(canvas, 'LuckyKvD', Offset(-len / 2 + 5.5 * ppc, 0.2 * ppc), ppc * 1.15);

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
    _brand(canvas, 'Claude', Offset(0, -ri * 0.55), ppc * 0.95);
    return recorder.endRecording();
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
