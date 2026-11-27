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

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Offset(pad, pad));
  final image = await recorder.endRecording().toImage(
    width.ceil(),
    height.ceil(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return HandwritingImage(
    data!.buffer.asUint8List(),
    Size(width / _scale, height / _scale),
  );
}
