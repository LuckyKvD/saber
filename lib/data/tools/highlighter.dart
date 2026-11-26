import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/i18n/strings.g.dart';

class Highlighter extends Pen {
  new()
    : super(
        name: t.editor.pens.highlighter,
        sizeMin: 10,
        sizeMax: 100,
        sizeStep: 10,
        icon: highlighterIcon,
        options: stows.lastHighlighterOptions.value,
        pressureEnabled: false,
        color: Colors.yellow.withAlpha(Highlighter.alpha),
        toolId: .highlighter,
      );

  static const alpha = 100;

  static var currentHighlighter = Highlighter();

  static const highlighterIcon = FontAwesomeIcons.highlighter;

  /// Gerader Modus: Start- bis Endpunkt als saubere Linie, waagerecht oder
  /// senkrecht einrastend.
  static const snapDegrees = 6.0;

  @override
  void onDragUpdate(Offset position, double? pressure) {
    if (!stows.highlighterStraight.value) {
      super.onDragUpdate(position, pressure);
      return;
    }
    final stroke = Pen.currentStroke;
    if (stroke == null) return;
    if (stroke.points.length >= 2) {
      stroke.points.removeRange(1, stroke.points.length);
    }
    var end = position;
    if (stroke.points.isNotEmpty) {
      final start = Offset(stroke.points.first.dx, stroke.points.first.dy);
      final dx = (end.dx - start.dx).abs();
      final dy = (end.dy - start.dy).abs();
      final tolerance = snapDegrees * 3.14159265 / 180;
      if (dx > 0 && dy / dx < tolerance) {
        end = Offset(end.dx, start.dy);
      } else if (dy > 0 && dx / dy < tolerance) {
        end = Offset(start.dx, end.dy);
      }
    }
    stroke.addPoint(end, pressure);
  }

  @override
  bool get holdToShape => !stows.highlighterStraight.value && super.holdToShape;
}
