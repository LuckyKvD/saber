import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/crypto/local_crypto.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// Wandelt alle lokalen Notizdateien einmalig in die verschlüsselte Form um
/// (und beim Abmelden wieder zurück).
///
/// Sicherheitsnetz pro Datei: erst in eine Zwischendatei schreiben, bei
/// Verschlüsselung per Rücktest prüfen, dann atomar umbenennen. Der
/// Zeitstempel bleibt erhalten, damit der Sync nichts neu überträgt.
class LocalMigration {
  LocalMigration._();

  static final log = Logger('LocalMigration');

  static const tempSuffix = '.feder-tmp';

  /// (erledigt, gesamt, wird verschlüsselt?) – null, wenn nichts läuft.
  static final progress =
      ValueNotifier<({int done, int total, bool encrypting})?>(null);

  static bool _running = false;
  static bool get isRunning => _running;

  /// Verschlüsselt alle noch unverschlüsselten Dateien. Gibt die Zahl der
  /// fehlgeschlagenen Dateien zurück (diese bleiben unverändert lesbar).
  static Future<int> encryptAll() => _convertAll(encrypt: true);

  /// Entschlüsselt alle Dateien (vor dem Abmelden).
  static Future<int> decryptAll() => _convertAll(encrypt: false);

  static Future<int> _convertAll({required bool encrypt}) async {
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await LocalCrypto.ensureReady();
    if (encrypt && !LocalCrypto.isActive) return 0;
    _running = true;
    var failed = 0;
    try {
      final files = <File>[];
      await for (final entity in FileManager.getRootDirectory().list(
        recursive: true,
      )) {
        if (entity is! File) continue;
        if (entity.path.endsWith(tempSuffix)) {
          // Rest eines früheren Abbruchs: Original ist noch vorhanden.
          await entity.delete().catchError((_) => entity);
          continue;
        }
        if (LocalCrypto.isEncryptablePath(entity.path)) files.add(entity);
      }

      var done = 0;
      progress.value = (done: 0, total: files.length, encrypting: encrypt);
      for (final file in files) {
        try {
          await _convertFile(file, encrypt: encrypt);
        } catch (e, st) {
          failed++;
          log.severe('Umwandlung fehlgeschlagen: ${file.path}', e, st);
        }
        done++;
        progress.value = (
          done: done,
          total: files.length,
          encrypting: encrypt,
        );
      }
    } finally {
      _running = false;
      progress.value = null;
    }
    return failed;
  }

  static Future<void> _convertFile(File file, {required bool encrypt}) async {
    final raw = await file.readAsBytes();
    if (raw.isEmpty) return; // leere Datei = gelöscht, nie anfassen
    if (LocalCrypto.isEncrypted(raw) == encrypt) return; // schon im Zielzustand

    final stat = file.statSync();
    final Uint8List out;
    if (encrypt) {
      out = await LocalCrypto.encrypt(raw);
      final check = await LocalCrypto.decrypt(out);
      if (!listEquals(check, raw)) {
        throw StateError('Rücktest der Verschlüsselung fehlgeschlagen.');
      }
    } else {
      out = await LocalCrypto.decrypt(raw);
    }

    final temp = File('${file.path}$tempSuffix');
    await temp.writeAsBytes(out, flush: true);
    await temp.setLastModified(stat.modified);

    // Wurde die Datei inzwischen geändert (z. B. durch Sync/Speichern)?
    final now = file.statSync();
    if (now.modified != stat.modified || now.size != stat.size) {
      await temp.delete();
      log.info('Übersprungen (inzwischen geändert): ${file.path}');
      return;
    }
    await temp.rename(file.path);
  }
}
