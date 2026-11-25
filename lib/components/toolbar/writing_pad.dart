import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/toolbar/writing_pad_guide.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:stow/stow.dart';
import 'package:saber/data/tools/pen.dart';

/// Schreibfeld (Easy-Writing): Du schreibst groß in das Feld, die Schrift
/// erscheint verkleinert als normale Handschrift in der Notiz.
///
/// Zuordnung: Ein Punkt im Feld (vx, py) landet in der Notiz bei
/// x = Rand + (vx - lineStartV) * scale, y = lineY + py * scale.
/// "vx" ist die waagerechte Position im endlos nach rechts laufenden Feld.
class WritingPad extends StatefulWidget {
  const new({
    super.key,
    required this.pen,
    required this.pages,
    required this.startPageIndex,
    required this.ensurePage,
    required this.addStroke,
    required this.undo,
    required this.close,
    required this.controller,
    required this.owner,
    required this.onGuideChanged,
    required this.cell,
  });

  /// Stift, dessen Farbe und Dicke verwendet werden.
  final Pen pen;
  final List<EditorPage> pages;
  final int startPageIndex;

  /// Legt Seiten bis einschließlich [pageIndex] an (plus eine leere Seite).
  final void Function(int pageIndex) ensurePage;

  /// Fügt einen fertigen Strich in die Notiz ein (mit Rückgängig-Verlauf).
  final void Function(Stroke stroke) addStroke;
  final VoidCallback undo;
  final VoidCallback close;
  final WritingPadController controller;

  /// Notiz, zu der das Schreibfeld gehört (für den Rahmen auf dem Blatt).
  final Object owner;

  /// Kästchengröße (Zeilenhöhe) der Notiz in Notiz-Einheiten.
  final double cell;

  /// Der Rahmen auf dem Blatt hat sich bewegt: Seite neu zeichnen.
  final VoidCallback onGuideChanged;

  @override
  State<WritingPad> createState() => _WritingPadState();
}

class _WritingPadState extends State<WritingPad> {
  static const _noteMargin = 40.0;

  late int pageIndex;
  double lineY = _noteMargin;
  double lineStartV = 0;

  /// Linker Rand der Zeile in der Notiz (per Tipp oder Pfeil verschiebbar).
  double startX = _noteMargin;

  /// Waagerechter Versatz der Ansicht im endlosen Feld.
  double viewX = 0;

  /// Striche der aktuellen Zeile im Feld (virtuelle Koordinaten).
  final padStrokes = <Stroke>[];
  Stroke? currentPadStroke;
  List<(Offset, double?)> currentRaw = [];

  /// Eingefügte Striche der aktuellen Zeile (für das Rückgängig im Feld).
  double padWidth = 600;
  double padHeight = 200;

  double get cell => math.max(10, widget.cell);

  /// Höhe einer Schreibzeile in Kästchen (1 bis 3).
  int get cells => stows.easyWritingCells.value;

  /// Verkleinerung: das Feld ([padHeight] hoch) entspricht genau [cells] Kästchen.
  double get scale => _lineHeight / padHeight;

  /// Kleiner Leerraum links, damit Striche links vom ersten Strich im Rahmen bleiben.
  double get _slackV => padWidth * 0.03;

  @override
  void initState() {
    super.initState();
    pageIndex = widget.startPageIndex.clamp(0, widget.pages.length - 1);
    lineY = _firstFreeY(pageIndex);
    widget.controller.addListener(_onController);
    WidgetsBinding.instance.addPostFrameCallback((_) => _publishGuide());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    widget.controller.disarm();
    WritingPadGuide.clear();
    super.dispose();
  }

  void _onController() {
    final c = widget.controller;
    final target = c.target;
    if (target != null && c.targetPage != null) {
      pageIndex = c.targetPage!.clamp(0, widget.pages.length - 1);
      final page = widget.pages[pageIndex];
      startX = target.dx.clamp(0, page.size.width - 200).toDouble();
      lineY = _snapY(
        (target.dy - _lineHeight / 2).clamp(0, page.size.height - _lineHeight),
      );
      padStrokes.clear();
      lineStartV = viewX;
      c.target = null;
      c.targetPage = null;
    }
    final delta = c.moveDelta;
    if (delta != null) {
      final page = widget.pages[pageIndex];
      startX = (startX + delta.dx).clamp(0, page.size.width - 200).toDouble();
      lineY = (lineY + delta.dy)
          .clamp(0, page.size.height - _lineHeight)
          .toDouble();
      c.moveDelta = null;
    }
    if (c.snapRequested) {
      c.snapRequested = false;
      lineY = _snapY(lineY);
    }
    if (mounted) setState(() {});
    _publishGuide();
  }

  /// Teilt der Seite mit, wo die nächste Zeile entsteht.
  void _publishGuide() {
    if (!mounted) return;
    final page = widget.pages[pageIndex];
    WritingPadGuide.owner = widget.owner;
    WritingPadGuide.pageIndex = pageIndex;
    WritingPadGuide.rect = Rect.fromLTWH(
      startX - _slackV * scale,
      lineY,
      math.max(100, page.size.width - _noteMargin - startX),
      _lineHeight,
    ).inflate(3);
    widget.onGuideChanged();
  }

  void _nudge(int cellsDown) {
    setState(() {
      final page = widget.pages[pageIndex];
      lineY = (_snapY(lineY) + cellsDown * cell)
          .clamp(0, page.size.height - _lineHeight)
          .toDouble();
    });
    _publishGuide();
  }

  double _firstFreeY(int index) {
    final page = widget.pages[index];
    if (page.strokes.isEmpty) return _snapY(_noteMargin);
    var maxY = 0.0;
    for (final stroke in page.strokes) {
      maxY = math.max(maxY, stroke.maxY);
    }
    return _snapY(maxY + cell * 0.5, up: true);
  }

  /// Rastet [y] auf das Kästchenraster der Notiz ein.
  double _snapY(double y, {bool up = false}) {
    final n = y / cell;
    return (up ? n.ceil() : n.round()) * cell;
  }

  Offset _toNote(double vx, double py) => Offset(
    startX + (vx - lineStartV) * scale,
    lineY + py * scale,
  );

  double get _lineHeight => cells * cell;

  /// Strichstärke in der Notiz: dünner als normal und mit wenig Druckvarianz,
  /// damit kleine Schrift lesbar bleibt.
  StrokeOptions _noteOptions(Pen pen) {
    final factor = stows.easyWritingThickness.value / 100;
    final options = pen.options.copyWith(isComplete: true);
    options.size = math.max(0.8, pen.options.size * factor);
    options.thinning = math.min(pen.options.thinning, 0.05);
    return options;
  }

  void _newLine({double? startAtV}) {
    setState(() {
      padStrokes.clear();
      lineY += _lineHeight;
      final page = widget.pages[pageIndex];
      if (lineY + _lineHeight > page.size.height - _noteMargin) {
        pageIndex++;
        widget.ensurePage(pageIndex);
        lineY = _snapY(_noteMargin);
      }
      lineStartV = startAtV ?? (viewX + _slackV);
    });
    _publishGuide();
  }

  void _space() {
    setState(() => viewX += padWidth * 0.12);
  }

  void _pointerDown(PointerDownEvent e) {
    if (!_accepts(e.kind)) return;
    final vx = viewX + e.localPosition.dx;
    final page = widget.pages[pageIndex];

    if (padStrokes.isEmpty) {
      // Erster Strich einer Zeile beginnt genau am linken Rand der Notiz.
      lineStartV = vx - _slackV;
    } else if (_toNote(vx, 0).dx > page.size.width - _noteMargin) {
      _newLine(startAtV: vx - _slackV);
    }

    final pen = widget.pen;
    currentRaw = [(Offset(vx, e.localPosition.dy), _pressure(e))];
    currentPadStroke = Stroke(
      color: pen.color,
      pressureEnabled: pen.pressureEnabled,
      options: _noteOptions(pen)
        ..size = _noteOptions(pen).size / scale
        ..isComplete = false,
      pageIndex: pageIndex,
      page: widget.pages[pageIndex],
      toolId: pen.toolId,
    )..addPoint(Offset(vx, e.localPosition.dy), _pressure(e));
    setState(() {});
  }

  void _pointerMove(PointerMoveEvent e) {
    final stroke = currentPadStroke;
    if (stroke == null) return;
    final vx = viewX + e.localPosition.dx;
    final p = Offset(vx, e.localPosition.dy.clamp(0, padHeight));
    currentRaw.add((p, _pressure(e)));
    stroke.addPoint(p, _pressure(e));
    setState(() {});
  }

  void _pointerUp(PointerEvent e) {
    final padStroke = currentPadStroke;
    currentPadStroke = null;
    if (padStroke == null) return;
    final raw = currentRaw;
    currentRaw = [];
    if (raw.isEmpty) {
      setState(() {});
      return;
    }

    padStroke.options.isComplete = true;
    padStroke.markPolygonNeedsUpdating();

    // Verkleinerte Kopie in die Notiz einfügen.
    final pen = widget.pen;
    final noteStroke = Stroke(
      color: pen.color,
      pressureEnabled: pen.pressureEnabled,
      options: _noteOptions(pen),
      pageIndex: pageIndex,
      page: widget.pages[pageIndex],
      toolId: pen.toolId,
    );
    for (final (point, pressure) in raw) {
      noteStroke.addPoint(_toNote(point.dx, point.dy), pressure);
    }
    if (!noteStroke.isEmpty) widget.addStroke(noteStroke);

    padStrokes.add(padStroke);

    // Nähert sich die Schrift dem rechten Rand, läuft die Ansicht weiter.
    final endLocalX = raw.last.$1.dx - viewX;
    if (endLocalX > padWidth * 0.7) {
      viewX = raw.last.$1.dx - padWidth * 0.25;
    }
    setState(() {});
  }

  bool _accepts(PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.mouse) {
      return true;
    }
    return kind == PointerDeviceKind.touch &&
        stows.editorFingerDrawing.value;
  }

  double? _pressure(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus) return null;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return null;
    return ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
  }

  void _undo() {
    widget.undo();
    setState(() {
      if (padStrokes.isNotEmpty) padStrokes.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final height = math.min(240.0, MediaQuery.sizeOf(context).height * 0.3);
    padHeight = height;

    return Material(
      color: colorScheme.surfaceContainerHigh,
      child: SizedBox(
        height: height + 44,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    _chips(
                      'Höhe',
                      stows.easyWritingCells,
                      const [(1, '1 Kästchen'), (2, '2 Kästchen'), (3, '3 Kästchen')],
                    ),
                    const SizedBox(width: 12),
                    _chips(
                      'Strich',
                      stows.easyWritingThickness,
                      const [(25, 'Fein'), (45, 'Mittel'), (70, 'Kräftig')],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Ort wählen: danach in die Notiz tippen',
                      isSelected: widget.controller.armed,
                      onPressed: () => widget.controller.armed
                          ? widget.controller.disarm()
                          : widget.controller.arm(),
                      icon: const Icon(Icons.ads_click),
                    ),
                    IconButton(
                      tooltip: 'Zeile ein Kästchen nach oben',
                      onPressed: () => _nudge(-1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Zeile ein Kästchen nach unten',
                      onPressed: () => _nudge(1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                    IconButton(
                      tooltip: 'Leerzeichen',
                      onPressed: _space,
                      icon: const Icon(Icons.space_bar),
                    ),
                    IconButton(
                      tooltip: 'Neue Zeile',
                      onPressed: () => _newLine(),
                      icon: const Icon(Icons.keyboard_return),
                    ),
                    IconButton(
                      tooltip: 'Rückgängig',
                      onPressed: _undo,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip: 'Schreibfeld schließen',
                      onPressed: widget.close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  padWidth = constraints.maxWidth;
                  return Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _pointerDown,
                    onPointerMove: _pointerMove,
                    onPointerUp: _pointerUp,
                    onPointerCancel: _pointerUp,
                    child: ClipRect(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          border: Border(
                            top: BorderSide(color: colorScheme.outlineVariant),
                          ),
                        ),
                        child: CustomPaint(
                          size: Size.infinite,
                          painter: _PadPainter(
                            strokes: [
                              ...padStrokes,
                              if (currentPadStroke != null) currentPadStroke!,
                            ],
                            viewX: viewX,
                            guide: colorScheme.outlineVariant,
                            midLine: padHeight / 2,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chips(String label, Stow<dynamic, int, dynamic> pref, List<(int, String)> options) {
    return ListenableBuilder(
      listenable: pref,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 6),
            for (final (value, text) in options)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(text),
                  selected: pref.value == value,
                  onSelected: (_) {
                    pref.value = value;
                    setState(() {});
                    _publishGuide();
                  },
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PadPainter extends CustomPainter {
  const _PadPainter({
    required this.strokes,
    required this.viewX,
    required this.guide,
    required this.midLine,
  });

  final List<Stroke> strokes;
  final double viewX;
  final Color guide;
  final double midLine;

  @override
  void paint(Canvas canvas, Size size) {
    // Hilfslinie in der Mitte (Schreibzeile).
    canvas.drawLine(
      Offset(0, midLine),
      Offset(size.width, midLine),
      Paint()
        ..color = guide.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );

    canvas.save();
    canvas.translate(-viewX, 0);
    for (final stroke in strokes) {
      canvas.drawPath(stroke.highQualityPath, Paint()..color = stroke.color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PadPainter oldDelegate) => true;
}
