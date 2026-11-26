import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  /// Feder: Handschrift der Auswahl als Aufgabe an Nextcloud senden.
  final VoidCallback createTask;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.createTask,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: .center,
      children: [
        TextButton.icon(
          onPressed: createTask,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
          ),
          icon: const Icon(Icons.task_alt),
          label: const Text('Als Aufgabe'),
        ),
        IconButton(
          onPressed: duplicateSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.duplicate,
          icon: const AdaptiveIcon(
            icon: Icons.content_copy,
            cupertinoIcon: CupertinoIcons.doc_on_clipboard,
          ),
        ),
        IconButton(
          onPressed: deleteSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: t.editor.selectionBar.delete,
          icon: const AdaptiveIcon(
            icon: Icons.delete,
            cupertinoIcon: CupertinoIcons.delete,
          ),
        ),
      ],
    );
  }
}
