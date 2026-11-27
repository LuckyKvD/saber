import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/images/safe_render.dart';

/// Vorlagen für Text-Stempel.
const textStampPresets = [
  'VERTRAULICH',
  'ACHTUNG',
  'BEACHTEN',
  'WICHTIG',
  'DRINGEND',
  'ERLEDIGT',
  'GEPRÜFT',
  'ENTWURF',
];

const textStampColors = <(String, Color)>[
  ('Rot', Color(0xFFC62828)),
  ('Blau', Color(0xFF1565C0)),
  ('Grün', Color(0xFF2E7D32)),
  ('Schwarz', Color(0xFF212121)),
];

/// Zeichnet einen eingerahmten Stempel (wie ein Gummistempel) als PNG
/// mit transparentem Hintergrund. Als Bild lässt er sich verschieben,
/// drehen und in der Größe ändern.
Future<Uint8List> renderTextStamp(String text, Color color) async {
  const fontSize = 96.0;
  final painter = TextPainter(
    text: TextSpan(
      text: text.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 6,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  const pad = 36.0;
  const border = 10.0;
  final width = painter.width + pad * 2 + border * 2;
  final height = painter.height + pad * 1.2 + border * 2;

  return renderInkPng(
    (canvas) {
      final stroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = border;
      final outer = RRect.fromRectAndRadius(
        Rect.fromLTWH(border / 2, border / 2, width - border, height - border),
        const Radius.circular(24),
      );
      canvas.drawRRect(outer, stroke);
      canvas.drawRRect(
        outer.deflate(border * 1.8),
        stroke..strokeWidth = border * 0.35,
      );
      painter.paint(
        canvas,
        Offset(border + pad, (height - painter.height) / 2),
      );
    },
    width.ceil(),
    height.ceil(),
    color,
  );
}

/// Fragt Text und Farbe ab. Gibt null zurück, wenn abgebrochen wurde.
Future<(String, Color)?> showTextStampDialog(BuildContext context) {
  return showDialog<(String, Color)>(
    context: context,
    builder: (_) => const _TextStampDialog(),
  );
}

class _TextStampDialog extends StatefulWidget {
  const _TextStampDialog();

  @override
  State<_TextStampDialog> createState() => _TextStampDialogState();
}

class _TextStampDialogState extends State<_TextStampDialog> {
  final controller = TextEditingController(text: textStampPresets.first);
  var color = textStampColors.first.$2;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Text-Stempel'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final preset in textStampPresets)
                  ActionChip(
                    label: Text(preset),
                    onPressed: () =>
                        setState(() => controller.text = preset),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Eigener Text',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 24,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (name, c) in textStampColors)
                  ChoiceChip(
                    label: Text(name),
                    selected: color == c,
                    avatar: CircleAvatar(backgroundColor: c, radius: 8),
                    onSelected: (_) => setState(() => color = c),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Der Stempel erscheint in der Bildmitte. Danach kannst du ihn '
              'verschieben und in der Größe ändern.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            Navigator.of(context).pop((text, color));
          },
          child: const Text('Stempeln'),
        ),
      ],
    );
  }
}
