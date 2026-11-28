import 'package:material_ui/material_ui.dart';
import 'package:saber/data/file_manager/decrypted_file_image.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/pages/editor/editor.dart';

/// Lässt ein Notizbuch aus allen vorhandenen auswählen.
/// Gibt den Pfad (ohne Dateiendung) zurück oder `null`.
Future<String?> pickNotebook(
  BuildContext context, {
  required String title,
  String? excludePath,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _PickNotebookDialog(title: title, excludePath: excludePath),
  );
}

class _PickNotebookDialog extends StatefulWidget {
  const new({required this.title, required this.excludePath});

  final String title;
  final String? excludePath;

  @override
  State<_PickNotebookDialog> createState() => _PickNotebookDialogState();
}

class _PickNotebookDialogState extends State<_PickNotebookDialog> {
  List<String>? notebooks;
  Set<String> recent = {};
  var query = '';
  String? folderFilter; // null = alle

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await FileManager.getAllFiles();
    all.removeWhere(
      (path) => path == widget.excludePath || path.startsWith('/Tagebuch/'),
    );
    all.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    var recents = <String>[];
    try {
      recents = await FileManager.getRecentlyAccessed();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      notebooks = all;
      recent = recents.where(all.contains).toSet();
      _recentOrder = recents;
    });
  }

  List<String> _recentOrder = [];

  static String _folderOf(String path) {
    final i = path.lastIndexOf('/');
    if (i <= 0) return '';
    final folder = path.substring(0, i);
    return folder.startsWith('/') ? folder.substring(1) : folder;
  }

  static String _nameOf(String path) => path.substring(path.lastIndexOf('/') + 1);

  @override
  Widget build(BuildContext context) {
    final list = notebooks;
    final q = query.toLowerCase();
    List<String>? shown;
    var folders = <String>[];
    if (list != null) {
      folders =
          list.map((p) => _folderOf(p).split('/').first).toSet().toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      shown = list.where((path) {
        if (q.isNotEmpty && !path.toLowerCase().contains(q)) return false;
        if (folderFilter != null &&
            _folderOf(path).split('/').first != folderFilter) {
          return false;
        }
        return true;
      }).toList();
      if (q.isEmpty && folderFilter == null) {
        // „Zuletzt geöffnet" zuerst, in Zugriffsreihenfolge.
        final first = _recentOrder.where(shown.contains).toList();
        final rest = shown.where((p) => !first.contains(p));
        shown = [...first, ...rest];
      }
    }
    final recentCount = (q.isEmpty && folderFilter == null && shown != null)
        ? shown.where(recent.contains).length
        : 0;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        height: 480,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Notizbuch suchen',
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            if (folders.length > 1) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: const Text('Alle'),
                        selected: folderFilter == null,
                        onSelected: (_) => setState(() => folderFilter = null),
                      ),
                    ),
                    for (final f in folders)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f.isEmpty ? 'Hauptregal' : f),
                          selected: folderFilter == f,
                          onSelected: (_) => setState(
                            () => folderFilter = folderFilter == f ? null : f,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: shown == null
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                  ? const Center(child: Text('Kein Notizbuch gefunden'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final path = shown![index];
                        final folder = _folderOf(path);
                        final header = recentCount > 0 && index == 0
                            ? 'Zuletzt geöffnet'
                            : (recentCount > 0 && index == recentCount
                                  ? 'Alle Notizbücher'
                                  : null);
                        final tile = ListTile(
                          leading: _Thumb(path: path),
                          title: Text(
                            _nameOf(path),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: folder.isEmpty
                              ? null
                              : Text(
                                  folder,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                          onTap: () => Navigator.of(context).pop(path),
                        );
                        if (header == null) return tile;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
                              child: Text(
                                header,
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                            ),
                            tile,
                          ],
                        );
                      },
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
      ],
    );
  }
}

/// Vorschaubild (gleiche `.p`-Datei wie auf der Startseite), sonst Symbol.
class _Thumb extends StatelessWidget {
  const new({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = FileManager.getFile('$path${Editor.extension}.p');
    return SizedBox(
      width: 48,
      height: 64,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: file.existsSync()
              ? Image(
                  image: DecryptedFileImage(file),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.menu_book, color: Colors.black45),
                )
              : const Icon(Icons.menu_book, color: Colors.black45),
        ),
      ),
    );
  }
}
