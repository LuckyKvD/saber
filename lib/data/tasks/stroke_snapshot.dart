import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// Feder: Zeichnet gewählte Striche als PNG (weißer Grund) für den
/// Bildanhang einer Aufgabe.
Future<Uint8List?> renderStrokesPng(List<Stroke> strokes) async {
  Rect? bounds;
  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    final b = stroke.highQualityPath.getBounds();
    bounds = bounds == null ? b : bounds.expandToInclude(b);
  }
  if (bounds == null || bounds.isEmpty) return null;

  const padding = 16.0;
  const maxSide = 1400.0;
  final box = bounds.inflate(padding);
  final scale = (maxSide / (box.width > box.height ? box.width : box.height))
      .clamp(0.1, 1.5);
  final width = (box.width * scale).ceil();
  final height = (box.height * scale).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  canvas.scale(scale);
  canvas.translate(-box.left, -box.top);
  for (final stroke in strokes) {
    if (stroke.isEmpty) continue;
    canvas.drawPath(
      stroke.highQualityPath,
      Paint()
        ..color = stroke.color.withValues(alpha: 1)
        ..style = PaintingStyle.fill,
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data?.buffer.asUint8List();
}
