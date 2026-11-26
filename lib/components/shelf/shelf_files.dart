import 'dart:async';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/shelf/cover_widgets.dart';
import 'package:saber/data/extensions/change_notifier_extensions.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/note_cover.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/pages/editor/editor.dart';

const double _spineWidth = 74;
const double _gap = 6;
const double _rowHeight = 290;

/// Regal: Notizbuecher stehen als Buchruecken auf Regalbrettern.
class ShelfFiles extends StatefulWidget {
  const ShelfFiles({
    super.key,
    required this.files,
    required this.selectedFiles,
  });

  final List<String> files;
  final ValueNotifier<List<String>> selectedFiles;

  @override
  State<ShelfFiles> createState() => _ShelfFilesState();
}

class _ShelfFilesState extends State<ShelfFiles> {
  void toggleSelection(String filePath, bool selected) {
    if (selected) {
      if (!widget.selectedFiles.value.contains(filePath)) {
        widget.selectedFiles.value.add(filePath);
      }
    } else {
      widget.selectedFiles.value.remove(filePath);
    }
    widget.selectedFiles.notifyListenersPlease();
  }

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final perRow = math.max(
            1,
            ((constraints.crossAxisExtent + _gap) / (_spineWidth + _gap))
                .floor(),
          );
          final rowCount = (widget.files.length / perRow).ceil();
          return SliverList(
            delegate: SliverChildBuilderDelegate((context, row) {
              final start = row * perRow;
              final end = math.min(start + perRow, widget.files.length);
              final rowFiles = widget.files.sublist(start, end);
              final anySelected = widget.selectedFiles.value.isNotEmpty;
              return Column(
                children: [
                  SizedBox(
                    height: _rowHeight,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final file in rowFiles)
                          Padding(
                            padding: const EdgeInsets.only(right: _gap),
                            child: BookSpine(
                              filePath: file,
                              selected: widget.selectedFiles.value.contains(
                                file,
                              ),
                              isAnythingSelected: anySelected,
                              toggleSelection: toggleSelection,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const _Board(),
                  const SizedBox(height: 14),
                ],
              );
            }, childCount: rowCount),
          );
        },
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const _Board();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(color: Color(0x66000000), blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Container(height: 2, color: NoteCover.gold),
          Container(
            height: 14,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF6B4B33), Color(0xFF3F2C1E)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BookSpine extends StatefulWidget {
  BookSpine({
    required this.filePath,
    required this.selected,
    required this.isAnythingSelected,
    required this.toggleSelection,
  }) : super(key: ValueKey('BookSpine$filePath'));

  final String filePath;
  final bool selected;
  final bool isAnythingSelected;
  final void Function(String, bool) toggleSelection;

  @override
  State<BookSpine> createState() => _BookSpineState();
}

class _BookSpineState extends State<BookSpine> {
  late NoteCover cover = NoteCover.peek(widget.filePath);
  StreamSubscription? _writeSubscription;

  @override
  void initState() {
    super.initState();
    _reload();
    NoteCover.changes.addListener(_reload);
    _writeSubscription = FileManager.fileWriteStream.stream.listen((event) {
      if (event.filePath.startsWith(widget.filePath) &&
          event.filePath.endsWith('.c')) {
        _reload();
      }
    });
  }

  Future<void> _reload() async {
    final loaded = await NoteCover.load(widget.filePath);
    if (!mounted || loaded == cover) return;
    setState(() => cover = loaded);
  }

  @override
  void dispose() {
    NoteCover.changes.removeListener(_reload);
    _writeSubscription?.cancel();
    super.dispose();
  }

  String get title =>
      widget.filePath.substring(widget.filePath.lastIndexOf('/') + 1);

  void _toggle() =>
      widget.toggleSelection(widget.filePath, !widget.selected);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final height = 210.0 + (NoteCover.nameHash(widget.filePath) % 6) * 12;
    const gold = NoteCover.gold;
    const spineRadius = BorderRadius.vertical(
      top: Radius.circular(5),
      bottom: Radius.circular(2),
    );
    final hasMotif = cover.motif != 0;
    final textMotif = cover.motif == 3;

    final spine = Container(
      width: _spineWidth,
      height: height,
      decoration: const BoxDecoration(
        borderRadius: spineRadius,
        boxShadow: [
          BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(2, 0)),
        ],
      ),
      foregroundDecoration: widget.selected
          ? BoxDecoration(
              border: Border.all(color: gold, width: 3),
              borderRadius: spineRadius,
            )
          : null,
      child: ClipRRect(
        borderRadius: spineRadius,
        child: RepaintBoundary(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: CoverMaterialPainter(cover)),
              ),
              for (final top in [12.0, 19.0])
                Positioned(left: 0, right: 0, top: top, height: 2, child: const ColoredBox(color: gold)),
              for (final bottom in [12.0, 19.0])
                Positioned(left: 0, right: 0, bottom: bottom, height: 2, child: const ColoredBox(color: gold)),
              Positioned.fill(
                top: 28,
                bottom: 28,
                left: 8,
                right: 8,
                child: Column(
                  children: [
                    if (hasMotif)
                      SizedBox(
                        height: textMotif ? 62 : 40,
                        width: double.infinity,
                        child: textMotif
                            ? RotatedBox(
                                quarterTurns: 3,
                                child: CustomPaint(
                                  painter: CoverMotifPainter(cover.motif, cover.ink),
                                ),
                              )
                            : CustomPaint(
                                painter: CoverMotifPainter(cover.motif, cover.ink),
                              ),
                      ),
                    if (hasMotif) const SizedBox(height: 6),
                    Expanded(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: CoverNamePlate(
                          title: title,
                          fontSize: 15,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final Widget closed = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.isAnythingSelected ? _toggle : null,
        onSecondaryTap: _toggle,
        onLongPress: _toggle,
        child: spine,
      ),
    );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.only(bottom: widget.selected ? 14 : 0),
      child: OpenContainer(
        clipBehavior: Clip.none,
        closedColor: Colors.transparent,
        closedShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(5)),
        ),
        closedElevation: 0,
        closedBuilder: (context, action) => closed,
        openColor: colorScheme.surface,
        openBuilder: (context, action) => Editor(path: widget.filePath),
        transitionDuration: Duration(milliseconds: disableAnimations ? 0 : 300),
        routeSettings: RouteSettings(
          name: RoutePaths.editFilePath(widget.filePath),
        ),
        onClosed: (_) => _reload(),
      ),
    );
  }
}
