import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/documents.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';

/// Feder-Dokumente: Liste der Textdokumente mit Ordnern.
class DocumentsPage extends StatefulWidget {
  const new({super.key});

  @override
  State<DocumentsPage> createState() => _DocumentsPageState();
}

class _DocumentsPageState extends State<DocumentsPage> {
  String dir = Documents.root;
  var folders = <String>[];
  var docs = <String>[];
  StreamSubscription<FileOperation>? _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = FileManager.fileWriteStream.stream.listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() {
    final l = Documents.list(dir);
    if (!mounted) return;
    setState(() {
      folders = l.folders;
      docs = l.docs;
    });
  }

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<String?> _askText(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _newDoc() async {
    final name = await _askText('Name des Dokuments', 'Neues Dokument');
    if (name == null || name.isEmpty) return;
    if (FileManager.validateFilename(name) != null) {
      _snack('Der Name enthält ungültige Zeichen.');
      return;
    }
    final path = Documents.uniquePath(dir, name);
    await Documents.save(path, FederDoc());
    if (!mounted) return;
    await context.push(RoutePaths.docPath(path));
    _reload();
  }

  Future<void> _newFolder() async {
    final name = await _askText('Name des Ordners', '');
    if (name == null || name.isEmpty) return;
    if (FileManager.validateFilename(name) != null) {
      _snack('Der Name enthält ungültige Zeichen.');
      return;
    }
    await FileManager.createFolder('$dir/$name');
    _reload();
  }

  Future<void> _docMenu(String name) async {
    final path = '$dir/$name';
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(name, style: Theme.of(c).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Umbenennen'),
              onTap: () => Navigator.of(c).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('Löschen'),
              onTap: () => Navigator.of(c).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'rename':
        final newName = await _askText('Umbenennen', name);
        if (newName == null || newName.isEmpty || newName == name) return;
        if (FileManager.validateFilename(newName) != null) {
          _snack('Der Name enthält ungültige Zeichen.');
          return;
        }
        await Documents.move(path, '$dir/$newName');
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Dokument löschen?'),
            content: Text('„$name“ wird gelöscht (nur über eine Sicherung wiederherstellbar).'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Löschen'),
              ),
            ],
          ),
        );
        if (ok == true) await Documents.delete(path);
    }
    _reload();
  }

  Future<void> _folderMenu(String name) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(name, style: Theme.of(c).textTheme.titleMedium)),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Ordner umbenennen'),
              onTap: () => Navigator.of(c).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('Ordner löschen (nur wenn leer)'),
              onTap: () => Navigator.of(c).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final path = '$dir/$name';
    if (choice == 'rename') {
      final newName = await _askText('Ordner umbenennen', name);
      if (newName == null || newName.isEmpty || newName == name) return;
      if (FileManager.validateFilename(newName) != null) {
        _snack('Der Name enthält ungültige Zeichen.');
        return;
      }
      await FileManager.renameDirectory(path, newName);
    } else {
      final inner = Documents.list(path);
      if (inner.folders.isNotEmpty || inner.docs.isNotEmpty) {
        _snack('Der Ordner ist nicht leer.');
        return;
      }
      await FileManager.deleteDirectory(path);
    }
    _reload();
  }

  /// Testdokument mit rund 100 Seiten Text.
  Future<void> _testDoc() async {
    const sentence =
        'Der schnelle braune Fuchs springt über den faulen Hund, während die '
        'Sonne langsam hinter den Hügeln untergeht und ein leichter Wind durch '
        'die Bäume weht. ';
    final ops = <Map<String, dynamic>>[];
    for (var chapter = 1; chapter <= 100; chapter++) {
      ops
        ..add({'insert': 'Kapitel $chapter'})
        ..add({'insert': '\n', 'attributes': {'header': 1}})
        ..add({'insert': List.filled(14, sentence).join() })
        ..add({'insert': '\n', 'attributes': {'align': 'justify'}});
    }
    ops.add({'insert': '\n'});
    final path = Documents.uniquePath(dir, 'Test 100 Seiten');
    await Documents.save(path, FederDoc(delta: ops));
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final atRoot = dir == Documents.root;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newDoc,
        icon: const Icon(Icons.note_add),
        label: const Text('Neues Dokument'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  if (!atRoot)
                    IconButton(
                      tooltip: 'Zurück',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        dir = dir.substring(0, dir.lastIndexOf('/'));
                        _reload();
                      },
                    ),
                  Expanded(
                    child: Text(
                      atRoot
                          ? 'Dokumente'
                          : dir.substring(Documents.root.length + 1),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Neuer Ordner',
                    icon: const Icon(Icons.create_new_folder),
                    onPressed: _newFolder,
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'test') _testDoc();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'test',
                        child: Text('Testdokument (100 Seiten) erzeugen'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (folders.isEmpty && docs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Noch keine Dokumente.')),
              ),
            for (final f in folders)
              ListTile(
                leading: Icon(Icons.folder, color: cs.primary),
                title: Text(f),
                onTap: () {
                  dir = '$dir/$f';
                  _reload();
                },
                onLongPress: () => _folderMenu(f),
              ),
            for (final d in docs)
              ListTile(
                leading: const Icon(Icons.description),
                title: Text(d),
                subtitle: Text(_modified('$dir/$d')),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert),
                  onPressed: () => _docMenu(d),
                ),
                onTap: () async {
                  await context.push(RoutePaths.docPath('$dir/$d'));
                  _reload();
                },
                onLongPress: () => _docMenu(d),
              ),
          ],
        ),
      ),
    );
  }

  static String _modified(String path) {
    try {
      final t = FileManager.lastModified('$path${Documents.extension}');
      String two(int n) => n.toString().padLeft(2, '0');
      return 'geändert ${two(t.day)}.${two(t.month)}.${t.year} '
          '${two(t.hour)}:${two(t.minute)}';
    } catch (_) {
      return '';
    }
  }
}
