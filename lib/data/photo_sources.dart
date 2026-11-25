import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Woher die Fotos kommen.
enum PhotoSource {
  /// Systemgalerie (auf Samsung: Samsung Galerie / Fotoauswahl des Systems).
  gallery('system', 'Galerie (System)'),
  googlePhotos('google', 'Google Fotos'),
  ente('ente', 'Ente Fotos'),

  /// Dateiauswahl (Dateiexplorer), auch für SVG.
  files('files', 'Dateien durchsuchen');

  const PhotoSource(this.id, this.label);
  final String id;
  final String label;
}

class PickedPhoto {
  const PickedPhoto(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

/// Fehler, wenn die gewünschte App fehlt oder keine Bildauswahl anbietet.
class PhotoSourceUnavailable implements Exception {
  const PhotoSourceUnavailable(this.source);
  final PhotoSource source;
}

class PhotoSources {
  const PhotoSources._();

  static const _channel = MethodChannel('de.luckykvd.feder/photos');

  /// Fragt die gewählte App nach Bildern. Das Verkleinern passiert nativ,
  /// das ist deutlich schneller als in Dart.
  static Future<List<PickedPhoto>> pick(
    PhotoSource source, {
    required int maxSize,
  }) async {
    assert(source != PhotoSource.files);
    final List<dynamic>? raw;
    try {
      raw = await _channel.invokeListMethod<dynamic>('pick', {
        'source': source.id,
        'maxSize': maxSize,
      });
    } on PlatformException catch (e) {
      if (e.code == 'not_installed') throw PhotoSourceUnavailable(source);
      rethrow;
    }
    if (raw == null) return const [];
    final result = <PickedPhoto>[];
    for (final item in raw) {
      final map = Map<String, dynamic>.from(item as Map);
      final file = File(map['path'] as String);
      try {
        result.add(
          PickedPhoto(await file.readAsBytes(), map['ext'] as String? ?? '.jpg'),
        );
      } finally {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    return result;
  }
}
