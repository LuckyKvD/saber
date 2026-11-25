import 'dart:ui';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';

/// Klebeband (Washi Tape): ein gerader, halbtransparenter Streifen
/// vom Start- bis zum Endpunkt, mit gezackten Enden. Liegt unter der Schrift.
class TapePen extends Pen {
  new()
    : super(
        name: 'Klebeband',
        sizeMin: 10,
        sizeMax: 100,
        sizeStep: 5,
        icon: tapeIcon,
        options: stows.lastTapeOptions.value,
        pressureEnabled: false,
        color: defaultColor,
        toolId: .tape,
      );

  static const alpha = 170;
  static final defaultColor = const Color(0xFFF48FB1).withAlpha(alpha);

  static var currentTape = TapePen();

  static const tapeIcon = FontAwesomeIcons.tape;

  /// Winkel (Grad), unter dem das Band waagerecht/senkrecht einrastet.
  static const snapDegrees = 4.0;

  @override
  void onDragUpdate(Offset position, double? pressure) {
    final stroke = Pen.currentStroke;
    if (stroke == null) return;

    final pattern = stows.lastTapePattern.value;
    stroke.tapePattern = pattern >= 0 ? pattern : null;

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
  Stroke? onDragEnd() {
    final stroke = Pen.currentStroke;
    if (stroke != null) {
      final short =
          stroke.points.length < 2 ||
          (Offset(stroke.points.first.dx, stroke.points.first.dy) -
                      Offset(stroke.points.last.dx, stroke.points.last.dy))
                  .distance <
              8;
      if (short) {
        Pen.currentStroke = null;
        return null;
      }
    }
    return super.onDragEnd();
  }
}
