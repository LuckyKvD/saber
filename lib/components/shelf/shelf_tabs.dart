import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/delete_folder_button.dart';
import 'package:saber/components/home/new_folder_dialog.dart';
import 'package:saber/components/home/rename_folder_button.dart';
import 'package:saber/components/shelf/pick_folder_dialog.dart';

/// Leiste mit Regal-Schildern: Hauptregal, je ein Schild pro Ordner
/// und "+ Neues Regal".
class ShelfTabs extends StatelessWidget {
  const new({
    super.key,
    required this.folders,
    required this.selected,
    required this.onSelect,
    required this.createFolder,
    required this.renameFolder,
    required this.deleteFolder,
    required this.isFolderEmpty,
    required this.moveFolder,
  });

  final List<String> folders;

  /// Name des gewählten Regals, `null` = Hauptregal.
  final String? selected;
  final void Function(String? folder) onSelect;
  final void Function(String name) createFolder;
  final Future<void> Function(String oldName, String newName) renameFolder;
  final Future<void> Function(String name) deleteFolder;
  final Future<bool> Function(String name) isFolderEmpty;

  /// Verschiebt das Regal [name] samt Inhalt in den Ordner [targetParent]
  /// (`'/'` = oberste Ebene).
  final Future<void> Function(String name, String targetParent) moveFolder;

  bool _exists(String name) => folders.contains(name);

  Future<void> _showMenu(BuildContext context, String folder) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: .min,
          children: [
            ListTile(
              title: Text(
                folder,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_square),
              title: const Text('Regal umbenennen'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move),
              title: const Text('Regal verschieben …'),
              onTap: () => Navigator.of(context).pop('move'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('Regal löschen'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'rename') {
      await showDialog(
        context: context,
        builder: (context) => RenameFolderDialog(
          folderName: folder,
          doesFolderExist: _exists,
          renameFolder: (newName) => renameFolder(folder, newName),
        ),
      );
    } else if (choice == 'move') {
      final target = await pickFolder(
        context,
        title: '„$folder“ verschieben nach',
        excludePath: '/$folder',
      );
      if (target != null) await moveFolder(folder, target);
    } else if (choice == 'delete') {
      await showDialog(
        context: context,
        builder: (context) => DeleteFolderDialog(
          folderName: folder,
          deleteFolder: deleteFolder,
          isFolderEmpty: isFolderEmpty,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: .horizontal,
        padding: const .symmetric(horizontal: 12, vertical: 6),
        children: [
          _Tab(
            label: 'Hauptregal',
            icon: Icons.collections_bookmark,
            selected: selected == null,
            onTap: () => onSelect(null),
          ),
          for (final folder in folders)
            _Tab(
              label: folder,
              selected: selected == folder,
              onTap: () => onSelect(folder),
              onLongPress: () => _showMenu(context, folder),
            ),
          _Tab(
            label: 'Neues Regal',
            icon: Icons.add,
            selected: false,
            outlined: true,
            onTap: () => showDialog(
              context: context,
              builder: (context) => NewFolderDialog(
                createFolder: createFolder,
                doesFolderExist: _exists,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool outlined;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final background = selected
        ? colorScheme.primary
        : colorScheme.surfaceContainerHigh;
    final foreground = selected ? colorScheme.onPrimary : colorScheme.onSurface;
    return Padding(
      padding: const .only(right: 8),
      child: Material(
        color: outlined ? Colors.transparent : background,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(10),
          side: outlined
              ? BorderSide(color: colorScheme.outlineVariant)
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: .circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const .symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: .min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: outlined ? colorScheme.onSurface : foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
