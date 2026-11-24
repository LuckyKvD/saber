import 'dart:ui';

import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/editor_history.dart';
import 'package:saber/data/prefs.dart';

import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

double square(double x) => x * x;
double sqrDistanceBetween(Offset p1, Offset p2) =>
    square(p1.dx - p2.dx) + square(p1.dy - p2.dy);

class Eraser extends Tool {
  /// Radius; folgt live der Einstellung, damit die Leiste ihn sofort ändern
  /// kann (außer er wurde im Konstruktor fest vorgegeben, z. B. in Tests).
  final double? _sizeOverride;
  double get size => _sizeOverride ?? stows.eraserSize.value.toDouble();
  double get sqrSize => square(size);

  List<Stroke> _erased = [];

  /// true = nur den berührten Teil des Strichs entfernen (Teilstrich-Radierer),
  /// false = ganzen Strich löschen (Saber-Standard).
  final bool? _partialOverride;
  bool get partial => _partialOverride ?? stows.eraserPartial.value;

  new({double? size, bool? partial})
    : _sizeOverride = size,
      _partialOverride = partial;

  final List<Stroke> _removedOriginals = [];
  final List<Stroke> _added = [];

  /// Teilstrich-Modus: Liefert (alter Strich, Reststücke) für alle berührten
  /// Striche. Der Aufrufer ersetzt die alten Striche durch die Reststücke.
  List<(Stroke, List<Stroke>)> erasePartially(
    Offset eraserPos,
    List<Stroke> strokes,
  ) {
    final result = <(Stroke, List<Stroke>)>[];
    for (final stroke in strokes) {
      final List<Stroke>? pieces;
      if (stroke is CircleStroke || stroke is RectangleStroke) {
        // Formen sind keine freien Linien: ganz löschen.
        pieces = _shouldStrokeBeErased(eraserPos, stroke, sqrSize) ? [] : null;
      } else {
        pieces = stroke.erasePartially(eraserPos, size);
      }
      if (pieces == null) continue;

      if (!_added.remove(stroke)) _removedOriginals.add(stroke);
      _added.addAll(pieces);
      result.add((stroke, pieces));
    }
    return result;
  }

  /// Beendet einen Radierzug im Teilstrich-Modus.
  /// Gibt den Undo-Eintrag zurück oder `null`, wenn nichts geändert wurde.
  HistoricReplace? onDragEndPartial() {
    if (_removedOriginals.isEmpty && _added.isEmpty) return null;
    final change = HistoricReplace(
      removed: List.of(_removedOriginals),
      added: List.of(_added),
    );
    _removedOriginals.clear();
    _added.clear();
    return change;
  }

  @override
  ToolId get toolId => .eraser;

  /// Returns any [strokes] that are close to the given [eraserPos].
  List<Stroke> checkForOverlappingStrokes(
    Offset eraserPos,
    List<Stroke> strokes,
  ) {
    final List<Stroke> overlapping = [];
    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      if (_shouldStrokeBeErased(eraserPos, stroke, sqrSize)) {
        overlapping.add(stroke);
        _erased.add(stroke);
      }
    }
    return overlapping;
  }

  /// Returns the strokes that have been erased during this drag.
  List<Stroke> onDragEnd() {
    final List<Stroke> erased = _erased;
    _erased = [];
    return erased;
  }

  static bool _shouldStrokeBeErased(
    Offset eraserPos,
    Stroke stroke,
    double sqrSize,
  ) {
    if (stroke.length <= 3) {
      if (stroke.lowQualityPath.contains(eraserPos)) return true;
    }

    /// skip checking every few vertices for performance
    final int verticesToSkip = switch (stroke.lowQualityPolygon.length) {
      < 100 => 0,
      < 1000 => 1,
      _ => 2,
    };

    for (
      int i = 0;
      i < stroke.lowQualityPolygon.length;
      i += verticesToSkip + 1
    ) {
      final Offset strokeVertex = stroke.lowQualityPolygon[i];
      if (sqrDistanceBetween(strokeVertex, eraserPos) <= sqrSize) return true;
    }
    return false;
  }
}
