import 'dart:math' as math;
import 'dart:ui' show Rect;

/// Feder: Bündelt Striche (anhand ihrer Umrandungen) zu Textzeilen,
/// damit die Handschrift-Erkennung Zeile für Zeile lesen kann.
abstract class LineGrouper {
  /// Gibt Gruppen von Indizes in [boxes] zurück, in Leserichtung
  /// (oben nach unten, links nach rechts). Eine Zeile wird zusätzlich getrennt,
  /// wenn zwischen zwei Strichen eine Lücke größer als [gapFactor] × [cell]
  /// liegt (z. B. Spalten einer Tabelle).
  static List<List<int>> group(
    List<Rect> boxes, {
    required double cell,
    double gapFactor = 3,
  }) {
    final order = List<int>.generate(boxes.length, (i) => i)
      ..sort((a, b) => boxes[a].center.dy.compareTo(boxes[b].center.dy));

    final lines = <_Line>[];
    for (final i in order) {
      final box = boxes[i];
      _Line? best;
      var bestOverlap = 0.0;
      for (final line in lines) {
        final overlap =
            math.min(line.bottom, box.bottom) - math.max(line.top, box.top);
        final smaller = math.min(line.bottom - line.top, box.height);
        final need = math.max(cell * 0.2, 0.4 * smaller);
        if (overlap >= need && overlap > bestOverlap) {
          best = line;
          bestOverlap = overlap;
        }
      }
      if (best == null) {
        lines.add(_Line(box.top, box.bottom)..items.add(i));
      } else {
        best.items.add(i);
        best.top = math.min(best.top, box.top);
        best.bottom = math.max(best.bottom, box.bottom);
      }
    }

    lines.sort((a, b) => a.top.compareTo(b.top));
    final result = <List<int>>[];
    for (final line in lines) {
      line.items.sort((a, b) => boxes[a].left.compareTo(boxes[b].left));
      var segment = <int>[];
      var right = -double.infinity;
      for (final i in line.items) {
        final box = boxes[i];
        if (segment.isNotEmpty && box.left - right > gapFactor * cell) {
          result.add(segment);
          segment = <int>[];
          right = -double.infinity;
        }
        segment.add(i);
        right = math.max(right, box.right);
      }
      if (segment.isNotEmpty) result.add(segment);
    }
    return result;
  }
}

class _Line {
  _Line(this.top, this.bottom);
  double top, bottom;
  final items = <int>[];
}
