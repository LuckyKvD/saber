import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';

/// Feder-Schnellnotiz: feste Notiz, die das Android-Widget öffnet und deren
/// erste Seite als Vorschau im Widget erscheint.
abstract class QuickNote {
  static final _log = Logger('QuickNote');

  /// Pfad der festen Notiz (ohne Dateiendung).
  static const path = '/Schnellnotiz';

  static const _channel = MethodChannel('de.luckykvd.feder/widget');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// [open] öffnet die Notiz im Editor. Wird sowohl beim Start über das
  /// Widget als auch bei laufender App aufgerufen.
  static Future<void> setup(void Function(String path) open) async {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'quickNote') {
        await _consume();
        open(path);
      }
    });
    unawaited(_syncPreviewFromFile());
    try {
      if (await _consume()) open(path);
    } catch (e) {
      _log.warning('Widget-Start nicht lesbar: $e');
    }
  }

  /// Beim Start: Vorschau aus der gespeicherten Notiz übernehmen
  /// (z. B. direkt nachdem das Widget neu angelegt wurde).
  static Future<void> _syncPreviewFromFile() async {
    try {
      final file = FileManager.getFile('$path.sbn2.p');
      if (!file.existsSync()) return;
      await updatePreview(await FileManager.readBytes(file));
    } catch (e) {
      _log.fine('Keine Vorschau zum Übernehmen: $e');
    }
  }

  static Future<bool> _consume() async {
    final pending = await _channel.invokeMethod<bool>('consumeLaunchAction');
    return pending ?? false;
  }

  /// Vorschau (PNG der ersten Seite) ans Widget geben.
  static Future<void> updatePreview(Uint8List png) async {
    if (!_supported || !stows.widgetPreview.value) return;
    try {
      await _channel.invokeMethod<void>('setPreview', png);
    } catch (e) {
      _log.warning('Widget-Vorschau nicht aktualisiert: $e');
    }
  }

  static Future<void> clearPreview() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('clearPreview');
    } catch (e) {
      _log.warning('Widget-Vorschau nicht gelöscht: $e');
    }
  }
}
