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
      try {
        if (FileManager.getFile(target).existsSync()) {
          result.skippedExisting++;
          continue;
        }
        final encrypted = await client.webdav.get(PathUri.parse(remotePath));
        final decrypted = await crypto.decryptFile(
          encrypted,
          isOldJson: path.endsWith('.sbn'),
        );
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
        result.errors.add('$path: $e');
      }
    }
    onProgress('Fertig', remoteFiles.length, remoteFiles.length);
    return result;
  }
}
