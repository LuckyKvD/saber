import 'dart:io' show Directory;

import 'package:material_ui/material_ui.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// Lässt einen Zielordner wählen (für „Ordner verschieben“).
/// Gibt den Pfad des Zielordners zurück (`'/'` = Hauptregal) oder `null`.
/// Der Ordner [excludePath] und alles darin wird nicht angeboten.
Future<String?> pickFolder(
  BuildContext context, {
  required String title,
  required String excludePath,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _PickFolderDialog(title: title, excludePath: excludePath),
  );
}

class _PickFolderDialog extends StatefulWidget {
  const new({required this.title, required this.excludePath});

  final String title;
  final String excludePath;

  @override
  State<_PickFolderDialog> createState() => _PickFolderDialogState();
}

class _PickFolderDialogState extends State<_PickFolderDialog> {
  List<String>? folders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final root = Directory(FileManager.documentsDirectory);
    final found = <String>[];
    if (root.existsSync()) {
      await for (final entity in root.list(recursive: true)) {
        if (entity is! Directory) continue;
        final rel = entity.path.substring(root.path.length);
        if (rel.isEmpty) continue;
        final path = rel.startsWith('/') ? rel : '/$rel';
        if (path == widget.excludePath ||
            path.startsWith('${widget.excludePath}/')) {
          continue;
        }
        found.add(path);
      }
    }
    found.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (mounted) setState(() => folders = found);
  }

  @override
  Widget build(BuildContext context) {
    final list = folders;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        height: 380,
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.shelves),
                    title: const Text('Hauptregal (oberste Ebene)'),
                    onTap: () => Navigator.of(context).pop('/'),
                  ),
                  for (final path in list)
                    ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(path.substring(1)),
                      onTap: () => Navigator.of(context).pop(path),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
      ],
    );
  }
}
