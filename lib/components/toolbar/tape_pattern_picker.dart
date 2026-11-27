import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/tape_geometry.dart';
import 'package:saber/data/prefs.dart';

/// Auswahl der Klebeband-Muster direkt in der Stift-Leiste.
/// Das erste Feld ("Farbe") bedeutet einfarbig mit der Farbe aus der Farbleiste.
class TapePatternPicker extends StatelessWidget {
  const TapePatternPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        stows.lastTapePattern,
        ...stows.tapeTexts,
        ...stows.tapeColors,
      ]),
      builder: (context, _) {
        final selected = stows.lastTapePattern.value;
        Widget swatch(int pattern, Widget child, String tooltip) {
          final isSelected = selected == pattern;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Tooltip(
              message: tooltip,
              child: GestureDetector(
                onTap: () => stows.lastTapePattern.value = pattern,
                child: Container(
                  width: 44,
                  height: 26,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: child,
                  ),
                ),
              ),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch(
              -1,
              Center(
                child: Text('Farbe', style: const TextStyle(fontSize: 10)),
              ),
              'Einfarbig (Farbe aus der Leiste)',
            ),
            for (final i in tapePatternOrder)
              if (i < tapeTextFirst ||
                  i >= tapeTextFirst + tapeTextCount ||
                  tapeTextOf(i - tapeTextFirst).isNotEmpty ||
                  selected == i)
                swatch(
                  i,
                  CustomPaint(
                    painter: _SwatchPainter(
                      i,
                      i >= tapeTextFirst && i < tapeTextFirst + tapeTextCount
                          ? tapeTextOf(i - tapeTextFirst)
                          : '',
                      i >= tapeTextFirst && i < tapeTextFirst + tapeTextCount
                          ? tapeColorOf(i - tapeTextFirst)
                          : 0,
                    ),
                    size: Size.infinite,
                  ),
                  i >= tapeTextFirst && i < tapeTextFirst + tapeTextCount
                      ? (tapeTextOf(i - tapeTextFirst).isEmpty
                            ? tapePatternNames[i]
                            : tapeTextOf(i - tapeTextFirst))
                      : tapePatternNames[i],
                ),
          ],
        );
      },
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.pattern, this.text, this.colorValue);

  final int pattern;
  final String text;
  final int colorValue;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    // Vorschau: Band mit Breite = Höhe der Fläche, damit das Muster lesbar bleibt.
    canvas.translate(0, size.height / 2);
    paintTapePattern(canvas, pattern, size.width, size.height);
  }

  @override
  bool shouldRepaint(_SwatchPainter oldDelegate) =>
      oldDelegate.pattern != pattern ||
      oldDelegate.text != text ||
      oldDelegate.colorValue != colorValue;
}
