import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:saber/data/images/safe_render.dart';

/// Feder: Text in Handschrift-Optik als PNG (transparent), z. B. für das
/// Ergebnis einer Matheaufgabe. Schrift: Neucha (liegt der App bei).
class HandwritingImage {
  const HandwritingImage(this.bytes, this.size);

  final Uint8List bytes;

  /// Größe in Seiteneinheiten (das PNG selbst ist [scale]-mal feiner).
  final Size size;
}

const _scale = 3.0;

/// Siehe [inkPixelsMatch].
bool handwritingPixelsMatch(Uint8List rgba, Color color) =>
    inkPixelsMatch(rgba, color);

Future<HandwritingImage> renderHandwriting(
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

  final bytes = await renderInkPng(
    (canvas) => painter.paint(canvas, Offset(pad, pad)),
    width.ceil(),
    height.ceil(),
    color,
  );
  return HandwritingImage(bytes, Size(width / _scale, height / _scale));
}
