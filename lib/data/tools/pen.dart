import 'dart:async';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/shape_pen.dart';
import 'package:saber/data/tools/shape_recognizer.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/tool_id.dart';

class Pen extends Tool {
  @protected
  @visibleForTesting
  new({
    required this.name,
    required this.sizeMin,
    required this.sizeMax,
    required this.sizeStep,
    required this.icon,
    required this.options,
    required this.pressureEnabled,
    required this.color,
    required this.toolId,
  });

  new fountainPen()
    : name = t.editor.pens.fountainPen,
      sizeMin = 1,
      sizeMax = 25,
      sizeStep = 1,
      icon = fountainPenIcon,
      options = stows.lastFountainPenOptions.value,
      pressureEnabled = true,
      color = Color(stows.lastFountainPenColor.value),
      toolId = .fountainPen;

  new ballpointPen()
    : name = t.editor.pens.ballpointPen,
      sizeMin = 1,
      sizeMax = 25,
      sizeStep = 1,
      icon = ballpointPenIcon,
      options = stows.lastBallpointPenOptions.value,
      pressureEnabled = false,
      color = Color(stows.lastBallpointPenColor.value),
      toolId = .ballpointPen;

  final String name;
  final double sizeMin, sizeMax, sizeStep;
  late final int sizeStepsBetweenMinAndMax = ((sizeMax - sizeMin) / sizeStep)
      .round();
  final Object icon;

  @override
  final ToolId toolId;

  static const fountainPenIcon = FontAwesomeIcons.penFancy;
  static const ballpointPenIcon = FontAwesomeIcons.pen;

  static Stroke? currentStroke;
  Color color;
  bool pressureEnabled;
  StrokeOptions options;

  static var _currentPen = Pen.fountainPen();
  static Pen get currentPen => _currentPen;
  static set currentPen(Pen currentPen) {
    assert(
      currentPen is! Highlighter,
      'Use Highlighter.currentHighlighter instead',
    );
    assert(currentPen is! Pencil, 'Use Pencil.currentPencil instead');
    _currentPen = currentPen;
  }

  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    currentStroke = Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(isComplete: false)
        ..thinning = toolId == .fountainPen
            ? stows.fountainThinning.value / 100
            : options.thinning,
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );
    if (holdToShape) _resetHold();
    onDragUpdate(position, pressure);
  }

  /// Formen-Halten: Bleibt der Stift am Ende eines Strichs kurz stehen,
  /// wird die erkannte Form (Linie, Rechteck, Kreis, Dreieck) angezeigt und
  /// beim Abheben übernommen. Gilt für alle Stifte außer dem Formen-Stift
  /// (der erkennt immer).
  bool get holdToShape => stows.autoShape.value && this is! ShapePen;

  static const holdToShapeDelay = Duration(milliseconds: 400);

  /// Bewegung unterhalb dieser Strecke (in Seitenpunkten) gilt als "Stillhalten".
  /// Wichtig: Stifte liefern auch im Stillstand winzige Bewegungs-Ereignisse.
  static const holdMoveTolerance = 4.0;
  static Timer? _holdTimer;
  static Offset? _holdAnchor;

  /// Beim Halten erkannte Form (Vorschau und Übernahme beim Abheben).
  static HeldShape? heldShape;

  /// Wird aufgerufen, wenn eine Form im Halten erkannt wurde (Editor zeichnet neu).
  static VoidCallback? onHoldShapeDetected;

  static void _resetHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdAnchor = null;
    heldShape = null;
  }

  void onDragUpdate(Offset position, double? pressure) {
    currentStroke?.addPoint(position, pressure);

    if (holdToShape) {
      final anchor = _holdAnchor;
      if (anchor == null || (position - anchor).distance > holdMoveTolerance) {
        _holdAnchor = position;
        final hadShape = heldShape != null;
        heldShape = null;
        _holdTimer?.cancel();
        _holdTimer = Timer(holdToShapeDelay, () {
          final stroke = Pen.currentStroke;
          if (stroke == null) return;
          heldShape = ShapeRecognizer.recognize([
            for (final p in stroke.points) Offset(p.dx, p.dy),
          ]);
          onHoldShapeDetected?.call();
        });
        if (hadShape) onHoldShapeDetected?.call();
      }
    }
  }

  Stroke? onDragEnd() {
    final held = holdToShape ? heldShape : null;
    if (holdToShape) _resetHold();

    final stroke = currentStroke;
    currentStroke = null;
    if (stroke == null) return null;

    stroke
      ..options.isComplete = true
      ..markPolygonNeedsUpdating();
    if (held != null) return held.applyTo(this, stroke);
    return stroke;
  }

  /// The default stroke options.
  ///
  /// Note that these are different to the default options in [StrokeOptions]
  /// e.g. [StrokeOptions.defaultSize] for historical reasons
  /// (i.e. [StrokeOptions.toJson] does not include default values.)
  static final defaultOptions = StrokeOptions(size: 5);

  static StrokeOptions get fountainPenOptions => defaultOptions.copyWith();
  static StrokeOptions get ballpointPenOptions => defaultOptions.copyWith();
  static StrokeOptions get shapePenOptions =>
      defaultOptions.copyWith(smoothing: 0, streamline: 0);
  static StrokeOptions get tapeOptions =>
      defaultOptions.copyWith(size: 30, smoothing: 0, streamline: 0);
  static StrokeOptions get highlighterOptions =>
      defaultOptions.copyWith(size: 50);
  static StrokeOptions get pencilOptions => defaultOptions.copyWith(
    streamline: 0.1,
    start: StrokeEndOptions.start(taperEnabled: true, customTaper: 1),
    end: StrokeEndOptions.end(taperEnabled: true, customTaper: 1),
  );
}
