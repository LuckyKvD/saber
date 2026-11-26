import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/symbol_geometry.dart';
import 'package:saber/components/toolbar/size_picker.dart';
import 'package:saber/components/toolbar/tape_pattern_picker.dart';
import 'package:saber/components/toolbar/tool_setting_chips.dart';
import 'package:saber/data/extensions/axis_extensions.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/calligraphy_pen.dart';
import 'package:saber/data/tools/extra_pens.dart';
import 'package:saber/data/tools/highlighter.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/data/tools/pencil.dart';
import 'package:saber/data/tools/tape_pen.dart';
import 'package:saber/i18n/strings.g.dart';

class PenModal<T extends Pen> extends StatefulWidget {
  const new({super.key, required this.getTool, required this.setTool});

  /// Gets the current/last-used tool of type [T],
  /// e.g. [Pen.currentPen] or [Highlighter.currentHighlighter].
  final T Function() getTool;

  /// Sets a pen to be the current pen.
  final void Function(Pen) setTool;

  @override
  State<PenModal<T>> createState() => _PenModalState<T>();
}

class _PenModalState<T extends Pen> extends State<PenModal<T>> {
  @override
  Widget build(BuildContext context) {
    final axis = stows.editorToolbarAlignment.value.axis.opposite;
    final pen = widget.getTool();
    final isPencil = pen is Pencil;

    return Center(
      child: SingleChildScrollView(
        scrollDirection: axis,
        child: Flex(
      direction: axis,
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        SizePicker(axis: axis, pen: pen),
        if (pen is Highlighter)
          ToolSettingChips<bool>(
            label: 'Linie',
            pref: stows.highlighterStraight,
            options: [(false, 'Frei'), (true, 'Gerade')],
          ),
        if (pen is TapePen) const TapePatternPicker(),

        if (pen is! Highlighter && pen is! TapePen) ...[
          if (!isPencil && Pen.currentPen.icon == GlitterPen.glitterIcon)
            ToolSettingChips<bool>(
              label: 'Farbe',
              pref: stows.glitterRainbow,
              options: [(true, 'Regenbogen'), (false, 'Einfarbig')],
            ),
          if (!isPencil && Pen.currentPen.icon == DashedPen.dashedIcon)
            ToolSettingChips<int>(
              label: 'Muster',
              pref: stows.patternSymbol,
              options: [
                for (var i = 0; i < symbolBrushNames.length; i++)
                  (i, symbolBrushNames[i]),
              ],
            ),
          if (!isPencil && Pen.currentPen.icon == CalligraphyPen.calligraphyIcon)
            ToolSettingChips<int>(
              label: 'Winkel',
              pref: stows.calligraphyNibAngle,
              options: [
                (15, '15°'),
                (30, '30°'),
                (45, '45°'),
                (60, '60°'),
                (75, '75°'),
              ],
            ),
          if (!isPencil && Pen.currentPen.icon == Pen.fountainPenIcon)
            ToolSettingChips<int>(
              label: 'Druck',
              pref: stows.fountainThinning,
              options: [(0, 'Aus'), (50, 'Normal'), (75, 'Stark'), (95, 'Max')],
            ),
        ],
      ],
        ),
      ),
    );
  }
}
