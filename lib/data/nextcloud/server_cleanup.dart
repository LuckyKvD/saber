import 'package:logging/logging.dart';
import 'package:nextcloud/webdav.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';

/// Feder: Räumt leere „Löschmarken“ auf dem Nextcloud-Server auf.
///
/// Beim Löschen/Verschieben überschreibt der Sync die alte Server-Datei durch
/// eine leere Datei (0 Bytes). Diese Marken sagen anderen Geräten „gelöscht“.
/// Bei nur einem Gerät sind sie überflüssig und blähen den Ordner auf.
class ServerCleanup {
  static final log = Logger('ServerCleanup');

  /// Gibt `null` zurück, wenn der Sync gerade arbeitet oder nicht angemeldet.
  static String? blockedReason() {
    if (!stows.loggedIn) return 'Du bist nicht bei Nextcloud angemeldet.';
    if (syncer.downloader.isRefreshing ||
        syncer.uploader.isRefreshing ||
        syncer.downloader.numPending + syncer.uploader.numPending > 0) {
      return 'Der Sync arbeitet noch. Bitte warten, bis oben rechts nichts '
          'mehr dreht, und es dann nochmal versuchen.';
    }
    return null;
  }

  /// Leere Dateien auf dem Server, die lokal nicht (mehr) existieren.
  static Future<List<WebDavFile>> findEmptyMarkers() async {
    final remote = await SaberSyncInterface.findRemoteFiles();
    final result = <WebDavFile>[];
    for (final file in remote) {
      final path = file.path.path;
      if (path.endsWith('/')) continue; // Ordner
      if (path.endsWith(NextcloudClientExtension.vaultFileName)) continue;
      if ((file.size ?? 0) > 0) continue;
      try {
        final syncFile = await const SaberSyncInterface()
            .getSyncFileFromRemoteFile(file);
        if (syncFile.localFile.existsSync()) continue;
      } catch (e) {
        // Name nicht entschlüsselbar: lieber stehen lassen.
        log.warning('Löschmarke übersprungen (Name nicht lesbar): $e');
        continue;
      }
      result.add(file);
    }
    return result;
  }

  /// Löscht die gefundenen Marken. Gibt Anzahl gelöscht/fehlgeschlagen zurück.
  static Future<({int removed, int failed})> run(
    List<WebDavFile> markers, {
    void Function(int done, int total)? onProgress,
  }) async {
    final client = SaberSyncInterface.client;
    if (client == null) return (removed: 0, failed: markers.length);
    var removed = 0;
    var failed = 0;
    for (var i = 0; i < markers.length; i++) {
      try {
        await client.webdav.delete(PathUri.parse(markers[i].path.path));
        removed++;
      } catch (e) {
        failed++;
        log.warning('Löschmarke nicht löschbar: $e');
      }
      onProgress?.call(i + 1, markers.length);
    }
    log.info('Server aufgeräumt: $removed gelöscht, $failed fehlgeschlagen');
    return (removed: removed, failed: failed);
  }
}
