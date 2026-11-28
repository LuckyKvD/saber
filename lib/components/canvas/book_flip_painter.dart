import 'dart:math';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Feder: Umblättern im Buch (Doppelblatt). Das Blatt klappt um den Falz:
/// erst sieht man seine Vorderseite (die alte rechte Seite), nach der Hälfte
/// die Rückseite (die neue linke Seite), die links liegen bleibt.
///
/// Gezeichnet wird nur die Fläche beider Seiten (+ 2 px Falz). Die Seite,
/// die sich beim Umblättern nicht ändert, bleibt die echte Ansicht darunter.
class BookFlipPainter extends CustomPainter {
  BookFlipPainter({
    required this.front,
    required this.back,
    required this.base,
    required this.baseOnRight,
    required this.animation,
    required this.forward,
  }) : super(repaint: animation);

  /// Vorderseite des Blatts = alte rechte Seite.
  final ui.Image front;

  /// Rückseite des Blatts = neue linke Seite.
  final ui.Image back;

  /// Die Seite, die unter dem Blatt zum Vorschein kommt.
  final ui.Image base;

  /// Vorwärts liegt [base] rechts (neue rechte Seite), rückwärts links.
  final bool baseOnRight;
  final Animation<double> animation;

  /// true: vorwärts blättern (Fortschritt 0 -> 1), false: zurück.
  final bool forward;

  static const _strips = 40;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOut.transform(animation.value);
    final p = forward ? t : 1 - t;
    final theta = p * pi;
    final h = size.height;
    final pw = (size.width - 2) / 2;
    if (pw <= 0 || h <= 0) return;
    final x0 = pw + 1; // Falz

    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.low;

    // Unter dem Blatt zum Vorschein kommende Seite.
    final baseRect = baseOnRight
        ? Rect.fromLTWH(pw + 2, 0, pw, h)
        : Rect.fromLTWH(0, 0, pw, h);
    canvas.drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      baseRect,
      paint,
    );

    final cosT = cos(theta);
    final sinT = sin(theta);
    final dist = pw * 4;
    double scaleAt(double u) => 1 / (1 - (u * sinT) / dist);

    // Schatten auf der Seite unter dem Blatt, neben der freien Kante.
    final edge = x0 + pw * cosT * scaleAt(pw);
    final shadowW = pw * 0.28;
    final alpha = 0.32 * sinT;
    if (alpha > 0.01) {
      final onRight = cosT > 0;
      final rect = onRight
          ? Rect.fromLTRB(edge, 0, min(edge + shadowW, size.width), h)
          : Rect.fromLTRB(max(edge - shadowW, 0), 0, edge, h);
      if (rect.width > 0.5) {
        canvas.drawRect(
          rect,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(onRight ? rect.left : rect.right, 0),
              Offset(onRight ? rect.right : rect.left, 0),
              [
                Colors.black.withValues(alpha: alpha),
                Colors.black.withValues(alpha: 0),
              ],
            ),
        );
      }
    }

    // Das Blatt selbst, in Streifen mit leichter Perspektive.
    final showFront = cosT >= 0;
    final img = showFront ? front : back;
    final iw = img.width.toDouble();
    final ih = img.height.toDouble();
    final shade = Paint()
      ..isAntiAlias = false
      ..color = Colors.black.withValues(alpha: 0.18 * sinT);
    for (var i = 0; i < _strips; i++) {
      final u0 = pw * i / _strips;
      final u1 = pw * (i + 1) / _strips;
      final s0 = scaleAt(u0);
      final s1 = scaleAt(u1);
      final xa = x0 + u0 * cosT * s0;
      final xb = x0 + u1 * cosT * s1;
      final left = min(xa, xb) - 0.5;
      final right = max(xa, xb) + 0.5;
      final sm = (s0 + s1) / 2;
      final inset = h * (1 - sm) / 2; // negativ = größer
      final dst = Rect.fromLTRB(left, inset, right, h - inset);
      final srcLeft = showFront ? u0 / pw * iw : (1 - u1 / pw) * iw;
      final src = Rect.fromLTWH(srcLeft, 0, (u1 - u0) / pw * iw + 0.5, ih);
      canvas.drawImageRect(img, src, dst, paint);
      if (sinT > 0.02) canvas.drawRect(dst, shade);
    }
  }

  @override
  bool shouldRepaint(BookFlipPainter old) =>
      old.front != front ||
      old.back != back ||
      old.base != base ||
      old.forward != forward ||
      old.baseOnRight != baseOnRight;
}
