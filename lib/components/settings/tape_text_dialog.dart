import 'package:material_ui/material_ui.dart';
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
              'Achtung: Der Text wird beim Zeichnen nicht im Strich gespeichert. '
              'Ändert man ihn später, ändern sich alle Bänder dieser Nummer.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _controllers.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _controllers[i],
                  maxLength: 24,
                  decoration: InputDecoration(
                    labelText: 'Textband ${i + 1}',
                    border: const OutlineInputBorder(),
                    counterText: '',
                  ),
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
            }
            Navigator.of(context).pop();
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}
