import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:saber/data/note_cover.dart';

Color lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0).toDouble())
      .toColor();
}

Color darken(Color c, double amount) => lighten(c, -amount);

const _plateColor = Color(0xFFF3E9CF);

/// Zeichnet das Einbandmaterial (Leder, Karo, Marmor ...) in die ganze Flaeche.
class CoverMaterialPainter extends CustomPainter {
  const CoverMaterialPainter(this.cover, {this.stitched = false});

  final NoteCover cover;

  /// Genaehte Goldkante am Rand (nur auf der Vorderseite).
  final bool stitched;

  @override
  void paint(Canvas canvas, Size size) {
    final base = cover.colorValue;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [lighten(base, 0.07), base, darken(base, 0.16)],
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRect(rect);
    final rnd = math.Random(cover.color ^ (cover.material * 7919));
    final w = size.width, h = size.height;
    final light = Paint()..color = const Color(0x1FFFFFFF);
    final dark = Paint()..color = const Color(0x22000000);

    switch (cover.material) {
      case 0: // Leder: feine Narbung
        final n = (w * h / 40).clamp(80, 2200).toInt();
        for (var i = 0; i < n; i++) {
          final p = Paint()
            ..color = (rnd.nextBool() ? Colors.white : Colors.black).withValues(
              alpha: 0.04 + rnd.nextDouble() * 0.08,
            );
          canvas.drawCircle(
            Offset(rnd.nextDouble() * w, rnd.nextDouble() * h),
            0.5 + rnd.nextDouble() * 1.2,
            p,
          );
        }
      case 1: // Glatt: weicher Glanz
        canvas.drawRect(
          Rect.fromLTWH(w * 0.12, 0, w * 0.18, h),
          Paint()..color = const Color(0x14FFFFFF),
        );
      case 2: // Karo
        final stepK = w / 5;
        for (var x = stepK * 0.5; x < w; x += stepK) {
          canvas.drawRect(Rect.fromLTWH(x, 0, stepK * 0.35, h), light);
        }
        for (var y = stepK * 0.5; y < h; y += stepK) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, stepK * 0.35), light);
        }
        for (var x = 0.0; x < w; x += stepK) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 1.2, h), dark);
        }
        for (var y = 0.0; y < h; y += stepK) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, 1.2), dark);
        }
      case 3: // Streifen
        final stepS = w / 7;
        for (var x = stepS * 0.3; x < w; x += stepS) {
          canvas.drawRect(Rect.fromLTWH(x, 0, stepS * 0.4, h), light);
        }
      case 4: // Marmor: geschwungene Adern
        for (var k = 0; k < 7; k++) {
          final path = Path();
          var x = rnd.nextDouble() * w;
          path.moveTo(x, 0);
          final amp = w * (0.08 + rnd.nextDouble() * 0.18);
          final phase = rnd.nextDouble() * 6;
          for (var y = 0.0; y <= h; y += h / 24) {
            path.lineTo(x + math.sin(y / h * 7 + phase) * amp, y);
          }
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8 + rnd.nextDouble() * 2.6
              ..color = (k.isEven ? Colors.white : Colors.black).withValues(
                alpha: 0.10 + rnd.nextDouble() * 0.14,
              ),
          );
        }
      case 5: // Punkte
        final stepP = w * 0.17;
        var row = 0;
        for (var y = stepP * 0.5; y < h; y += stepP) {
          final shift = row.isEven ? 0.0 : stepP / 2;
          for (var x = stepP * 0.5 + shift; x < w + stepP; x += stepP) {
            canvas.drawCircle(Offset(x, y), stepP * 0.17, light);
          }
          row++;
        }
      case 6: // Leinen: Gewebe
        for (var y = 0.0; y < h; y += 3) {
          canvas.drawRect(Rect.fromLTWH(0, y, w, 0.8), dark);
        }
        for (var x = 0.0; x < w; x += 3) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 0.8, h), light);
        }
    }

    if (stitched) {
      final inset = math.max(6.0, w * 0.05);
      final stitch = Paint()
        ..color = NoteCover.gold.withValues(alpha: 0.9)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      const dash = 6.0, gap = 4.0;
      void line(Offset a, Offset b) {
        final len = (b - a).distance;
        final dir = (b - a) / len;
        for (var d = 0.0; d < len; d += dash + gap) {
          canvas.drawLine(
            a + dir * d,
            a + dir * math.min(d + dash, len),
            stitch,
          );
        }
      }

      line(Offset(inset, inset), Offset(w - inset, inset));
      line(Offset(w - inset, inset), Offset(w - inset, h - inset));
      line(Offset(w - inset, h - inset), Offset(inset, h - inset));
      line(Offset(inset, h - inset), Offset(inset, inset));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CoverMaterialPainter old) =>
      old.cover != cover || old.stitched != stitched;
}

/// Motiv in Praegeoptik (Gold bzw. Dunkelblau auf hellem Einband).
class CoverMotifPainter extends CustomPainter {
  const CoverMotifPainter(this.motif, this.color);

  final int motif;
  final Color color;

  void _emboss(Canvas canvas, Path path, Color cover) {
    canvas.drawPath(
      path.shift(const Offset(1.2, 1.4)),
      Paint()..color = const Color(0x59000000),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final s = math.min(size.width, size.height) / 2 * 0.92;
    switch (motif) {
      case 1: // Herz
        final heart = Path()
          ..moveTo(c.dx, c.dy + s * 0.9)
          ..cubicTo(c.dx - s * 1.5, c.dy + s * 0.1, c.dx - s * 0.9,
              c.dy - s * 0.9, c.dx, c.dy - s * 0.35)
          ..cubicTo(c.dx + s * 0.9, c.dy - s * 0.9, c.dx + s * 1.5,
              c.dy + s * 0.1, c.dx, c.dy + s * 0.9)
          ..close();
        _emboss(canvas, heart, color);
      case 2: // Totenkopf mit gekreuzten Knochen
        final bones = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.17
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(c.dx - s * 0.95, c.dy - s * 0.55),
          Offset(c.dx + s * 0.95, c.dy + s * 0.95),
          bones,
        );
        canvas.drawLine(
          Offset(c.dx + s * 0.95, c.dy - s * 0.55),
          Offset(c.dx - s * 0.95, c.dy + s * 0.95),
          bones,
        );
        var skull = Path()
          ..addOval(
            Rect.fromCenter(
              center: Offset(c.dx, c.dy - s * 0.12),
              width: s * 1.5,
              height: s * 1.4,
            ),
          )
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(c.dx - s * 0.45, c.dy + s * 0.3, c.dx + s * 0.45, c.dy + s * 0.85),
              Radius.circular(s * 0.12),
            ),
          );
        final holes = Path()
          ..addOval(Rect.fromCircle(center: Offset(c.dx - s * 0.32, c.dy - s * 0.1), radius: s * 0.22))
          ..addOval(Rect.fromCircle(center: Offset(c.dx + s * 0.32, c.dy - s * 0.1), radius: s * 0.22))
          ..addPolygon([
            Offset(c.dx, c.dy + s * 0.08),
            Offset(c.dx - s * 0.11, c.dy + s * 0.34),
            Offset(c.dx + s * 0.11, c.dy + s * 0.34),
          ], true);
        for (final dx in [-0.17, 0.0, 0.17]) {
          holes.addRect(
            Rect.fromLTRB(c.dx + s * dx - s * 0.025, c.dy + s * 0.52, c.dx + s * dx + s * 0.025, c.dy + s * 0.85),
          );
        }
        skull = Path.combine(PathOperation.difference, skull, holes);
        _emboss(canvas, skull, color);
      case 3: // LuckyKvD
        final tp = TextPainter(
          text: TextSpan(
            text: 'LuckyKvD',
            style: TextStyle(
              color: color,
              fontFamily: 'Dekko',
              fontStyle: FontStyle.italic,
              fontSize: 100,
              shadows: const [Shadow(color: Color(0x66000000), offset: Offset(1.2, 1.4))],
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final scale = math.min(size.width / tp.width, size.height / tp.height);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.scale(scale);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      case 4: // Feder
        canvas.save();
        canvas.translate(c.dx - s, c.dy - s);
        canvas.scale(s * 2 / 70);
        canvas.translate(-20, -20);
        final feather = Path()
          ..moveTo(36, 79)
          ..cubicTo(25, 52, 45, 29, 82, 23)
          ..cubicTo(82, 50, 63, 73, 36, 79)
          ..close();
        _emboss(canvas, feather, color);
        canvas.drawLine(
          const Offset(27, 90),
          const Offset(81, 24),
          Paint()
            ..color = color
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round,
        );
        canvas.restore();
      case 5: // Stern
        final star = Path();
        for (var i = 0; i < 10; i++) {
          final r = i.isEven ? s : s * 0.42;
          final a = -math.pi / 2 + i * math.pi / 5;
          final p = Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
          if (i == 0) {
            star.moveTo(p.dx, p.dy);
          } else {
            star.lineTo(p.dx, p.dy);
          }
        }
        star.close();
        _emboss(canvas, star, color);
    }
  }

  @override
  bool shouldRepaint(CoverMotifPainter old) =>
      old.motif != motif || old.color != color;
}

/// Fenster (Namensschild) mit dem Namen des Notizbuchs.
class CoverNamePlate extends StatelessWidget {
  const CoverNamePlate({super.key, required this.title, required this.fontSize, this.maxLines = 2});

  final String title;
  final double fontSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _plateColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: NoteCover.gold, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 3, offset: Offset(1, 1.5))],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: NoteCover.navy,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Vorderseite des Einbands: Material, Motiv und Namensfenster.
class CoverFront extends StatelessWidget {
  const CoverFront({
    super.key,
    required this.cover,
    required this.title,
    this.width = 140,
  });

  final NoteCover cover;
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.4;
    final small = width < 90;
    return Container(
      width: width,
      height: height,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(10),
        ),
        boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(2, 3))],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(10),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: CoverMaterialPainter(cover, stitched: !small)),
            ),
            if (cover.motif != 0)
              Positioned(
                top: height * 0.13,
                left: width * 0.14,
                right: width * 0.14,
                height: height * 0.30,
                child: CustomPaint(painter: CoverMotifPainter(cover.motif, cover.ink)),
              ),
            Positioned(
              left: width * 0.13,
              right: width * 0.13,
              top: height * (cover.motif == 0 ? 0.38 : 0.55),
              height: height * 0.22,
              child: small
                  ? const DecoratedBox(
                      decoration: BoxDecoration(
                        color: _plateColor,
                        border: Border.fromBorderSide(BorderSide(color: NoteCover.gold)),
                      ),
                    )
                  : CoverNamePlate(title: title, fontSize: width * 0.085),
            ),
          ],
        ),
      ),
    );
  }
}

/// Auswahl von Vorlage, Farbe, Material und Motiv mit Vorschau.
class CoverPicker extends StatelessWidget {
  const CoverPicker({
    super.key,
    required this.cover,
    required this.title,
    required this.onChanged,
  });

  final NoteCover cover;
  final String title;
  final ValueChanged<NoteCover> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoverFront(cover: cover, title: title.isEmpty ? 'Name' : title),
        const SizedBox(height: 16),
        const Text('Fertige Einbände'),
        const SizedBox(height: 8),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            children: [
              for (final preset in NoteCover.presets)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => onChanged(preset.$2),
                    child: Column(
                      children: [
                        CoverFront(cover: preset.$2, title: '', width: 56),
                        const SizedBox(height: 4),
                        Text(preset.$1, style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            for (final value in NoteCover.palette)
              GestureDetector(
                onTap: () => onChanged(cover.copyWith(color: value)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Color(value),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: cover.color == value ? NoteCover.gold : const Color(0x33000000),
                      width: cover.color == value ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Material'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < NoteCover.materialNames.length; i++)
              ChoiceChip(
                label: Text(NoteCover.materialNames[i]),
                selected: cover.material == i,
                onSelected: (_) => onChanged(cover.copyWith(material: i)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Motiv'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < NoteCover.motifNames.length; i++)
              ChoiceChip(
                label: Text(NoteCover.motifNames[i]),
                selected: cover.motif == i,
                onSelected: (_) => onChanged(cover.copyWith(motif: i)),
              ),
          ],
        ),
      ],
    );
  }
}
