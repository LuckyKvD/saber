import 'package:material_ui/material_ui.dart';
import 'package:saber/data/file_manager/file_manager.dart';

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
  var query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await FileManager.getAllFiles();
    all.removeWhere((path) => path == widget.excludePath);
    all.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    if (mounted) setState(() => notebooks = all);
  }

  @override
  Widget build(BuildContext context) {
    final list = notebooks;
    final shown = list
        ?.where((path) => path.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Notizbuch suchen',
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: shown == null
                  ? const Center(child: CircularProgressIndicator())
                  : shown.isEmpty
                  ? const Center(child: Text('Kein Notizbuch gefunden'))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, index) {
                        final path = shown[index];
                        return ListTile(
                          leading: const Icon(Icons.menu_book),
                          title: Text(
                            path.startsWith('/') ? path.substring(1) : path,
                          ),
                          onTap: () => Navigator.of(context).pop(path),
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
