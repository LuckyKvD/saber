import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nextcloud/webdav.dart';
import 'package:saber/data/nextcloud/server_cleanup.dart';
import 'package:saber/data/prefs.dart';

/// Einstellungs-Eintrag „Server aufräumen“ (nur wenn angemeldet).
class ServerCleanupTile extends HookWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final loggedIn = useListenableSelector(
      stows.username,
      () => stows.loggedIn,
    );
    if (!loggedIn) return const SizedBox.shrink();
    return ListTile(
      leading: const Icon(Icons.cleaning_services),
      title: const Text('Server aufräumen'),
      subtitle: const Text(
        'Löscht leere Löschmarken auf der Nextcloud (entstehen beim '
        'Verschieben, Umbenennen und Löschen). Deine Notizen bleiben.',
      ),
      onTap: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _CleanupDialog(),
      ),
    );
  }
}

class _CleanupDialog extends HookWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final blocked = ServerCleanup.blockedReason();
    final markers = useState<List<WebDavFile>?>(null);
    final searching = useState(false);
    final running = useState(false);
    final done = useState(0);
    final result = useState<({int removed, int failed})?>(null);
    final error = useState('');

    useEffect(() {
      if (blocked != null) return null;
      searching.value = true;
      ServerCleanup.findEmptyMarkers()
          .then((list) => markers.value = list)
          .catchError((Object e) {
            error.value = '$e';
            markers.value = const [];
            return const <WebDavFile>[];
          })
          .whenComplete(() => searching.value = false);
      return null;
    }, const []);

    Future<void> start() async {
      final list = markers.value ?? const [];
      running.value = true;
      try {
        result.value = await ServerCleanup.run(
          list,
          onProgress: (d, t) => done.value = d,
        );
      } catch (e) {
        error.value = '$e';
      } finally {
        running.value = false;
      }
    }

    final list = markers.value;
    final res = result.value;

    Widget content;
    if (blocked != null) {
      content = Text(blocked);
    } else if (res != null) {
      content = Text(
        'Fertig. Gelöscht: ${res.removed}'
        '${res.failed > 0 ? '\nNicht löschbar: ${res.failed}' : ''}',
      );
    } else if (running.value) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: (list?.isEmpty ?? true) ? null : done.value / list!.length,
          ),
          const SizedBox(height: 8),
          Text('${done.value} von ${list?.length ?? 0}'),
        ],
      );
    } else if (searching.value || list == null) {
      content = const Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Expanded(child: Text('Suche leere Dateien auf dem Server …')),
        ],
      );
    } else if (list.isEmpty) {
      content = Text(
        error.value.isEmpty
            ? 'Es gibt nichts aufzuräumen.'
            : 'Fehler: ${error.value}',
      );
    } else {
      content = Text(
        'Auf dem Server liegen ${list.length} leere Löschmarken. Sie werden '
        'jetzt endgültig gelöscht (Nextcloud legt sie in den Papierkorb).\n\n'
        'Das ist nur sicher, wenn alle deine Geräte schon synchron sind. '
        'Deine Notizen und der Schlüssel werden nicht angefasst.\n\n'
        'Fortfahren?',
      );
    }

    final canStart =
        blocked == null &&
        res == null &&
        !running.value &&
        !searching.value &&
        (list?.isNotEmpty ?? false);

    return AlertDialog(
      title: const Text('Server aufräumen'),
      content: SingleChildScrollView(child: content),
      actions: [
        if (!running.value)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(res == null ? 'Abbrechen' : 'Schließen'),
          ),
        if (canStart)
          FilledButton(onPressed: start, child: const Text('Löschen')),
      ],
    );
  }
}
