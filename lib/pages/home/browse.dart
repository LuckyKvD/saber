import 'dart:io' show Directory;
import 'dart:async';

import 'package:collapsible/collapsible.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:saber/components/home/local_migration_status.dart';
import 'package:saber/components/home/delete_note_button.dart';
import 'package:saber/components/home/export_note_button.dart';
import 'package:saber/components/home/grid_folders.dart';
import 'package:saber/components/home/home_layout_button.dart';
import 'package:saber/components/home/masonry_files.dart';
import 'package:saber/components/home/move_note_button.dart';
import 'package:saber/components/home/new_note_button.dart';
import 'package:saber/components/home/no_files.dart';
import 'package:saber/components/home/path_components.dart';
import 'package:saber/components/home/rename_note_button.dart';
import 'package:saber/components/home/sort_button.dart';
import 'package:saber/components/home/syncing_button.dart';
import 'package:saber/components/shelf/cover_dialogs.dart';
import 'package:saber/components/shelf/shelf_files.dart';
import 'package:saber/components/import/saber_import_tile.dart';
import 'package:saber/components/shelf/shelf_tabs.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/i18n/strings.g.dart';

class BrowsePage extends StatefulHookWidget {
  const new({super.key, String? path}) : initialPath = path;

  final String? initialPath;

  @visibleForTesting
  static DirectoryChildren? overrideChildren;

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  DirectoryChildren? children;

  /// Ordner der obersten Ebene = Regal-Schilder
  List<String> rootFolders = [];

  String? path;

  final ValueNotifier<List<String>> selectedFiles = ValueNotifier([]);

  @override
  void initState() {
    path = widget.initialPath;

    findChildrenOfPath();
    fileWriteSubscription = FileManager.fileWriteStream.stream.listen(
      fileWriteListener,
    );
    selectedFiles.addListener(_setState);

    super.initState();
  }

  @override
  void dispose() {
    selectedFiles.removeListener(_setState);
    fileWriteSubscription?.cancel();
    super.dispose();
  }

  StreamSubscription? fileWriteSubscription;
  void fileWriteListener(FileOperation event) {
    if (!event.filePath.startsWith(path ?? '/')) return;
    findChildrenOfPath(fromFileListener: true);
  }

  void _setState() => setState(() {});

  Future findChildrenOfPath({bool fromFileListener = false}) async {
    if (!mounted) return;

    if (fromFileListener) {
      // don't refresh if we're not on the home page
      final location = GoRouterState.of(context).uri.toString();
      if (!location.startsWith(RoutePaths.prefixOfHome)) return;
    }

    children =
        BrowsePage.overrideChildren ??
        await FileManager.getChildrenOfDirectory(
          path ?? '/',
          sortMetric: stows.browseSortMetric.value,
        );

    if (path == null || path!.isEmpty) {
      rootFolders = [...?children?.directories];
    } else {
      final root = await FileManager.getChildrenOfDirectory('/');
      rootFolders = [...?root?.directories];
    }

    if (mounted) setState(() {});
  }

  void onDirectoryTap(String folder) {
    selectedFiles.value = [];
    if (folder == '..') {
      path = p.dirname(path ?? '/');
      if (path == '/') path = null;
    } else {
      path = p.join(path ?? '/', folder);
    }
    context.go(HomeRoutes.browseFilePath(path ?? '/'));
    findChildrenOfPath();
  }

  void onPathComponentTap(String? newPath) {
    selectedFiles.value = [];
    if (newPath == null || newPath.isEmpty || newPath == '/') {
      newPath = null;
    }
    path = newPath;
    context.go(HomeRoutes.browseFilePath(path ?? '/'));
    findChildrenOfPath();
  }

  /// Name des gewählten Regals (erste Pfadebene), `null` = Hauptregal.
  String? get selectedShelf {
    final parts = (path ?? '').split('/').where((s) => s.isNotEmpty);
    return parts.isEmpty ? null : parts.first;
  }

  bool get isDeeperThanShelf =>
      (path ?? '').split('/').where((s) => s.isNotEmpty).length > 1;

  void selectShelf(String? folder) {
    selectedFiles.value = [];
    path = folder == null ? null : '/$folder';
    context.go(HomeRoutes.browseFilePath(path ?? '/'));
    findChildrenOfPath();
  }

  Future<void> createShelf(String folderName) async {
    await FileManager.createFolder('/$folderName');
    selectShelf(folderName);
  }

  Future<void> renameShelf(String oldName, String newName) async {
    await FileManager.renameDirectory('/$oldName', newName);
    if (selectedShelf == oldName) {
      selectShelf(newName);
    } else {
      findChildrenOfPath();
    }
  }

  Future<void> moveShelf(String name, String targetParent) async {
    final base = targetParent == '/' ? '' : targetParent;
    var newPath = '$base/$name';
    var n = 2;
    while (Directory(FileManager.documentsDirectory + newPath).existsSync()) {
      newPath = '$base/$name $n';
      n++;
    }
    final ok = await FileManager.moveDirectory('/$name', newPath);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verschieben nicht möglich.')),
      );
      findChildrenOfPath();
      return;
    }
    // Zum Ziel wechseln (oberste Ebene des neuen Pfads).
    final top = newPath.split('/').where((s) => s.isNotEmpty).first;
    selectShelf(top);
  }

  Future<void> deleteShelf(String name) async {
    await FileManager.deleteDirectory('/$name');
    if (selectedShelf == name) {
      selectShelf(null);
    } else {
      findChildrenOfPath();
    }
  }

  Future<bool> isShelfEmpty(String name) async {
    final c = await FileManager.getChildrenOfDirectory('/$name');
    return c?.isEmpty ?? true;
  }

  Future<void> createFolder(String folderName) async {
    final folderPath = '${path ?? ''}/$folderName';
    await FileManager.createFolder(folderPath);
    findChildrenOfPath();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final platform = Theme.of(context).platform;
    final crossAxisCount = MediaQuery.sizeOf(context).width ~/ 300 + 1;
    useListenable(stows.homeLayout);
    useOnListenableChange(stows.browseSortMetric, findChildrenOfPath);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            collapsedHeight: kToolbarHeight,
            expandedHeight: platform.isMaterialNative ? 200 - 8 : null,
            pinned: true,
            scrolledUnderElevation: 1,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                t.home.titles.home,
                style: TextStyle(color: colorScheme.onSurface),
              ),
              centerTitle: false,
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                bottom: 8, // less than other pages for path components
              ),
            ),
            actions: const [
              SaberImportButton(),
              BrowseSortButton(),
              HomeLayoutButton(),
              SyncingButton(),
            ],
          ),
          SliverToBoxAdapter(
            child: ShelfTabs(
              folders: rootFolders,
              selected: selectedShelf,
              onSelect: selectShelf,
              createFolder: createShelf,
              renameFolder: renameShelf,
              deleteFolder: deleteShelf,
              isFolderEmpty: isShelfEmpty,
              moveFolder: moveShelf,
            ),
          ),
          // Nur für ältere, tiefer verschachtelte Ordner
          if (isDeeperThanShelf)
            SliverToBoxAdapter(
              child: PathComponents(
                path,
                onPathComponentTap: onPathComponentTap,
              ),
            ),
          const SliverToBoxAdapter(child: LocalMigrationStatus()),
          const SliverPadding(padding: .only(bottom: 16)),
          if (path != null && (children?.directories.isNotEmpty ?? false))
          GridFolders(
            isAtRoot: path?.isEmpty ?? true,
            crossAxisCount: crossAxisCount,
            onTap: onDirectoryTap,
            createFolder: createFolder,
            doesFolderExist: (String folderName) {
              return children?.directories.contains(folderName) ?? false;
            },
            renameFolder: (String oldName, String newName) async {
              final oldPath = '${path ?? ''}/$oldName';
              await FileManager.renameDirectory(oldPath, newName);
              findChildrenOfPath();
            },
            isFolderEmpty: (String folderName) async {
              final folderPath = '${path ?? ''}/$folderName';
              final children = await FileManager.getChildrenOfDirectory(
                folderPath,
              );
              return children?.isEmpty ?? true;
            },
            deleteFolder: (String folderName) async {
              final folderPath = '${path ?? ''}/$folderName';
              await FileManager.deleteDirectory(folderPath);
              findChildrenOfPath();
            },
            folders: [
              for (final directoryPath in children?.directories ?? const [])
                directoryPath,
            ],
          ),
          if (children == null) ...[
            // loading
          ] else if (children!.isEmpty) ...[
            const SliverSafeArea(sliver: SliverToBoxAdapter(child: NoFiles())),
          ] else ...[
            SliverSafeArea(
              top: false,
              minimum: const .only(
                top: 8,
                // Allow space for the FloatingActionButton
                bottom: 70,
              ),
              sliver: stows.homeLayout.value == HomeLayout.shelf
                  ? ShelfFiles(
                      files: [
                        for (final filePath in children?.files ?? const [])
                          "${path ?? ""}/$filePath",
                      ],
                      selectedFiles: selectedFiles,
                    )
                  : MasonryFiles(
                      crossAxisCount: crossAxisCount,
                      files: [
                        for (final filePath in children?.files ?? const [])
                          "${path ?? ""}/$filePath",
                      ],
                      selectedFiles: selectedFiles,
                    ),
            ),
          ],
        ],
      ),
      floatingActionButton: NewNoteButton(
        cupertino: platform.isCupertino,
        path: path,
      ),
      persistentFooterButtons: selectedFiles.value.isEmpty
          ? null
          : [
              Collapsible(
                axis: .vertical,
                collapsed: selectedFiles.value.length != 1,
                child: RenameNoteButton(
                  existingPath: selectedFiles.value.isEmpty
                      ? ''
                      : selectedFiles.value.first,
                  unselectNotes: () => selectedFiles.value = [],
                ),
              ),
              Collapsible(
                axis: .vertical,
                collapsed: selectedFiles.value.length != 1,
                child: CoverNoteButton(
                  existingPath: selectedFiles.value.isEmpty
                      ? ''
                      : selectedFiles.value.first,
                  unselectNotes: () => selectedFiles.value = [],
                ),
              ),
              MoveNoteButton(
                filesToMove: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              DeleteNoteButton(
                filesToDelete: selectedFiles.value,
                unselectNotes: () => selectedFiles.value = [],
              ),
              ExportNoteButton(selectedFiles: selectedFiles.value),
            ],
    );
  }
}
