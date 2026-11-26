import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/components/theming/saber_theme.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/i18n/strings.g.dart';

class EditorPageManager extends StatefulWidget {
  const new({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.redrawAndSave,
    required this.insertPageAfter,
    required this.duplicatePage,
    required this.clearPage,
    required this.deletePage,
    required this.transformationController,
    this.scrollToPageOverride,
    this.onTransfer,
  });

  final EditorCoreInfo coreInfo;
  final int? currentPageIndex;
  final VoidCallback redrawAndSave;

  final void Function(int) insertPageAfter;
  final void Function(int) duplicatePage;
  final void Function(int) clearPage;
  final void Function(int) deletePage;

  final TransformationController transformationController;

  /// Feder: Scrollen je nach Blätter-Richtung (vertikal/horizontal).
  final void Function(int)? scrollToPageOverride;

  /// Feder: ausgewählte Seiten in ein anderes Notizbuch kopieren/verschieben.
  /// Gibt `true` zurück, wenn die Übertragung erfolgt ist.
  final Future<bool> Function(List<int> pageIndexes, bool move)? onTransfer;

  @override
  State<EditorPageManager> createState() => _EditorPageManagerState();
}

class _EditorPageManagerState extends State<EditorPageManager> {
  final selected = <int>{};

  Future<void> _transfer(bool move) async {
    final onTransfer = widget.onTransfer;
    if (onTransfer == null || selected.isEmpty) return;
    final pages = selected.toList()..sort();
    final done = await onTransfer(pages, move);
    if (done && mounted) setState(selected.clear);
  }

  Widget _buildHeader() {
    if (widget.onTransfer == null) return const SizedBox.shrink();
    return Padding(
      padding: const .fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            selected.isEmpty
                ? 'Seiten ankreuzen, um sie in ein anderes Notizbuch zu übertragen'
                : '${selected.length} Seite(n) ausgewählt',
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            icon: const Icon(Icons.content_copy),
            label: const Text('Kopieren nach …'),
            onPressed: selected.isEmpty ? null : () => _transfer(false),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.drive_file_move),
            label: const Text('Verschieben nach …'),
            onPressed: selected.isEmpty ? null : () => _transfer(true),
          ),
        ],
      ),
    );
  }

  void scrollToPage(int pageIndex) {
    final override = widget.scrollToPageOverride;
    if (override != null) {
      override(pageIndex);
      return;
    }
    CanvasGestureDetector.scrollToPage(
      pageIndex: pageIndex,
      pages: widget.coreInfo.pages,
      screenWidth: MediaQuery.sizeOf(context).width,
      transformationController: widget.transformationController,
    );
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final cupertino = platform.isCupertino;
    return SizedBox(
      width: cupertino ? null : 300,
      height: cupertino ? 600 : null,
      child: ReorderableListView.builder(
        header: _buildHeader(),
        buildDefaultDragHandles: false,
        itemCount: widget.coreInfo.pages.length,
        itemBuilder: (context, pageIndex) {
          final isEmptyLastPage =
              pageIndex == widget.coreInfo.pages.length - 1 &&
              widget.coreInfo.pages[pageIndex].isEmpty;
          return InkWell(
            key: ValueKey(pageIndex),
            onTap: () => scrollToPage(pageIndex),
            child: Padding(
              padding: const .all(8),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: .spaceAround,
                    children: [
                      Checkbox(
                        value: selected.contains(pageIndex),
                        onChanged: widget.onTransfer == null
                            ? null
                            : (value) => setState(() {
                                if (value ?? false) {
                                  selected.add(pageIndex);
                                } else {
                                  selected.remove(pageIndex);
                                }
                              }),
                      ),
                      Text(
                        '${pageIndex + 1} / ${widget.coreInfo.pages.length}',
                      ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: cupertino ? 100 : 110,
                          maxHeight: 250,
                        ),
                        child: FittedBox(
                          child: CanvasPreview(
                            pageIndex: pageIndex,
                            height: null,
                            coreInfo: widget.coreInfo,
                          ),
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: ReorderableDragStartListener(
                          index: pageIndex,
                          child: const Padding(
                            padding: .all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: .center,
                    children: [
                      IconButton(
                        tooltip: t.editor.menu.insertPage,
                        icon: const AdaptiveIcon(
                          icon: Icons.insert_page_break,
                          cupertinoIcon: CupertinoIcons.add,
                        ),
                        onPressed: () => setState(() {
                          selected.clear();
                          widget.insertPageAfter(pageIndex);
                          scrollToPage(pageIndex + 1);
                        }),
                      ),
                      IconButton(
                        tooltip: t.editor.menu.duplicatePage,
                        icon: const AdaptiveIcon(
                          icon: Icons.content_copy,
                          cupertinoIcon: CupertinoIcons.doc_on_clipboard,
                        ),
                        onPressed: () => setState(() {
                          selected.clear();
                          widget.duplicatePage(pageIndex);
                          scrollToPage(pageIndex + 1);
                        }),
                      ),
                      IconButton(
                        tooltip: t.editor.menu.clearPage(
                          page: pageIndex + 1,
                          totalPages: widget.coreInfo.pages.length,
                        ),
                        icon: const Icon(Icons.cleaning_services),
                        onPressed: isEmptyLastPage
                            ? null
                            : () => setState(() {
                                widget.clearPage(pageIndex);
                                scrollToPage(pageIndex);
                              }),
                      ),
                      IconButton(
                        tooltip: t.editor.menu.deletePage,
                        icon: const AdaptiveIcon(
                          icon: Icons.delete,
                          cupertinoIcon: CupertinoIcons.delete,
                        ),
                        onPressed: isEmptyLastPage
                            ? null
                            : () => setState(() {
                                selected.clear();
                                widget.deletePage(pageIndex);
                                scrollToPage(pageIndex);
                              }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
        onReorderItem: (oldIndex, newIndex) {
          if (oldIndex == newIndex) return;
          setState(selected.clear);
          widget.coreInfo.pages.insert(
            newIndex,
            widget.coreInfo.pages.removeAt(oldIndex),
          );

          // reassign pageIndex of pages' strokes and images
          for (int i = 0; i < widget.coreInfo.pages.length; i++) {
            final page = widget.coreInfo.pages[i];
            page.updatePageIndex(i);
          }

          widget.redrawAndSave();
        },
      ),
    );
  }
}
