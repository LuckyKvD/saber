import 'package:material_ui/material_ui.dart';
import 'dart:math' as math;

import 'package:perfect_freehand/perfect_freehand.dart' show PointVector;
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/data/tools/_tool.dart';
import 'package:sbn/tool_id.dart';

class Select extends Tool {
  new _();

  static final _currentSelect = Select._();
  static Select get currentSelect => _currentSelect;

  /// The minimum ratio of points inside a stroke or image
  /// for it to be selected.
  static const minPercentInside = 0.7;

  var selectResult = SelectResult(
    pageIndex: -1,
    strokes: const [],
    images: const [],
    path: Path(),
    pageIndexStart: null,
  );
  var doneSelecting = false;

  @override
  ToolId get toolId => .select;

  void unselect() {
    doneSelecting = false;
    selectResult.pageIndex = -1;
  }

  Color? getDominantStrokeColor() {
    if (!doneSelecting) return null;
    if (selectResult.strokes.isEmpty) return null;

    final colorDistribution = <Color, int>{};
    for (final stroke in selectResult.strokes) {
      colorDistribution.update(
        stroke.color,
        (value) => value + stroke.length,
        ifAbsent: () => stroke.length,
      );
    }
    assert(colorDistribution.isNotEmpty);

    return colorDistribution.entries.reduce((a, b) {
      return a.value > b.value ? a : b;
    }).key;
  }

  void onDragStart(Offset position, int pageIndex) {
    doneSelecting = false;
    selectResult = SelectResult(
      pageIndex: pageIndex,
      strokes: [],
      images: [],
      path: Path(),
      pageIndexStart: pageIndex,
    );
    selectResult.path.moveTo(position.dx, position.dy);
    onDragUpdate(position);
  }

  void onDragUpdate(Offset position) {
    selectResult.path.lineTo(position.dx, position.dy);
  }

  /// Adds the indices of any [strokes] that are inside the selection area
  /// to [selectResult.indices].
  void onDragEnd(List<Stroke> strokes, List<EditorImage> images) {
    selectResult.path.close();
    doneSelecting = true;

    for (int i = 0; i < strokes.length; i++) {
      final stroke = strokes[i];
      // Freie Linien werden am Lassorand geschnitten, siehe [cutStrokes].
      if (stroke is! CircleStroke && stroke is! RectangleStroke) continue;
      final percentInside = polygonPercentInside(
        selectResult.path,
        stroke.lowQualityPolygon,
      );
      if (percentInside > minPercentInside) {
        selectResult.strokes.add(stroke);
      }
    }

    for (int i = 0; i < images.length; i++) {
      final image = images[i];
      final percentInside = rectPercentInside(selectResult.path, image.dstRect);
      if (percentInside >= minPercentInside) {
        selectResult.images.add(image);
      }
    }
  }

  /// Schneidet freie Linien am Lassorand: Der Teil innen wird ausgewählt,
  /// der Teil außen bleibt stehen. Gibt (Original, innen, außen) für jeden
  /// geschnittenen Strich zurück. Ganz innen liegende Striche werden
  /// unverändert ausgewählt. Der Aufrufer ersetzt Originale durch Teile.
  List<(Stroke, List<Stroke>, List<Stroke>)> cutStrokes(List<Stroke> strokes) {
    final result = <(Stroke, List<Stroke>, List<Stroke>)>[];
    final path = selectResult.path;
    final bounds = path.getBounds();
    const step = 3.0;

    for (final stroke in strokes) {
      if (stroke is CircleStroke || stroke is RectangleStroke) continue;
      final pts = stroke.points;
      if (pts.isEmpty) continue;

      // Schnelltest über die Umrandung des Strichs.
      var minX = double.infinity, minY = double.infinity;
      var maxX = -double.infinity, maxY = -double.infinity;
      for (final p in pts) {
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      if (!bounds.overlaps(Rect.fromLTRB(minX, minY, maxX, maxY)) &&
          !bounds.contains(Offset(minX, minY))) {
        continue;
      }

      // Linie verdichten, damit die Schnittkante genau am Rand liegt.
      final dense = <PointVector>[pts.first];
      for (int i = 0; i < pts.length - 1; i++) {
        final a = pts[i], b = pts[i + 1];
        final n = ((b - a).distance / step).ceil();
        for (int k = 1; k < n; k++) {
          final t = k / n;
          dense.add(
            PointVector(
              a.dx + (b.dx - a.dx) * t,
              a.dy + (b.dy - a.dy) * t,
              a.pressure == null || b.pressure == null
                  ? null
                  : a.pressure! + (b.pressure! - a.pressure!) * t,
            ),
          );
        }
        dense.add(b);
      }

      final inside = [for (final p in dense) path.contains(Offset(p.dx, p.dy))];
      if (inside.every((v) => !v)) continue;
      if (inside.every((v) => v)) {
        selectResult.strokes.add(stroke);
        continue;
      }

      final insideRuns = <List<PointVector>>[];
      final outsideRuns = <List<PointVector>>[];
      var current = <PointVector>[dense.first];
      for (int i = 1; i < dense.length; i++) {
        if (inside[i] == inside[i - 1]) {
          current.add(dense[i]);
        } else {
          (inside[i - 1] ? insideRuns : outsideRuns).add(current);
          // Anschlusspunkt doppelt, damit keine Lücke entsteht.
          current = [dense[i - 1], dense[i]];
        }
      }
      (inside.last ? insideRuns : outsideRuns).add(current);

      final insidePieces = [
        for (final run in insideRuns)
          if (run.length >= 2) stroke.piece(run),
      ];
      final outsidePieces = [
        for (final run in outsideRuns)
          if (run.length >= 2) stroke.piece(run),
      ];
      selectResult.strokes.addAll(insidePieces);
      result.add((stroke, insidePieces, outsidePieces));
    }
    return result;
  }

  static double rectPercentInside(Path selection, Rect rect) {
    const int gridSize = 5;
    final gridCellWidth = rect.width / (gridSize - 1);
    final gridCellHeight = rect.height / (gridSize - 1);

    int pointsInside = 0;
    for (int x = 0; x < gridSize; x++) {
      for (int y = 0; y < gridSize; y++) {
        if (selection.contains(
          Offset(rect.left + gridCellWidth * x, rect.top + gridCellHeight * y),
        )) {
          pointsInside++;
        }
      }
    }

    // times 1.25 because the grid is not very accurate
    return pointsInside / (gridSize * gridSize) * 1.25;
  }

  static double polygonPercentInside(Path selection, List<Offset> polygon) {
    int pointsInside = 0;
    for (final point in polygon) {
      if (selection.contains(point)) {
        pointsInside++;
      }
    }
    return pointsInside / polygon.length;
  }
}

class SelectResult {
  int pageIndex;
  final List<Stroke> strokes;
  final List<EditorImage> images;
  Path path;
  int? pageIndexStart;

  new({
    required this.pageIndex,
    required this.strokes,
    required this.images,
    required this.path,
    required this.pageIndexStart,
  });

  bool get isEmpty {
    return strokes.isEmpty && images.isEmpty;
  }

  SelectResult copyWith({
    int? pageIndex,
    List<Stroke>? strokes,
    List<EditorImage>? images,
    Path? path,
    int? pageIndexStart,
  }) {
    return SelectResult(
      pageIndex: pageIndex ?? this.pageIndex,
      strokes: strokes ?? this.strokes,
      images: images ?? this.images,
      path: path ?? this.path,
      pageIndexStart: pageIndexStart ?? this.pageIndexStart,
    );
  }
}
