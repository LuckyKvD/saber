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

    final fill = Paint()..color = const Color(0x66FFD54F);
    final outline = Paint()
      ..color = const Color(0xFF8D6E00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (full) {
      canvas.drawCircle(Offset.zero, r, fill);
      canvas.drawCircle(Offset.zero, r, outline);
    } else {
      final path = Path()
        ..moveTo(-r, 0)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r), math.pi, math.pi, false)
        ..close();
      canvas.drawPath(path, fill);
      canvas.drawPath(path, outline);
    }

    final tick = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    final steps = full ? 360 : 180;
    for (var d = 0; d < steps + (full ? 0 : 1); d++) {
      final a = d * math.pi / 180;
      // Winkel gegen den Uhrzeigersinn ab der rechten Grundlinie.
      final dir = Offset(math.cos(a), -math.sin(a));
      final tl = d % 10 == 0
          ? ppc * 0.5
          : d % 5 == 0
          ? ppc * 0.35
          : ppc * 0.2;
      canvas.drawLine(dir * r, dir * (r - tl), tick);
      if (d % 10 == 0 && (full || d <= 180)) {
        final tp = TextPainter(
          text: TextSpan(
            text: '$d',
            style: TextStyle(color: _ink, fontSize: ppc * 0.32),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final c = dir * (r - ppc * 0.95);
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
        if (!full) {
          // Innere Zahlenreihe von links nach rechts.
          final tp2 = TextPainter(
            text: TextSpan(
              text: '${180 - d}',
              style: TextStyle(
                color: _ink.withValues(alpha: 0.7),
                fontSize: ppc * 0.28,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          final c2 = dir * (r - ppc * 1.5);
          tp2.paint(canvas, c2 - Offset(tp2.width / 2, tp2.height / 2));
        }
      }
    }

    // Mittelpunkt und Grundlinie.
    final cross = Paint()
      ..color = _ink
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(-ppc * 0.4, 0), Offset(ppc * 0.4, 0), cross);
    canvas.drawLine(Offset(0, -ppc * 0.4), Offset(0, ppc * 0.4), cross);
    if (!full) {
      canvas.drawLine(Offset(-r, 0), Offset(r, 0), cross);
    }
    return recorder.endRecording();
  }
}
