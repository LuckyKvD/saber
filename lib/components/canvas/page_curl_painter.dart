import 'dart:math';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Zeichnet eine Seite, die von rechts nach links um einen Zylinder
/// aufgerollt (weggeblättert) wird, mit Schatten und sichtbarer Rückseite.
///
/// [forward] = true: Seite wird weggeblättert (Fortschritt 0 -> 1).
/// [forward] = false: Seite kommt zurück (Fortschritt 1 -> 0).
class PageCurlPainter extends CustomPainter {
  PageCurlPainter({
    required this.image,
    required this.animation,
    required this.forward,
    this.leftBlank = 0,
  }) : super(repaint: animation);

  /// Doppelblatt: Breite des leeren Bereichs links (die andere Buchseite).
  /// Das Bild ist dann nur die rechte Seite; sie rollt über den Falz.
  final double leftBlank;

  final ui.Image image;
  final Animation<double> animation;
  final bool forward;

  static const _strips = 56;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeInOut.transform(animation.value);
    final p0 = forward ? t : 1 - t;
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    final book = leftBlank > 0;
    // Buch: Die Seite rollt nur bis zum Falz und blendet dann aus.
    final p = book ? p0 * (1 - leftBlank / w) : p0;
    final cw = w - leftBlank;

    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final r = w * 0.15;
    final xc = w * (1 - p);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    if (book) {
      final fade = ((p0 - 0.7) / 0.3).clamp(0.0, 1.0);
      final alpha = 1 - fade;
      if (alpha < 1) {
        canvas.saveLayer(
          Offset.zero & size,
          Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
        );
      }
    }

    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.low;

    // Flacher Teil.
    if (xc > leftBlank + 0.5) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, iw * (xc - leftBlank) / cw, ih),
        Rect.fromLTWH(leftBlank, 0, xc - leftBlank, h),
        paint,
      );
    }

    // Aufgerollter Teil, von vorne nach hinten.
    final total = w - xc;
    double maxX = xc;
    if (total > 0.5) {
      double posOf(double s) =>
          s <= pi * r ? xc + r * sin(s / r) : xc - (s - pi * r);
      final backPaint = Paint()..isAntiAlias = false;
      final shadePaint = Paint()..isAntiAlias = false;
      for (var i = 0; i < _strips; i++) {
        final s0 = total * i / _strips;
        final s1 = total * (i + 1) / _strips;
        if (xc + s1 <= leftBlank) continue;
        final x0 = posOf(s0);
        final x1 = posOf(s1);
        final left = min(x0, x1) - 0.6;
        final right = max(x0, x1) + 0.6;
        maxX = max(maxX, right);
        final mid = (s0 + s1) / 2;
        final phi = mid / r;
        // Leichte Perspektive: aufgerollter Teil liegt „weiter vorne“.
        final lift = phi >= pi ? 1.0 : (1 - cos(phi)) / 2;
        final inset = h * 0.045 * lift;
        final dst = Rect.fromLTRB(left, inset, right, h - inset);
        if (phi < pi) {
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              max(0.0, xc + s0 - leftBlank) / cw * iw,
              0,
              (s1 - s0) / cw * iw + 0.5,
              ih,
            ),
            dst,
            paint,
          );
          shadePaint.color = Colors.black.withValues(
            alpha: 0.38 * (1 - cos(phi)) / 2,
          );
          canvas.drawRect(dst, shadePaint);
        } else {
          // Rückseite: helles Papier, nach hinten aufgehellt.
          final fade = ((phi - pi) / 1.2).clamp(0.0, 1.0);
          backPaint.color = Color.lerp(
            const Color(0xFFD9D2C2),
            const Color(0xFFF3EEE2),
            fade,
          )!;
          canvas.drawRect(dst, backPaint);
        }
      }

      // Schatten der Rolle auf der darunterliegenden Seite.
      final shadowLeft = min(maxX, w);
      final shadowRight = min(shadowLeft + r * 1.6, w);
      if (shadowRight > shadowLeft + 0.5) {
        final shadow = Rect.fromLTRB(shadowLeft, 0, shadowRight, h);
        canvas.drawRect(
          shadow,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(shadow.left, 0),
              Offset(shadow.right, 0),
              [
                Colors.black.withValues(alpha: 0.28),
                Colors.black.withValues(alpha: 0),
              ],
            ),
        );
      }
    }
    if (book && ((p0 - 0.7) / 0.3).clamp(0.0, 1.0) > 0) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(PageCurlPainter old) =>
      old.image != image ||
      old.forward != forward ||
      old.leftBlank != leftBlank;
}
