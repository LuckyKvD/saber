import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// Prüft Rohpixel (RGBA, vormultipliziert): Ein sauber gerenderter Text oder
/// Stempel enthält nur transparente Pixel und Pixel in [color]. Fremde Farben
/// (z. B. Reste von Grafikspeicher) gelten als fehlerhaft.
bool inkPixelsMatch(Uint8List rgba, Color color) {
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  var bad = 0;
  final pixels = rgba.length ~/ 4;
  for (var i = 0; i < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 0) {
      if (rgba[i] != 0 || rgba[i + 1] != 0 || rgba[i + 2] != 0) bad++;
      continue;
    }
    final er = r * a / 255, eg = g * a / 255, eb = b * a / 255;
    if ((rgba[i] - er).abs() > 6 ||
        (rgba[i + 1] - eg).abs() > 6 ||
        (rgba[i + 2] - eb).abs() > 6) {
      bad++;
    }
  }
  return bad <= pixels * 0.002;
}

/// Feder: Zeichnet mit [draw] ein einfarbiges Motiv (Farbe [color]) in ein PNG
/// der Größe [width] × [height]. Zeichnung und Bild werden immer freigegeben.
/// Enthält das Ergebnis fremde Farben (bekannter Fehler beim Grafikspeicher),
/// wird bis zu 4-mal neu gerendert. Liefert die PNG-Bytes.
Future<Uint8List> renderInkPng(
  void Function(Canvas canvas) draw,
  int width,
  int height,
  Color color,
) async {
  Uint8List? last;
  for (var attempt = 0; attempt < 5; attempt++) {
    final recorder = ui.PictureRecorder();
    draw(Canvas(recorder));
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      last = png!.buffer.asUint8List();
      if (raw != null && inkPixelsMatch(raw.buffer.asUint8List(), color)) {
        return last;
      }
    } finally {
      image?.dispose();
      picture.dispose();
    }
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  return last!;
}
