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

    final sinT = sin(theta);
    final dist = pw * 5;
    // Das Blatt biegt sich: Die freie Kante eilt dem Falz voraus. In der
    // Mitte des Umklappens ist die Biegung am stärksten, am Anfang und am
    // Ende liegt das Blatt flach.
    const bend = 0.95;
    double angleAt(double u) => (theta + bend * sinT * (u / pw)).clamp(0.0, pi);

    // Streifen von Falz bis freier Kante: Lage (x, Tiefe z) aufsummieren.
    final xs = List<double>.filled(_strips + 1, x0);
    final scales = List<double>.filled(_strips + 1, 1);
    var x = 0.0;
    var z = 0.0;
    for (var i = 0; i < _strips; i++) {
      final um = pw * (i + 0.5) / _strips;
      final a = angleAt(um);
      final ds = pw / _strips;
      x += ds * cos(a);
      z += ds * sin(a);
      final sc = 1 / (1 - z / dist);
      scales[i + 1] = sc;
      xs[i + 1] = x0 + x * sc;
    }

    // Schatten auf der Seite unter dem Blatt, neben der freien Kante.
    final edge = xs[_strips];
    final shadowW = pw * 0.3;
    final alpha = 0.34 * sinT;
    if (alpha > 0.01) {
      final onRight = edge > x0;
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

    final fw = front.width.toDouble();
    final fh = front.height.toDouble();
    final bw = back.width.toDouble();
    final bh = back.height.toDouble();
    final shade = Paint()..isAntiAlias = false;
    for (var i = 0; i < _strips; i++) {
      final u0 = pw * i / _strips;
      final u1 = pw * (i + 1) / _strips;
      final am = angleAt((u0 + u1) / 2);
      final showFront = cos(am) >= 0;
      final xa = xs[i];
      final xb = xs[i + 1];
      final left = min(xa, xb) - 0.5;
      final right = max(xa, xb) + 0.5;
      final sm = (scales[i] + scales[i + 1]) / 2;
      final inset = h * (1 - sm) / 2; // negativ = größer
      final dst = Rect.fromLTRB(left, inset, right, h - inset);
      if (showFront) {
        canvas.drawImageRect(
          front,
          Rect.fromLTWH(u0 / pw * fw, 0, (u1 - u0) / pw * fw + 0.5, fh),
          dst,
          paint,
        );
      } else {
        canvas.drawImageRect(
          back,
          Rect.fromLTWH((1 - u1 / pw) * bw, 0, (u1 - u0) / pw * bw + 0.5, bh),
          dst,
          paint,
        );
      }
      // Licht von links oben: schräg stehende Teile werden dunkler.
      final dark = 0.30 * pow(sin(am), 1.2).toDouble();
      if (dark > 0.01) {
        shade.color = Colors.black.withValues(alpha: dark);
        canvas.drawRect(dst, shade);
      }
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
