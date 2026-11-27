import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/tasks/nextcloud_dav.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;

  /// Feder: Handschrift der Auswahl als Aufgabe, Termin oder Kontakt an
  /// Nextcloud senden.
  final void Function(NcKind kind) sendToNextcloud;

  /// Feder: Auswahl als Matheaufgabe lesen und lösen.
  final VoidCallback solveMath;

  /// Feder: Auswahl enthält eine Tabelle → Zeilen/Spalten anfügen.
  final bool hasTable;
  final void Function(int rows, int cols) extendTable;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.sendToNextcloud,
    required this.solveMath,
    required this.hasTable,
    required this.extendTable,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: .center,
      children: [
        if (hasTable)
          PopupMenuButton<(int, int)>(
            tooltip: 'Tabelle erweitern',
            onSelected: (v) => extendTable(v.$1, v.$2),
            itemBuilder: (context) => const [
              PopupMenuItem(value: (1, 0), child: Text('+ 1 Zeile unten')),
              PopupMenuItem(value: (3, 0), child: Text('+ 3 Zeilen unten')),
              PopupMenuItem(value: (0, 1), child: Text('+ 1 Spalte rechts')),
              PopupMenuItem(value: (0, 2), child: Text('+ 2 Spalten rechts')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.table_chart_outlined,
                    color: ColorScheme.of(context).secondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Tabelle',
                    style: TextStyle(color: ColorScheme.of(context).secondary),
                  ),
                ],
              ),
            ),
          ),
        TextButton.icon(
          onPressed: solveMath,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
          ),
          icon: const Icon(Icons.calculate),
          label: const Text('Rechnen'),
        ),
        PopupMenuButton<NcKind>(
          tooltip: 'An Nextcloud senden',
          onSelected: sendToNextcloud,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: NcKind.task,
              child: ListTile(
                leading: Icon(Icons.task_alt),
                title: Text('Als Aufgabe'),
              ),
            ),
            PopupMenuItem(
              value: NcKind.event,
              child: ListTile(
                leading: Icon(Icons.event),
                title: Text('Als Termin'),
              ),
            ),
            PopupMenuItem(
              value: NcKind.contact,
              child: ListTile(
                leading: Icon(Icons.person_add),
                title: Text('Als Kontakt'),
              ),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_upload,
                  color: ColorScheme.of(context).secondary,
                ),
                const SizedBox(width: 6),
                Text(
                  'An Nextcloud',
                  style: TextStyle(color: ColorScheme.of(context).secondary),
                ),
              ],
            ),
          ),
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
