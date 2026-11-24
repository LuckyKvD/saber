import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/crypto/local_migration.dart';
import 'package:saber/data/prefs.dart';

/// Zeigt, wie viele lokale Notizdateien verschlüsselt sind. Antippen zählt neu
/// und verschlüsselt, falls noch unverschlüsselte Dateien vorhanden sind.
class LocalEncryptionTile extends HookWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final key = useValueListenable(stows.key);
    final status = useState<({int encrypted, int plain})?>(null);
    final busy = useState(false);

    Future<void> recount() async {
      busy.value = true;
      try {
        status.value = await LocalMigration.countStatus();
      } finally {
        busy.value = false;
      }
    }

    useEffect(() {
      if (key.isNotEmpty) recount();
      return null;
    }, [key]);

    final s = status.value;
    final String subtitle;
    if (key.isEmpty) {
      subtitle =
          'Nicht aktiv: Melde dich bei Nextcloud an, dann werden deine '
          'Notizen auf dem Gerät verschlüsselt.';
    } else if (s == null) {
      subtitle = 'Wird geprüft …';
    } else {
      final total = s.encrypted + s.plain;
      subtitle = s.plain == 0
          ? 'Aktiv: alle $total Dateien sind verschlüsselt.'
          : '${s.encrypted} von $total Dateien verschlüsselt, '
                '${s.plain} noch nicht. Antippen zum Verschlüsseln.';
    }

    return ListTile(
      leading: Icon(
        s != null && s.plain == 0 && key.isNotEmpty
            ? Icons.lock
            : Icons.lock_open,
      ),
      title: const Text('Lokale Verschlüsselung'),
      subtitle: Text(subtitle),
      trailing: busy.value
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: key.isEmpty || busy.value
          ? null
          : () async {
              final current = status.value;
              if (current != null && current.plain > 0) {
                busy.value = true;
                await LocalMigration.encryptAll();
              }
              await recount();
            },
    );
  }
}
