import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_canvas_background_painter.dart';
import 'package:saber/components/canvas/_canvas_painter.dart';
import 'package:saber/components/canvas/canvas_image.dart';
import 'package:saber/components/canvas/inner_canvas.dart';
import 'package:saber/components/toolbar/writing_pad_guide.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/extensions/color_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/pressure_curve.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:sbn/canvas_background_pattern.dart';

/// Schreibfeld (Easy-Writing) nach dem Vorbild von Samsung Notes:
/// Das Feld ist eine Lupe auf das echte Blatt. Der blaue Rahmen auf dem Blatt
/// zeigt, welcher Ausschnitt im Feld vergrößert erscheint. Was du im Feld
/// schreibst, entsteht direkt im Blatt (mit der echten Stiftdicke).
class WritingPad extends StatefulWidget {
  const new({
    super.key,
    required this.controller,
    required this.coreInfo,
    required this.enabled,
    required this.onStrokeStart,
    required this.onStrokeUpdate,
    required this.onStrokeEnd,
  });

  final WritingPadController controller;
  final EditorCoreInfo coreInfo;

  /// false bei schreibgeschützten Notizen.
  final bool enabled;

  /// Strich beginnt: Seite, Position in Seitenkoordinaten, Druck (0 bis 1).
  final void Function(int pageIndex, Offset position, double? pressure)
  onStrokeStart;
  final void Function(Offset position, double? pressure) onStrokeUpdate;
  final VoidCallback onStrokeEnd;

  @override
  State<WritingPad> createState() => _WritingPadState();
}

class _WritingPadState extends State<WritingPad> {
  static const _barHeight = 44.0;

  int? _pointer;
  Offset _lastPagePosition = Offset.zero;
  double _padWidth = 0;
  double _padHeight = 0;

  /// Lage der Umbruch-Marke in Prozent der Feldbreite (bleibt gespeichert).
  late double _marker = stows.easyWritingMarker.value / 100;

  WritingPadController get c => widget.controller;

  double get _zoom => _padWidth <= 0 ? 1 : _padWidth / c.width;

  Offset _toPage(Offset local) {
    final x = local.dx.clamp(0, _padWidth).toDouble();
    final y = local.dy.clamp(0, _padHeight).toDouble();
    return Offset(c.left + x / _zoom, c.top + y / _zoom);
  }

  bool _accepts(PointerDeviceKind kind) {
    if (!widget.enabled) return false;
    if (kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus ||
        kind == PointerDeviceKind.mouse) {
      return true;
    }
    return kind == PointerDeviceKind.touch && stows.editorFingerDrawing.value;
  }

  double? _pressure(PointerEvent e) {
    if (e.kind != PointerDeviceKind.stylus &&
        e.kind != PointerDeviceKind.invertedStylus) {
      return null;
    }
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return null;
    final t = ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0);
    return applyPressureCurve(t.toDouble());
  }

  void _pointerDown(PointerDownEvent e) {
    if (_pointer != null || !_accepts(e.kind)) return;
    _pointer = e.pointer;
    _lastPagePosition = _toPage(e.localPosition);
    widget.onStrokeStart(c.pageIndex, _lastPagePosition, _pressure(e));
  }

  void _pointerMove(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _lastPagePosition = _toPage(e.localPosition);
    widget.onStrokeUpdate(_lastPagePosition, _pressure(e));
  }

  void _pointerUp(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    widget.onStrokeEnd();
    // Erst nach dem Strich weiterrücken, nie mittendrin (sonst springt die Schrift).
    c.afterStroke(lastX: _lastPagePosition.dx, markerFraction: _marker);
  }

  /// Das Feld kennt seine Größe erst nach dem Layout; der Rahmen auf dem
  /// Blatt muss genau diesem Seitenverhältnis folgen.
  void _syncSize(double width, double height) {
    if ((width - _padWidth).abs() < 0.5 && (height - _padHeight).abs() < 0.5) {
      return;
    }
    _padWidth = width;
    _padHeight = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _padWidth > 0) c.setAspect(_padHeight / _padWidth);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final brightness = theme.brightness;
    final invert = stows.editorAutoInvert.value && brightness == Brightness.dark;
    final invertColorScheme =
        !stows.editorAutoInvert.value && brightness == Brightness.dark;

    final pages = widget.coreInfo.pages;
    final page = pages[c.pageIndex.clamp(0, pages.length - 1)];

    final screenWidth = MediaQuery.sizeOf(context).width;
    final padHeight = (screenWidth * 0.22).clamp(120.0, 230.0).toDouble();

    return Material(
      color: colorScheme.surfaceContainerHigh,
      child: SizedBox(
        height: padHeight + _barHeight,
        child: Column(
          children: [
            SizedBox(
              height: _barHeight,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.drag_indicator,
                    size: 20,
                    color: colorScheme.outline,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Zurück',
                    onPressed: () => c.shift(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Weiter',
                    onPressed: () => c.shift(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Neue Zeile',
                    onPressed: c.newLine,
                    icon: const Icon(Icons.keyboard_return),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _syncSize(constraints.maxWidth, constraints.maxHeight);
                  final markerX = _marker * constraints.maxWidth;
                  return Stack(
                    children: [
                      // 1. Hintergrund (Kästchen, Linien)
                      Positioned.fill(
                        child: ClipRect(
                          child: CustomPaint(
                            painter: _LupeBackgroundPainter(
                              controller: c,
                              page: page,
                              invert: invert,
                              backgroundColor:
                                  widget.coreInfo.backgroundColor ??
                                  InnerCanvas.defaultBackgroundColor,
                              pattern: widget.coreInfo.backgroundPattern,
                              lineHeight: widget.coreInfo.lineHeight,
                              lineThickness: widget.coreInfo.lineThickness,
                              primaryColor: colorScheme.primary.withInversion(
                                invertColorScheme,
                              ),
                              secondaryColor: colorScheme.secondary
                                  .withInversion(invertColorScheme),
                            ),
                          ),
                        ),
                      ),
                      // 2. Hintergrundbild und Bilder (wie auf dem Blatt)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minWidth: 0,
                              minHeight: 0,
                              maxWidth: double.infinity,
                              maxHeight: double.infinity,
                              child: Transform(
                                alignment: Alignment.topLeft,
                                transform: Matrix4.identity()
                                  ..scale(_zoom, _zoom)
                                  ..translate(-c.left, -c.top),
                                child: SizedBox(
                                  width: page.size.width,
                                  height: page.size.height,
                                  child: DeferredPointerHandler(
                                    child: Stack(
                                    children: [
                                      if (page.backgroundImage != null)
                                        CanvasImage(
                                          filePath: widget.coreInfo.filePath,
                                          image: page.backgroundImage!,
                                          pageSize: page.size,
                                          setAsBackground: null,
                                          isBackground: true,
                                          readOnly: true,
                                        ),
                                      for (final image in page.images)
                                        CanvasImage(
                                          filePath: widget.coreInfo.filePath,
                                          image: image,
                                          pageSize: page.size,
                                          setAsBackground: null,
                                          readOnly: true,
                                        ),
                                    ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 3. Striche und Umbruch-Marke
                      Positioned.fill(
                        child: ClipRect(
                          child: CustomPaint(
                            painter: _LupeStrokesPainter(
                              controller: c,
                              page: page,
                              pageIndex: c.pageIndex,
                              totalPages: pages.length,
                              invert: invert,
                              primaryColor: colorScheme.primary.withInversion(
                                invertColorScheme,
                              ),
                              textStyle: theme.textTheme.bodyMedium!,
                              markerX: markerX,
                              markerColor: colorScheme.primary,
                              divider: colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      // 4. Eingabefläche für den Stift
                      Positioned.fill(
                        child: Listener(
                          behavior: HitTestBehavior.opaque,
                          onPointerDown: _pointerDown,
                          onPointerMove: _pointerMove,
                          onPointerUp: _pointerUp,
                          onPointerCancel: _pointerUp,
                        ),
                      ),
                      // Umbruch-Marke: nach links/rechts schiebbar.
                      Positioned(
                        left: markerX - 22,
                        top: 0,
                        width: 44,
                        height: 36,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) {
                            final x = (_marker * _padWidth + d.delta.dx);
                            setState(() {
                              _marker = (x / _padWidth).clamp(0.4, 0.92).toDouble();
                            });
                          },
                          onHorizontalDragEnd: (_) {
                            stows.easyWritingMarker.value = (_marker * 100)
                                .round();
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Gemeinsame Abbildung: Seitenkoordinaten -> Feld (Rahmen füllt das Feld).
void _applyWindow(Canvas canvas, Size size, Rect window) {
  canvas.clipRect(Offset.zero & size);
  canvas.scale(size.width / window.width);
  canvas.translate(-window.left, -window.top);
}

/// Unterste Ebene: Hintergrund (Kästchen, Linien) des Ausschnitts, vergrößert.
class _LupeBackgroundPainter extends CustomPainter {
  _LupeBackgroundPainter({
    required this.controller,
    required this.page,
    required this.invert,
    required this.backgroundColor,
    required this.pattern,
    required this.lineHeight,
    required this.lineThickness,
    required this.primaryColor,
    required this.secondaryColor,
  }) : super(repaint: controller);

  final WritingPadController controller;
  final EditorPage page;
  final bool invert;
  final Color backgroundColor;
  final CanvasBackgroundPattern pattern;
  final int lineHeight;
  final int lineThickness;
  final Color primaryColor;
  final Color secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final window = controller.rect;
    if (window.width <= 0) return;
    canvas.save();
    _applyWindow(canvas, size, window);

    final hasBackgroundImage = page.backgroundImage != null;
    CanvasBackgroundPainter(
      invert: invert,
      backgroundColor: hasBackgroundImage ? Colors.white : backgroundColor,
      backgroundPattern: hasBackgroundImage
          ? CanvasBackgroundPattern.none
          : pattern,
      lineHeight: lineHeight,
      lineThickness: lineThickness,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    ).paint(canvas, page.size);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_LupeBackgroundPainter oldDelegate) => true;
}

/// Oberste Ebene: Striche des Ausschnitts, vergrößert, dazu die Umbruch-Marke.
class _LupeStrokesPainter extends CustomPainter {
  _LupeStrokesPainter({
    required this.controller,
    required this.page,
    required this.pageIndex,
    required this.totalPages,
    required this.invert,
    required this.primaryColor,
    required this.textStyle,
    required this.markerX,
    required this.markerColor,
    required this.divider,
  }) : super(repaint: Listenable.merge([controller, page]));

  final WritingPadController controller;
  final EditorPage page;
  final int pageIndex;
  final int totalPages;
  final bool invert;
  final Color primaryColor;
  final TextStyle textStyle;
  final double markerX;
  final Color markerColor;
  final Color divider;

  @override
  void paint(Canvas canvas, Size size) {
    final window = controller.rect;
    if (window.width <= 0) return;

    canvas.save();
    _applyWindow(canvas, size, window);
    final current = Pen.currentStroke;
    CanvasPainter(
      invert: invert,
      strokes: page.strokes,
      laserStrokes: page.laserStrokes,
      currentStroke: current?.pageIndex == pageIndex ? current : null,
      currentSelection: null,
      primaryColor: primaryColor,
      page: page,
      showPageIndicator: false,
      pageIndex: pageIndex,
      totalPages: totalPages,
      currentScale: 1,
      defaultTextStyle: textStyle,
    ).paint(canvas, page.size);
    canvas.restore();

    // Grauer Bereich hinter der Marke: hier rückt der Ausschnitt weiter.
    canvas.drawRect(
      Rect.fromLTRB(markerX, 0, size.width, size.height),
      Paint()..color = Colors.black.withValues(alpha: 0.06),
    );
    canvas.drawLine(
      Offset(markerX, 0),
      Offset(markerX, size.height),
      Paint()
        ..color = markerColor.withValues(alpha: 0.7)
        ..strokeWidth = 1.5,
    );
    // Fähnchen oben an der Marke.
    final pin = Path()
      ..moveTo(markerX - 11, 0)
      ..lineTo(markerX + 11, 0)
      ..lineTo(markerX + 11, 14)
      ..lineTo(markerX, 24)
      ..lineTo(markerX - 11, 14)
      ..close();
    canvas.drawPath(pin, Paint()..color = markerColor);
    canvas.drawLine(
      Offset.zero,
      Offset(size.width, 0),
      Paint()
        ..color = divider
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_LupeStrokesPainter oldDelegate) => true;
}
