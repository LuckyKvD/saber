import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/tasks/nextcloud_dav.dart';
import 'package:saber/i18n/strings.g.dart';

class SelectionBar extends StatelessWidget {
  final VoidCallback duplicateSelection;
  final VoidCallback deleteSelection;
  final VoidCallback saveAsTemplate;

  /// Feder: Handschrift der Auswahl als Aufgabe, Termin oder Kontakt an
  /// Nextcloud senden.
  final void Function(NcKind kind) sendToNextcloud;

  /// Feder: Auswahl als Matheaufgabe lesen und lösen.
  final VoidCallback solveMath;
  final VoidCallback convertToText;

  /// Feder: Auswahl (z. B. Handschrift) mit einer anderen Notiz verknüpfen.
  final VoidCallback linkSelection;

  /// Feder: Auswahl enthält eine Tabelle → Zeilen/Spalten anfügen.
  final bool hasTable;
  final void Function(int rows, int cols) extendTable;

  /// Strichdicke bzw. Größe der Auswahl ändern (Faktoren, 1 = unverändert).
  final void Function({double thickness, double scale}) adjustSelection;

  const new({
    super.key,
    required this.duplicateSelection,
    required this.deleteSelection,
    required this.saveAsTemplate,
    required this.sendToNextcloud,
    required this.solveMath,
    required this.convertToText,
    required this.linkSelection,
    required this.hasTable,
    required this.extendTable,
    required this.adjustSelection,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
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
        PopupMenuButton<(double, double)>(
          tooltip: 'Strichdicke und Größe',
          onSelected: (v) => adjustSelection(thickness: v.$1, scale: v.$2),
          itemBuilder: (context) => const [
            PopupMenuItem(value: (0.8, 1.0), child: Text('Striche dünner')),
            PopupMenuItem(value: (1.25, 1.0), child: Text('Striche dicker')),
            PopupMenuItem(value: (1.0, 0.8), child: Text('Verkleinern (80 %)')),
            PopupMenuItem(value: (1.0, 1.25), child: Text('Vergrößern (125 %)')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Icon(
              Icons.tune,
              color: ColorScheme.of(context).secondary,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: convertToText,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
          ),
          icon: const Icon(Icons.text_fields),
          label: const Text('In Text'),
        ),
        TextButton.icon(
          onPressed: linkSelection,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
          ),
          icon: const Icon(Icons.link),
          label: const Text('Link'),
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
          onPressed: saveAsTemplate,
          style: TextButton.styleFrom(
            foregroundColor: ColorScheme.of(context).secondary,
            backgroundColor: Colors.transparent,
            shape: const CircleBorder(),
          ),
          tooltip: 'Als Vorlage speichern',
          icon: const Icon(Icons.bookmark_add_outlined),
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
    ),
    );
  }
}
