import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/tape_geometry.dart';
import 'package:saber/data/prefs.dart';

/// Feder: Dialog für die Texte der Textbänder 1–5.
/// Die Texte liegen nur in den Einstellungen dieses Geräts, nicht im Code.
Future<void> showTapeTextDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _TapeTextDialog(),
  );
}

class _TapeTextDialog extends StatefulWidget {
  const _TapeTextDialog();

  @override
  State<_TapeTextDialog> createState() => _TapeTextDialogState();
}

class _TapeTextDialogState extends State<_TapeTextDialog> {
  late final List<TextEditingController> _controllers = [
    for (final s in stows.tapeTexts) TextEditingController(text: s.value),
  ];

  late final List<int> _colors = [
    for (final s in stows.tapeColors) s.value,
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Texte für Textbänder'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Diese Texte stehen nur in den Einstellungen dieses Geräts. '
              'Leere Felder werden im Stift-Menü nicht angezeigt. '
              'Unter jedem Feld wählst du die Bandfarbe. '
              'Achtung: Der Text wird beim Zeichnen nicht im Strich gespeichert. '
              'Ändert man ihn später, ändern sich alle Bänder dieser Nummer.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _controllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _controllers[i],
                      maxLength: 24,
                      decoration: InputDecoration(
                        labelText: 'Textband ${i + 1}',
                        border: const OutlineInputBorder(),
                        counterText: '',
                        filled: true,
                        fillColor: Color(_colors[i]).withValues(alpha: 0.18),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in tapeColorChoices)
                          GestureDetector(
                            onTap: () => setState(() => _colors[i] = c),
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _colors[i] == c
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: [
                                  if (_colors[i] == c)
                                    const BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 3,
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
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
            for (var i = 0; i < _controllers.length; i++) {
              stows.tapeTexts[i].value = _controllers[i].text.trim();
              stows.tapeColors[i].value = _colors[i];
            }
            Navigator.of(context).pop();
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
