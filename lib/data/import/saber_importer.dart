import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:nextcloud/webdav.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/import/saber_legacy_crypto.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';

class SaberImportResult {
  int imported = 0;
  int skippedExisting = 0;
  int recovered = 0;
  int failed = 0;
  final List<String> errors = [];
}

/// Importiert Notizen aus dem Saber-Ordner (`Saber/`) derselben Nextcloud als
/// KOPIE nach `Import aus Saber/…` in Feder.
///
/// Der Saber-Ordner wird ausschließlich gelesen (PROPFIND/GET). Es wird dort
/// nichts geschrieben, verschoben oder gelöscht.
class SaberImporter {
  SaberImporter._();

  static final log = Logger('SaberImporter');

  /// Server-Ordner der Saber-App (nur lesen!).
  static const saberRemoteRoot = 'Saber';
  static const _configName = 'config.sbc';
  static const _encExtension = '.sbe';

  /// Zielordner in Feder (verhindert Kollisionen mit eigenen Notizen).
  static const targetFolder = '/Import aus Saber';

  static Future<SaberImportResult> run({
    required String saberPassword,
    required void Function(String status, int done, int total) onProgress,
  }) async {
    final result = SaberImportResult();
    final client = NextcloudClientExtension.fromNextcloudCredentials();
    if (client == null) {
      throw StateError('Nicht bei Nextcloud angemeldet.');
    }

    onProgress('Saber-Konfiguration lesen …', 0, 0);
    final Uint8List configBytes;
    try {
      configBytes = await client.webdav.get(
        PathUri.parse('$saberRemoteRoot/$_configName'),
      );
    } on DynamiteStatusCodeException catch (e) {
      if (e.statusCode == HttpStatus.notFound) {
        throw StateError(
          'Auf diesem Server gibt es keinen Saber-Ordner '
          '("$saberRemoteRoot") mit Konfiguration.',
        );
      }
      rethrow;
    }
    final config =
        jsonDecode(utf8.decode(configBytes, allowMalformed: true))
            as Map<String, dynamic>;
    final crypto = SaberLegacyCrypto.fromConfig(config, saberPassword);

    onProgress('Dateiliste laden …', 0, 0);
    final listing = await client.webdav.propfind(
      PathUri.parse(saberRemoteRoot),
      prop: const WebDavPropWithoutValues.fromBools(
        davGetcontentlength: true,
        davGetlastmodified: true,
      ),
    );
    final remoteFiles = listing
        .toWebDavFiles()
        .where((f) => f.path.path.endsWith(_encExtension))
        .where((f) => (f.size ?? 0) > 0) // 0 Byte = in Saber gelöscht
        .toList();

    var done = 0;
    for (final remote in remoteFiles) {
      done++;
      final remotePath = remote.path.path;
      final hexName = remotePath.substring(
        remotePath.lastIndexOf('/') + 1,
        remotePath.length - _encExtension.length,
      );
      final path = crypto.decryptPath(hexName);
      if (path == null) {
        result.failed++;
        result.errors.add('Name nicht lesbar: $hexName');
        continue;
      }
      onProgress(path, done, remoteFiles.length);

      final target = '$targetFolder$path';
      var diag = 'Server: ${remote.size} B';
      try {
        if (FileManager.getFile(target).existsSync()) {
          result.skippedExisting++;
          continue;
        }
        final encrypted = await client.webdav.get(PathUri.parse(remotePath));
        diag = 'Server: ${remote.size} B, geladen: ${encrypted.length} B '
            '(Rest mod 16: ${encrypted.length % 16}), '
            'geändert: ${remote.lastModified?.toIso8601String()}';
        Uint8List decrypted;
        try {
          decrypted = await crypto.decryptFile(
            encrypted,
            isOldJson: path.endsWith('.sbn'),
          );
        } catch (e) {
          // Rettungsversuch: Padding am Ende defekt (z. B. angehängte Bytes).
          final raw = await crypto.decryptRaw(encrypted);
          final info = _bsonInfo(raw);
          diag += ', roh: ${raw.length} B, letztes Byte: ${raw.last}, ${info.text}';
          final cut = info.length;
          if (path.endsWith('.sbn2') &&
              cut != null &&
              cut <= raw.length &&
              raw.length - cut <= 8192 &&
              raw[cut - 1] == 0) {
            decrypted = Uint8List.sublistView(raw, 0, cut);
            result.recovered++;
            log.warning('Gerettet (Ende abgeschnitten): $path ($e)');
          } else {
            rethrow;
          }
        }
        if (decrypted.isEmpty) {
          throw const FormatException('Leere Datei nach Entschlüsselung');
        }
        await FileManager.writeFile(
          target,
          decrypted,
          awaitWrite: true,
          lastModified: remote.lastModified,
        );
        result.imported++;
      } catch (e, st) {
        log.warning('Import fehlgeschlagen für $path: $e', e, st);
        result.failed++;
        result.errors.add('$path: $e [$diag]');
      }
    }
    onProgress('Fertig', remoteFiles.length, remoteFiles.length);
    return result;
  }

  /// BSON-Dokumente beginnen mit ihrer Gesamtlänge (Int32, little endian) und
  /// enden mit 0x00. (Annahme: .sbn2 ist BSON – wird hier nur geprüft.)
  static ({int? length, String text}) _bsonInfo(Uint8List raw) {
    if (raw.length < 5) return (length: null, text: 'zu kurz');
    final len = ByteData.sublistView(raw).getInt32(0, Endian.little);
    final ok = len >= 5 && len <= raw.length;
    return (
      length: ok ? len : null,
      text: 'Kopfwert: $len${ok ? ', Byte am Ende: ${raw[len - 1]}' : ''}',
    );
  }
}
