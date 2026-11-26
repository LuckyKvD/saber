import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';

/// Gemeinsame Basis der Feder-Stifte (Pinsel, Fineliner, gestrichelt,
/// Glitzer, Stempel). Sie speichern sich als normale Füller/Kugelschreiber
/// (ggf. mit Zusatzschlüssel `ps`), damit ältere Versionen die Notiz lesen.
abstract class FederPen extends Pen {
  @protected
  new({
    required super.name,
    required super.sizeMin,
    required super.sizeMax,
    required super.sizeStep,
    required super.icon,
    required super.options,
    required super.pressureEnabled,
    required super.color,
    required super.toolId,
    this.penStyle,
  });

  int? penStyle;

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    Pen.currentStroke = Stroke(
      color: color,
      pressureEnabled: pressureEnabled,
      options: options.copyWith(isComplete: false),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
      penStyle: penStyle,
    );
    onDragUpdate(position, pressure);
  }
}

/// Pinsel: starke Strichbreitenvariation nach Druck, spitz auslaufend.
class BrushPen extends FederPen {
  new()
    : super(
        name: 'Pinsel',
        sizeMin: 4,
        sizeMax: 40,
        sizeStep: 1,
        icon: brushIcon,
        options: Pen.defaultOptions.copyWith(
          size: 16,
          smoothing: 0.5,
          streamline: 0.6,
          start: StrokeEndOptions.start(taperEnabled: true),
          end: StrokeEndOptions.end(taperEnabled: true),
        )..thinning = 0.9,
        pressureEnabled: true,
        color: Color(stows.lastFountainPenColor.value),
        toolId: .fountainPen,
      );

  static const brushIcon = FontAwesomeIcons.paintbrush;
  static var current = BrushPen();
}

/// Fineliner: gleichmäßig dünne, harte Linie mit eckigen Enden
/// (technischer Stil, ohne Druckeffekt und ohne rundes Auslaufen).
class FinelinerPen extends FederPen {
  new()
    : super(
        name: 'Fineliner',
        sizeMin: 0.5,
        sizeMax: 6,
        sizeStep: 0.5,
        icon: finelinerIcon,
        options: Pen.defaultOptions.copyWith(
          size: 1.5,
          smoothing: 0.3,
          streamline: 0.3,
        ),
        pressureEnabled: false,
        color: const Color(0xFF1A237E),
        toolId: .ballpointPen,
        penStyle: Stroke.styleLiner,
      );

  static const finelinerIcon = FontAwesomeIcons.penNib;
  static var current = FinelinerPen();

  @override
  bool get holdToShape => false;
}

/// Muster-Stift: gestrichelt oder eine Kette aus Zeichen (Punkte, Sterne …),
/// je nach Auswahl in `stows.patternSymbol`.
class DashedPen extends FederPen {
  new()
    : super(
        name: 'Muster-Stift',
        sizeMin: 1,
        sizeMax: 14,
        sizeStep: 1,
        icon: dashedIcon,
        options: Pen.defaultOptions.copyWith(
          size: 3,
          smoothing: 0.3,
          streamline: 0.4,
        ),
        pressureEnabled: false,
        color: Color(stows.lastBallpointPenColor.value),
        toolId: .ballpointPen,
        penStyle: Stroke.styleDashed,
      );

  static const dashedIcon = FontAwesomeIcons.ellipsis;
  static var current = DashedPen();

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    final n = stows.patternSymbol.value;
    penStyle = n <= 0 ? Stroke.styleDashed : Stroke.styleSymbolBase + n;
    super.onDragStart(position, page, pageIndex, pressure);
  }

  @override
  bool get holdToShape => false;
}

/// Glitzerstift: Gel-Look mit Funkeln.
class GlitterPen extends FederPen {
  new()
    : super(
        name: 'Glitzer',
        sizeMin: 4,
        sizeMax: 30,
        sizeStep: 1,
        icon: glitterIcon,
        options: Pen.defaultOptions.copyWith(
          size: 12,
          smoothing: 0.5,
          streamline: 0.5,
        ),
        pressureEnabled: false,
        color: const Color(0xFFE91E8C),
        toolId: .ballpointPen,
        penStyle: Stroke.styleGlitter,
      );

  static const glitterIcon = FontAwesomeIcons.wandMagicSparkles;
  static var current = GlitterPen();

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    penStyle = stows.glitterRainbow.value
        ? Stroke.styleRainbow
        : Stroke.styleGlitter;
    super.onDragStart(position, page, pageIndex, pressure);
  }

  @override
  bool get holdToShape => false;
}

/// Stempel: ein Tipp setzt ein Symbol (Häkchen, Kreuz, Stern, Herz, Pfeil, Kästchen).
class StampPen extends FederPen {
  new()
    : super(
        name: 'Stempel',
        sizeMin: 1,
        sizeMax: 12,
        sizeStep: 1,
        icon: stampIcon,
        options: Pen.defaultOptions.copyWith(
          size: 3,
          smoothing: 0,
          streamline: 0,
        ),
        pressureEnabled: false,
        color: const Color(0xFFD32F2F),
        toolId: .ballpointPen,
      );

  static const stampIcon = FontAwesomeIcons.stamp;
  static var current = StampPen();

  /// Vom Editor gesetzt: legt einen Text-Stempel als Bild aufs Blatt.
  static void Function(String text, Color color)? onPlaceText;

  static const symbolNames = ['Häkchen', 'Kreuz', 'Stern', 'Herz', 'Pfeil', 'Kästchen'];

  @override
  bool get holdToShape => false;

  /// Linienzug des Symbols im Einheitsquadrat (-0.5 .. 0.5, y nach unten).
  static List<Offset> symbolPoints(int symbol) {
    switch (symbol) {
      case 0: // Häkchen
        return const [Offset(-0.45, 0.05), Offset(-0.15, 0.4), Offset(0.5, -0.4)];
      case 1: // Kreuz
        return const [
          Offset(-0.4, -0.4),
          Offset(0.4, 0.4),
          Offset(0, 0),
          Offset(0.4, -0.4),
          Offset(-0.4, 0.4),
        ];
      case 2: // Stern
        return [
          for (var i = 0; i <= 10; i++)
            () {
              final r = i.isEven ? 0.5 : 0.2;
              final a = -math.pi / 2 + i * math.pi / 5;
              return Offset(r * math.cos(a), r * math.sin(a));
            }(),
        ];
      case 3: // Herz
        return [
          for (var i = 0; i <= 32; i++)
            () {
              final t = i / 32 * 2 * math.pi;
              final x = 16 * math.pow(math.sin(t), 3);
              final y =
                  13 * math.cos(t) -
                  5 * math.cos(2 * t) -
                  2 * math.cos(3 * t) -
                  math.cos(4 * t);
              return Offset(x / 34, -y / 34 + 0.03);
            }(),
        ];
      case 4: // Pfeil
        return const [
          Offset(-0.5, 0),
          Offset(0.5, 0),
          Offset(0.2, 0.3),
          Offset(0.5, 0),
          Offset(0.2, -0.3),
        ];
      default: // Kästchen
        return const [
          Offset(-0.4, -0.4),
          Offset(0.4, -0.4),
          Offset(0.4, 0.4),
          Offset(-0.4, 0.4),
          Offset(-0.4, -0.4),
        ];
    }
  }

  @override
  void onDragStart(
    Offset position,
    EditorPage page,
    int pageIndex,
    double? pressure,
  ) {
    final stroke = Stroke(
      color: color,
      pressureEnabled: false,
      options: options.copyWith(isComplete: false),
      pageIndex: pageIndex,
      page: page,
      toolId: toolId,
    );
    final scale = stows.stampScale.value.toDouble();
    for (final p in symbolPoints(stows.stampSymbol.value)) {
      stroke.addPoint(position + p * scale);
    }
    Pen.currentStroke = stroke;
  }

  @override
  void onDragUpdate(Offset position, double? pressure) {
    // Ein Stempel ist ein einzelner Tipp: Ziehen verändert nichts.
  }
}
