import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/canvas_preview.dart';
import 'package:saber/data/editor/editor_core_info.dart';

/// Feder: Seitenübersicht im Vollbild als Raster mit Miniaturen
/// (wie bei Samsung Notes). Tippen springt zur Seite, langes Drücken und
/// Ziehen sortiert um, „Auswählen" erlaubt Kopieren, Verschieben,
/// Duplizieren und Löschen mehrerer Seiten.
class PageOverview extends StatefulWidget {
  const PageOverview({
    super.key,
    required this.coreInfo,
    required this.currentPageIndex,
    required this.scrollToPage,
    required this.insertPageAfter,
    required this.duplicatePage,
    required this.deletePage,
    required this.reorderPage,
    required this.redrawAndSave,
    required this.onTransfer,
    required this.exportPdf,
    required this.showToc,
  });

  final EditorCoreInfo coreInfo;
  final int? currentPageIndex;
  final void Function(int) scrollToPage;
  final void Function(int) insertPageAfter;
  final void Function(int) duplicatePage;
  final void Function(int) deletePage;

  /// Verschiebt eine Seite (Editor kümmert sich um Rückgängig und Speichern).
  final void Function(int from, int to) reorderPage;
  final VoidCallback redrawAndSave;
  final Future<bool> Function(List<int> pageIndexes, bool move) onTransfer;

  /// Feder: markierte Seiten als PDF exportieren.
  final Future<void> Function(List<int> pageIndexes) exportPdf;

  /// Feder: Inhaltsverzeichnis öffnen.
  final VoidCallback showToc;

  @override
  State<PageOverview> createState() => _PageOverviewState();
}

class _PageOverviewState extends State<PageOverview> {
  final _selected = <int>{};
  var _selecting = false;

  int get _count => widget.coreInfo.pages.length;

  void _reorder(int from, int to) {
    if (from == to) return;
    setState(() => _selected.clear());
    widget.reorderPage(from, to);
    setState(() {});
  }

  Future<void> _transfer(bool move) async {
    final pages = _selected.toList()..sort();
    if (pages.isEmpty) return;
    final done = await widget.onTransfer(pages, move);
    if (done && mounted) {
      setState(() {
        _selected.clear();
        _selecting = false;
      });
    }
  }

  Future<void> _exportPdf() async {
    final pages = _selected.toList()..sort();
    if (pages.isEmpty) return;
    await widget.exportPdf(pages);
  }

  void _duplicateSelected() {
    final pages = _selected.toList()..sort((a, b) => b - a);
    setState(() {
      for (final i in pages) {
        widget.duplicatePage(i);
      }
      _selected.clear();
      _selecting = false;
    });
  }

  Future<void> _deleteSelected() async {
    final pages = _selected.toList()..sort((a, b) => b - a);
    if (pages.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${pages.length} Seite(n) löschen?'),
        content: const Text(
          'Die Seiten werden aus der Notiz entfernt. Mit „Rückgängig" im Editor '
          'lassen sie sich wiederholen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      for (final i in pages) {
        widget.deletePage(i);
      }
      _selected.clear();
      _selecting = false;
    });
  }

  Widget _thumb(int index, double width, {bool dragging = false}) {
    final scheme = ColorScheme.of(context);
    final page = widget.coreInfo.pages[index];
    final ratio = page.size.width / page.size.height;
    final isCurrent = index == widget.currentPageIndex;
    final isSelected = _selected.contains(index);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSelected || isCurrent
                        ? scheme.primary
                        : scheme.outlineVariant,
                    width: isSelected || isCurrent ? 3 : 1,
                  ),
                  boxShadow: dragging
                      ? const [BoxShadow(blurRadius: 12, color: Colors.black38)]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: ratio,
                  child: IgnorePointer(
                    child: FittedBox(
                      child: CanvasPreview(
                        pageIndex: index,
                        height: null,
                        coreInfo: widget.coreInfo,
                      ),
                    ),
                  ),
                ),
              ),
              if (_selecting)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: scheme.primary,
                    size: 28,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            page.bookmark == null ? '${index + 1}' : '${index + 1} · ${page.bookmark}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isCurrent ? scheme.primary : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 190).floor().clamp(2, 6);
    const spacing = 12.0;
    final tileWidth = (width - spacing * (columns + 1)) / columns;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selecting
              ? '${_selected.length} ausgewählt'
              : 'Seiten ($_count)',
        ),
        actions: [
          if (!_selecting)
            IconButton(
              tooltip: 'Inhaltsverzeichnis',
              icon: const Icon(Icons.bookmarks_outlined),
              onPressed: widget.showToc,
            ),
          if (!_selecting)
            IconButton(
              tooltip: 'Seite am Ende einfügen',
              icon: const Icon(Icons.add),
              onPressed: () => setState(() {
                widget.insertPageAfter(_count - 1);
              }),
            ),
          TextButton(
            onPressed: () => setState(() {
              _selecting = !_selecting;
              _selected.clear();
            }),
            child: Text(_selecting ? 'Fertig' : 'Auswählen'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(spacing),
        child: Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < _count; i++)
              DragTarget<int>(
                onWillAcceptWithDetails: (d) => !_selecting && d.data != i,
                onAcceptWithDetails: (d) => _reorder(d.data, i),
                builder: (context, candidates, _) {
                  final tile = GestureDetector(
                    onTap: () {
                      if (_selecting) {
                        setState(() {
                          if (!_selected.remove(i)) _selected.add(i);
                        });
                      } else {
                        widget.scrollToPage(i);
                        Navigator.of(context).pop();
                      }
                    },
                    child: Opacity(
                      opacity: candidates.isNotEmpty ? 0.5 : 1,
                      child: _thumb(i, tileWidth),
                    ),
                  );
                  if (_selecting) return tile;
                  return LongPressDraggable<int>(
                    data: i,
                    feedback: Material(
                      color: Colors.transparent,
                      child: _thumb(i, tileWidth * 0.8, dragging: true),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.3,
                      child: _thumb(i, tileWidth),
                    ),
                    child: tile,
                  );
                },
              ),
          ],
        ),
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.content_copy),
                      label: const Text('Kopieren nach …'),
                      onPressed: _selected.isEmpty ? null : () => _transfer(false),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.drive_file_move),
                      label: const Text('Verschieben nach …'),
                      onPressed: _selected.isEmpty ? null : () => _transfer(true),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const Text('Als PDF'),
                      onPressed: _selected.isEmpty ? null : _exportPdf,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy_all),
                      label: const Text('Duplizieren'),
                      onPressed: _selected.isEmpty ? null : _duplicateSelected,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Löschen'),
                      onPressed: _selected.isEmpty ? null : _deleteSelected,
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
