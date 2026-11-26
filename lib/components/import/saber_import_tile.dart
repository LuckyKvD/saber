import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/import/saber_importer.dart';
import 'package:saber/data/import/saber_legacy_crypto.dart';
import 'package:saber/data/prefs.dart';

/// Knopf auf dem Hauptbildschirm: „Notizen aus Saber importieren“
/// (nur wenn die Verschlüsselung eingerichtet ist).
class SaberImportButton extends HookWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final key = useValueListenable(stows.key);
    if (key.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Notizen aus Saber importieren',
      icon: const Icon(Icons.move_to_inbox),
      onPressed: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _ImportDialog(),
      ),
    );
  }
}

class _ImportDialog extends HookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final password = useTextEditingController();
    final running = useState(false);
    final status = useState('');
    final done = useState(0);
    final total = useState(0);
    final error = useState('');
    final result = useState<SaberImportResult?>(null);
    final hide = useState(true);

    Future<void> start() async {
      running.value = true;
      error.value = '';
      try {
        result.value = await SaberImporter.run(
          saberPassword: password.text,
          onProgress: (s, d, t) {
            status.value = s;
            done.value = d;
            total.value = t;
          },
        );
      } on SaberLegacyWrongPassword catch (e) {
        error.value = e.message;
      } catch (e) {
        error.value = '$e';
      } finally {
        running.value = false;
      }
    }

    final res = result.value;
    return AlertDialog(
      title: const Text('Notizen aus Saber importieren'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (res != null) ...[
              Text('Importiert: ${res.imported}'),
              Text('Schon vorhanden (übersprungen): ${res.skippedExisting}'),
              if (res.recovered > 0)
                Text('Repariert (Dateiende war defekt): ${res.recovered}'),
              Text('Fehlgeschlagen: ${res.failed}'),
              const SizedBox(height: 8),
              const Text(
                'Du findest die Notizen im Ordner „Import aus Saber“. '
                'Die Dateien werden jetzt verschlüsselt in den Feder-Ordner '
                'synchronisiert.',
              ),
              if (res.largest.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Größte Dateien:'),
                Text(res.largest.join('\n')),
              ],
              if (res.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  res.errors.take(8).join('\n'),
                  style: TextStyle(color: ColorScheme.of(context).error),
                ),
              ],
            ] else if (running.value) ...[
              Text(status.value, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: total.value == 0 ? null : done.value / total.value,
              ),
              if (total.value > 0) Text('${done.value} von ${total.value}'),
            ] else ...[
              const Text(
                'Gib das Verschlüsselungspasswort ein, das du in Saber benutzt '
                'hast. Es wird nur für diesen Import verwendet und nicht '
                'gespeichert. Feder liest den Saber-Ordner nur und verändert '
                'dort nichts.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: password,
                obscureText: hide.value,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Saber-Verschlüsselungspasswort',
                  suffixIcon: IconButton(
                    icon: Icon(
                      hide.value ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => hide.value = !hide.value,
                  ),
                ),
              ),
              if (error.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error.value,
                    style: TextStyle(color: ColorScheme.of(context).error),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        if (!running.value)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(res == null ? 'Abbrechen' : 'Schließen'),
          ),
        if (res == null && !running.value)
          FilledButton(
            onPressed: start,
            child: const Text('Import starten'),
          ),
      ],
    );
  }
}
