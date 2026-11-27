import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// Feder: Text in Handschrift-Optik als PNG (transparent), z. B. für das
/// Ergebnis einer Matheaufgabe. Schrift: Neucha (liegt der App bei).
class HandwritingImage {
  const HandwritingImage(this.bytes, this.size);

  final Uint8List bytes;

  /// Größe in Seiteneinheiten (das PNG selbst ist [scale]-mal feiner).
  final Size size;
}

const _scale = 3.0;

/// Prüft Rohpixel (RGBA, vormultipliziert): Ein sauber gerenderter Text enthält
/// nur transparente Pixel und Pixel in [color]. Fremde Farben (z. B. Reste von
/// Grafikspeicher) gelten als fehlerhaft.
bool handwritingPixelsMatch(Uint8List rgba, Color color) {
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

/// Rendert mit Prüfung: bei fehlerhaftem Ergebnis bis zu 4 weitere Versuche.
Future<HandwritingImage> renderHandwriting(
  String text,
  Color color,
  double fontSize,
) async {
  late HandwritingImage result;
  for (var attempt = 0; attempt < 5; attempt++) {
    final (image, clean) = await _renderOnce(text, color, fontSize);
    result = image;
    if (clean) break;
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
  return result;
}

Future<(HandwritingImage, bool)> _renderOnce(
  String text,
  Color color,
  double fontSize,
) async {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Neucha',
        color: color,
        fontSize: fontSize * _scale,
        height: 1.1,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();

  final pad = fontSize * _scale * 0.1;
  final width = painter.width + pad * 2;
  final height = painter.height + pad * 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Offset(pad, pad));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width.ceil(), height.ceil());
  final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final clean = raw != null && handwritingPixelsMatch(raw.buffer.asUint8List(), color);
  image.dispose();
  picture.dispose();
  return (
    HandwritingImage(
      data!.buffer.asUint8List(),
      Size(width / _scale, height / _scale),
    ),
    clean,
  );
}
