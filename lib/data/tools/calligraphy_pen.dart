import 'dart:math' as math;

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';

/// Kalligrafie-Feder mit festem Federwinkel (PROTOTYP).
///
/// Speichert als normaler Füller (`ty = fountainPen`) plus Zusatzschlüssel
/// `na` (Federwinkel). Original-Saber zeigt solche Striche als einfache Linie.
class CalligraphyPen extends Pen {
  new()
    : super(
        name: 'Kalligrafie-Feder',
        sizeMin: 2,
        sizeMax: 40,
        sizeStep: 1,
        icon: calligraphyIcon,
        options: StrokeOptions(size: 10),
        pressureEnabled: false,
        color: Color(stows.lastFountainPenColor.value),
        toolId: .fountainPen,
      );

  static const calligraphyIcon = FontAwesomeIcons.featherPointed;

  static var current = CalligraphyPen();

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    Pen.currentStroke = Stroke(
      color: color,
      pressureEnabled: false,
      options: options.copyWith(isComplete: false),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      nibAngle: stows.calligraphyNibAngle.value * math.pi / 180,
    );
    onDragUpdate(position, pressure);
  }
}
