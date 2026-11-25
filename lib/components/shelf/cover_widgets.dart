import 'package:material_ui/material_ui.dart';
import 'package:saber/data/note_cover.dart';

Color lighten(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl
      .withLightness((hsl.lightness + amount).clamp(0.0, 1.0).toDouble())
      .toColor();
}

Color darken(Color c, double amount) => lighten(c, -amount);

/// Kleine goldene Schreibfeder (wie das App-Symbol).
class FeatherPainter extends CustomPainter {
  const FeatherPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 70, size.height / 70);
    canvas.translate(-20, -20);
    final path = Path()
      ..moveTo(36, 79)
      ..cubicTo(25, 52, 45, 29, 82, 23)
      ..cubicTo(82, 50, 63, 73, 36, 79)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawLine(
      const Offset(27, 90),
      const Offset(81, 24),
      Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FeatherPainter old) => old.color != color;
}

/// Vorderseite des Einbands (Vorschau in den Dialogen).
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
    final base = cover.colorValue;
    final height = width * 1.4;
    const gold = NoteCover.gold;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(4),
          right: Radius.circular(10),
        ),
        gradient: LinearGradient(
          colors: [lighten(base, 0.06), base, darken(base, 0.14)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 8, offset: Offset(2, 3)),
        ],
      ),
      child: Stack(
        children: [
          if (cover.style == 0)
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: gold, width: 1.5),
                  ),
                ),
              ),
            ),
          if (cover.style == 1) ...[
            Positioned(left: 0, right: 0, top: height * 0.22, height: 2, child: const ColoredBox(color: gold)),
            Positioned(left: 0, right: 0, top: height * 0.22 + 6, height: 1, child: const ColoredBox(color: gold)),
            Positioned(left: 0, right: 0, bottom: height * 0.22, height: 2, child: const ColoredBox(color: gold)),
            Positioned(left: 0, right: 0, bottom: height * 0.22 + 6, height: 1, child: const ColoredBox(color: gold)),
          ],
          if (cover.style == 3)
            Positioned(
              top: height * 0.12,
              left: 0,
              right: 0,
              child: Center(
                child: CustomPaint(
                  size: Size(width * 0.28, width * 0.28),
                  painter: const FeatherPainter(gold),
                ),
              ),
            ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: width * 0.14),
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cover.ink,
                  fontSize: width * 0.13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Auswahl von Einbandfarbe und -stil mit Vorschau.
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
        CoverFront(cover: cover, title: title.isEmpty ? 'Titel' : title),
        const SizedBox(height: 16),
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
                      color: cover.color == value
                          ? NoteCover.gold
                          : const Color(0x33000000),
                      width: cover.color == value ? 3 : 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < NoteCover.styleNames.length; i++)
              ChoiceChip(
                label: Text(NoteCover.styleNames[i]),
                selected: cover.style == i,
                onSelected: (_) => onChanged(cover.copyWith(style: i)),
              ),
          ],
        ),
      ],
    );
  }
}
