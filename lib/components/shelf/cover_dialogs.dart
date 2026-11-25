import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/shelf/cover_widgets.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/note_cover.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:sbn/canvas_background_pattern.dart';

String _titleOf(String filePath) =>
    filePath.substring(filePath.lastIndexOf('/') + 1);

/// Knopf in der Auswahlleiste: Einband der gewaehlten Notiz aendern.
class CoverNoteButton extends StatelessWidget {
  const CoverNoteButton({
    super.key,
    required this.existingPath,
    required this.unselectNotes,
  });

  final String existingPath;
  final void Function() unselectNotes;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      padding: EdgeInsets.zero,
      tooltip: 'Einband',
      onPressed: () async {
        await showDialog<void>(
          context: context,
          builder: (context) => _CoverDialog(filePath: existingPath),
        );
        unselectNotes();
      },
      icon: const Icon(Icons.palette_outlined),
    );
  }
}

class _CoverDialog extends StatefulWidget {
  const _CoverDialog({required this.filePath});

  final String filePath;

  @override
  State<_CoverDialog> createState() => _CoverDialogState();
}

class _CoverDialogState extends State<_CoverDialog> {
  late NoteCover cover = NoteCover.peek(widget.filePath);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Einband'),
      content: SingleChildScrollView(
        child: CoverPicker(
          cover: cover,
          title: _titleOf(widget.filePath),
          onChanged: (value) => setState(() => cover = value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () async {
            await cover.save(widget.filePath);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _NewNotebook {
  const _NewNotebook({
    required this.title,
    required this.cover,
    required this.pattern,
    required this.lineHeight,
  });

  final String title;
  final NoteCover cover;
  final CanvasBackgroundPattern pattern;
  final int lineHeight;
}

const _patternNames = <CanvasBackgroundPattern, String>{
  CanvasBackgroundPattern.none: 'Leer',
  CanvasBackgroundPattern.grid: 'Kariert',
  CanvasBackgroundPattern.lined: 'Liniert',
  CanvasBackgroundPattern.collegeLtr: 'College',
  CanvasBackgroundPattern.dots: 'Punkte',
  CanvasBackgroundPattern.cornell: 'Cornell',
  CanvasBackgroundPattern.staffs: 'Notenlinien',
  CanvasBackgroundPattern.tablature: 'Tabulatur',
};

const _lineHeights = <String, int>{'Eng': 30, 'Normal': 40, 'Weit': 55};

class _NewNotebookDialog extends StatefulWidget {
  const _NewNotebookDialog();

  @override
  State<_NewNotebookDialog> createState() => _NewNotebookDialogState();
}

class _NewNotebookDialogState extends State<_NewNotebookDialog> {
  final controller = TextEditingController();
  NoteCover cover = const NoteCover(color: 0xFF14284B, material: 0, motif: 3);
  CanvasBackgroundPattern pattern = stows.lastBackgroundPattern.value;
  int lineHeight = stows.lastLineHeight.value;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neues Notizbuch'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Titel'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Center(
                child: CoverPicker(
                  cover: cover,
                  title: controller.text.trim(),
                  onChanged: (value) => setState(() => cover = value),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Seitenvorlage'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final entry in _patternNames.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: pattern == entry.key,
                      onSelected: (_) => setState(() => pattern = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Zeilenabstand'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in _lineHeights.entries)
                    ChoiceChip(
                      label: Text(entry.key),
                      selected: lineHeight == entry.value,
                      onSelected: (_) =>
                          setState(() => lineHeight = entry.value),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _NewNotebook(
              title: controller.text,
              cover: cover,
              pattern: pattern,
              lineHeight: lineHeight,
            ),
          ),
          child: const Text('Anlegen'),
        ),
      ],
    );
  }
}

/// Fragt Titel, Einband und Seitenvorlage ab und oeffnet das neue Notizbuch.
Future<void> startNewNotebook(BuildContext context, String? path) async {
  final result = await showDialog<_NewNotebook>(
    context: context,
    builder: (context) => const _NewNotebookDialog(),
  );
  if (result == null || !context.mounted) return;

  final title = result.title
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
      .trim();
  final parent = '${path ?? ''}/';
  final filePath = title.isEmpty
      ? await FileManager.newFilePath(parent)
      : await FileManager.suffixFilePathToMakeItUnique('$parent$title');

  // Neue Notizen starten mit den zuletzt gewaehlten Einstellungen.
  stows.lastBackgroundPattern.value = result.pattern;
  stows.lastLineHeight.value = result.lineHeight;
  await result.cover.save(filePath);

  if (!context.mounted) return;
  context.push(RoutePaths.editFilePath(filePath));
}
