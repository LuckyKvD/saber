import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:sbn/tool_id.dart';

/// Feder: Wandelt Handschrift-Striche auf dem Gerät in Text um
/// (Android, ML Kit Digital Ink Recognition; Sprachmodell einmalig geladen).
abstract class InkRecognition {
  static const _channel = MethodChannel('de.luckykvd.feder/ink');

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// Nur echte Schreibstriche (kein Textmarker, kein Klebeband).
  static bool _isWriting(Stroke stroke) =>
      stroke.toolId != ToolId.highlighter &&
      stroke.toolId != ToolId.tape &&
      !stroke.isEmpty;

  /// Gibt die Erkennungs-Kandidaten zurück (bester zuerst), leer wenn nichts
  /// erkannt wurde. Wirft bei Fehlern (z. B. Modell nicht ladbar).
  static Future<List<String>> recognize(
    List<Stroke> strokes, {
    String language = 'de',
  }) async {
    if (!supported) {
      throw UnsupportedError('Handschrift-Erkennung gibt es nur auf Android.');
    }
    final writing = strokes.where(_isWriting).toList();
    if (writing.isEmpty) return const [];

    // Reihenfolge: nach linker Kante, damit "Wort für Wort" gelesen wird.
    double minX(Stroke s) {
      var m = double.infinity;
      for (final p in s.points) {
        if (p.dx < m) m = p.dx;
      }
      return m;
    }

    writing.sort((a, b) => minX(a).compareTo(minX(b)));

    var t = 0;
    final payload = <List<List<double>>>[];
    for (final stroke in writing) {
      final points = <List<double>>[];
      for (final p in stroke.points) {
        points.add([p.dx, p.dy, t.toDouble()]);
        t += 10;
      }
      t += 300;
      payload.add(points);
    }

    final result = await _channel.invokeListMethod<String>('recognize', {
      'language': language,
      'strokes': payload,
    });
    return [
      for (final text in result ?? const <String>[])
        if (text.trim().isNotEmpty) text.trim(),
    ];
  }
}
