import 'dart:convert';
import 'dart:io';

import 'package:abstract_sync/abstract_sync.dart';
import 'package:collection/collection.dart';
import 'package:saber/data/crypto/feder_crypto.dart';
import 'package:saber/data/crypto/feder_session.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:nextcloud/webdav.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

final syncer = Syncer<SaberSyncInterface, SaberSyncFile, File, WebDavFile>(
  const SaberSyncInterface(),
  failureTimeout: const Duration(seconds: 4),
);

class const SaberSyncInterface()
    extends AbstractSyncInterface<SaberSyncFile, File, WebDavFile> {
  static final log = Logger('SaberSyncInterface');

  @override
  bool areRemoteFilesEqual(WebDavFile a, WebDavFile b) => a.path == b.path;

  @override
  bool areLocalFilesEqual(File a, File b) => a.path == b.path;

  @override
  Future<List<SaberSyncFile>> findLocalChanges() async {
    for (var tries = 0; tries < 10 && remoteFiles.isEmpty; ++tries) {
      // Wait for [findRemoteChanges] to populate [remoteFiles]
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final syncFiles = <SaberSyncFile>[];
    await for (final localFile in FileManager.getRootDirectory().list(
      recursive: true,
    )) {
      if (localFile is! File) continue;
      if (localFile.path.endsWith('.feder-tmp')) continue;

      final syncFile = await getSyncFileFromLocalFile(localFile);

      final bestFile = await getBestFile(
        syncFile,
        onLocalFileNotFound: .local,
        onEqualFiles: .remote,
      );
      switch (bestFile) {
        case .local:
          syncFiles.add(syncFile);
        case .remote:
          // Remote file is newer, do nothing
          break;
      }
      // Feder: Stand merken, solange beide Seiten übereinstimmen.
      final remoteTime = syncFile.remoteFile?.lastModified;
      if (remoteTime != null &&
          KnownMtimes.get(syncFile.relativeLocalPath) == null &&
          remoteTime.difference(syncFile.localFile.lastModifiedSync()).abs() <
              const Duration(milliseconds: 500)) {
        KnownMtimes.set(syncFile.relativeLocalPath, remoteTime);
      }
    }
    // Feder: Noch nicht gemeldete Löschungen erneut anstoßen (z. B. nach
    // einem App-Neustart, bei dem die Warteschlange verloren ging).
    for (final pending in stows.fileSyncPendingDeletes.value.toList()) {
      if (FileManager.getFile(pending).existsSync()) {
        stows.fileSyncPendingDeletes.value.remove(pending);
        continue;
      }
      try {
        final syncFile = await SaberSyncFile.relative(pending);
        if (!syncFiles.any((f) => f.relativeLocalPath == pending)) {
          syncFiles.add(syncFile);
        }
      } catch (e) {
        log.warning('Offene Löschung nicht vormerkbar: $e');
      }
    }
    return syncFiles;
  }

  @override
  Future<List<SaberSyncFile>> findRemoteChanges() async {
    final client = SaberSyncInterface.client;
    if (client == null) return const [];

    remoteFiles = await findRemoteFiles();
    if (remoteFiles.isEmpty) return const [];

    final List<SaberSyncFile> changedFiles = await Future.wait(
      remoteFiles
          .where(
            (f) => !f.path.path.endsWith(
              NextcloudClientExtension.vaultFileName,
            ),
          )
          .map((remoteFile) async {
        final SaberSyncFile syncFile;
        try {
          syncFile = await getSyncFileFromRemoteFile(remoteFile);
        } catch (e, st) {
          log.warning('Failed to get sync file from remote file: $e', e, st);
          return null;
        }

        final bestFile = await getBestFile(
          syncFile,
          onLocalFileNotFound: .remote,
          onEqualFiles: .local,
        );
        switch (bestFile) {
          case .local:
            // Local file is newer, do nothing
            return null;
          case .remote:
            // Remote file is newer or doesn't exist locally

            // Feder: lokal gelöscht/verschoben, Löschung noch unterwegs:
            // die alte Server-Datei nicht zurückladen.
            if (!syncFile.localFile.existsSync() &&
                stows.fileSyncPendingDeletes.value.contains(
                  syncFile.relativeLocalPath,
                )) {
              return null;
            }

            final remotelyDeleted = syncFile.remoteFile!.size! <= 0;
            final locallyDeleted = stows.fileSyncAlreadyDeleted.value.contains(
              syncFile.relativeLocalPath,
            );
            if (remotelyDeleted && locallyDeleted) break;

            return syncFile;
        }
      }),
    ).then((list) => list.nonNulls.toList());

    // Prioritize note.sbn2.p over note.sbn2 (so the preview is updated first)
    final previewSyncFiles = changedFiles
        .where((syncFile) => syncFile.localFile.path.endsWith('.p'))
        .toList(growable: false);
    for (final previewSyncFile in previewSyncFiles) {
      final previewSyncFileIndex = changedFiles.indexOf(previewSyncFile);
      final mainSyncFileIndex = changedFiles.indexWhere(
        (syncFile) =>
            syncFile.localFile.path ==
            previewSyncFile.localFile.path.substring(
              0,
              previewSyncFile.localFile.path.length - 2,
            ),
      );
      if (previewSyncFileIndex <= -1 || mainSyncFileIndex <= -1) continue;

      if (previewSyncFileIndex >= mainSyncFileIndex) {
        changedFiles
          ..removeAt(previewSyncFileIndex)
          ..insert(mainSyncFileIndex, previewSyncFile);
      } else {
        changedFiles
          ..removeAt(previewSyncFileIndex)
          ..insert(mainSyncFileIndex - 1, previewSyncFile);
      }
    }

    return changedFiles;
  }

  @override
  Future<SaberSyncFile> getSyncFileFromLocalFile(File localFile) async {
    final relativePath = localFile.path
        .substring(FileManager.documentsDirectory.length)
        // Compensate for Windows using backslashes
        .replaceAll(Platform.pathSeparator, '/');

    assert(relativePath.startsWith('/'));
    final encryptedName = await encryptPath(client, relativePath);
    final remotePath =
        '${NextcloudClientExtension.appRootDirectoryPrefix}/'
        '$encryptedName'
        '$encExtension';

    final remoteFile = await getWebDavFile(remotePath);

    return SaberSyncFile(
      remoteFile: remoteFile,
      remotePath: remotePath,
      localFile: localFile,
    );
  }

  @override
  Future<SaberSyncFile> getSyncFileFromRemoteFile(WebDavFile remoteFile) async {
    final relativeLocalPath = await decryptPath(client!, remoteFile.path.path);
    if (relativeLocalPath == null)
      throw Exception('Decryption failed for ${remoteFile.path.path}');
    final localFile = FileManager.getFile(relativeLocalPath);

    return SaberSyncFile(remoteFile: remoteFile, localFile: localFile);
  }

  @override
  Future<Uint8List> downloadRemoteFile(SaberSyncFile file) async {
    if (file.remoteFile?.size == 0) {
      // Deleted file, handle in [writeLocalFile]
      return Uint8List(0);
    }

    final client = SaberSyncInterface.client;
    if (client == null)
      throw Exception('Tried to download file without being logged in');

    return await client.webdav.get(PathUri.parse(file.remotePath));
  }

  @override
  Future<void> writeLocalFile(
    SaberSyncFile file,
    // ignore: avoid_renaming_method_parameters
    Uint8List encryptedBytes, {
    @visibleForTesting bool awaitWrite = false,
  }) async {
    if (encryptedBytes.isEmpty) {
      // Remote file was deleted
      KnownMtimes.remove(file.relativeLocalPath);
      await FileManager.deleteFile(file.relativeLocalPath, alsoUpload: false);
      stows.fileSyncAlreadyDeleted.value.add(file.relativeLocalPath);
      stows.fileSyncAlreadyDeleted.notifyListeners();
      return;
    }

    final client = SaberSyncInterface.client;
    if (client == null)
      throw Exception('Tried to decrypt file without being logged in');

    final Uint8List decryptedData;
    try {
      decryptedData = await FederCrypto.decryptFile(
        FederSession.masterKey,
        encryptedBytes,
        path: _logicalPath(file),
      );
    } on FederCryptoException catch (e, st) {
      // Manipulierte oder fremde Datei: NICHT überschreiben.
      log.severe('Entschlüsselung fehlgeschlagen für ${file.remotePath}', e, st);
      return;
    }
    // Feder: Wurde die lokale Datei seit dem letzten Abgleich geändert,
    // geht ihr Inhalt nicht verloren, sondern wird als Konfliktkopie
    // gesichert, bevor die Server-Version sie ersetzt.
    final rel = file.relativeLocalPath;
    if (KnownMtimes.isNote(rel) && file.localFile.existsSync()) {
      final known = KnownMtimes.get(rel);
      if (KnownMtimes.differs(known, file.localFile.lastModifiedSync())) {
        try {
          final localBytes = await FileManager.readBytes(file.localFile);
          if (localBytes.isNotEmpty) {
            await FileManager.writeFile(
              KnownMtimes.conflictPath(rel),
              localBytes,
              awaitWrite: true,
            );
            log.warning('Konflikt: lokale Änderungen von $rel als Kopie gesichert');
          }
        } catch (e, st) {
          log.severe('Konfliktkopie fehlgeschlagen für $rel', e, st);
        }
      }
    }
    await FileManager.writeFile(
      rel,
      decryptedData,
      awaitWrite: awaitWrite,
      alsoUpload: false,
      // Local file should have the same last modified date as remote
      lastModified: file.remoteFile?.lastModified,
    );
    final remoteTime = file.remoteFile?.lastModified;
    if (remoteTime != null) KnownMtimes.set(rel, remoteTime);
  }

  @override
  Future<Uint8List> readLocalFile(SaberSyncFile file) async {
    final decryptedBytes = file.localFile.existsSync()
        ? await FileManager.readBytes(file.localFile)
        : Uint8List(0);
    if (decryptedBytes.isEmpty) {
      // deleted file, handle in [uploadRemoteFile]
      return decryptedBytes;
    }

    final client = SaberSyncInterface.client;
    if (client == null)
      throw Exception('Tried to encrypt file without being logged in');

    final encryptedData = await FederCrypto.encryptFile(
      FederSession.masterKey,
      decryptedBytes,
      path: _logicalPath(file),
    );

    return encryptedData;
  }

  @override
  Future<void> uploadRemoteFile(
    SaberSyncFile file,
    // ignore: avoid_renaming_method_parameters
    Uint8List encryptedBytes,
  ) async {
    DateTime lastModified;
    try {
      lastModified = file.localFile.lastModifiedSync();
    } on FileSystemException {
      lastModified = DateTime.now();
    }
    if (lastModified.isBefore(stows.fileSyncResyncEverythingDate.value)) {
      lastModified = stows.fileSyncResyncEverythingDate.value;
    }

    final client = SaberSyncInterface.client;
    if (client == null)
      throw Exception('Tried to upload file without being logged in');

    // Feder: Hat sich die Server-Version seit dem letzten Abgleich geändert
    // (anderes Gerät), wird sie vor dem Überschreiben als Konfliktkopie
    // gesichert.
    final rel = file.relativeLocalPath;
    if (encryptedBytes.isNotEmpty && KnownMtimes.isNote(rel)) {
      try {
        final known = KnownMtimes.get(rel);
        final remoteNow = await _getWebDavFileUncached(file.remotePath);
        if (remoteNow != null &&
            (remoteNow.size ?? 0) > 0 &&
            KnownMtimes.differs(known, remoteNow.lastModified)) {
          final remoteBytes = await client.webdav.get(
            PathUri.parse(file.remotePath),
          );
          final plain = await FederCrypto.decryptFile(
            FederSession.masterKey,
            remoteBytes,
            path: _logicalPath(file),
          );
          if (plain.isNotEmpty) {
            await FileManager.writeFile(
              KnownMtimes.conflictPath(rel),
              plain,
              awaitWrite: true,
            );
            log.warning('Konflikt: Server-Version von $rel als Kopie gesichert');
          }
        }
      } catch (e, st) {
        log.severe('Konfliktprüfung vor dem Hochladen fehlgeschlagen', e, st);
      }
    }
    await client.webdav.put(
      encryptedBytes,
      PathUri.parse(file.remotePath),
      lastModified: lastModified,
    );
    if (encryptedBytes.isNotEmpty) {
      KnownMtimes.set(rel, lastModified);
    } else {
      KnownMtimes.remove(rel);
    }
    // Feder: Löschung bzw. neue Version ist auf dem Server angekommen.
    if (stows.fileSyncPendingDeletes.value.remove(file.relativeLocalPath)) {
      stows.fileSyncPendingDeletes.notifyListeners();
    }
  }

  static NextcloudClient? _client;
  static NextcloudClient? get client {
    if (_client?.authentications?.isEmpty ?? true) {
      _client = NextcloudClientExtension.withSavedDetails();
    }
    return _client;
  }

  /// A list of remote files from server,
  /// used to speed up [getSyncFileFromLocalFile].
  ///
  /// This is set in [findRemoteFiles], and may be empty
  /// or incomplete if [findRemoteFiles] has not been called recently.
  static var remoteFiles = <WebDavFile>{};

  /// A cache map to encrypt file paths.
  /// e.g. '/path/to/file.sbn2' -> 'L3BhdGgvdG8vZmlsZS5zYm4y'
  ///
  /// Use [encryptPath] to encrypt a path instead of accessing this directly.
  static final _encryptMap = <String, String>{};

  /// A cache map to decrypt file paths.
  /// e.g. 'L3BhdGgvdG8vZmlsZS5zYm4y' -> '/path/to/file.sbn2'
  ///
  /// Use [decryptPath] to decrypt a path instead of accessing this directly.
  static final _decryptMap = <String, String>{};

  /// Leert die Namens-Caches (nach Anmeldung/Abmeldung mit anderem Schlüssel).
  static void clearPathCaches() {
    _encryptMap.clear();
    _decryptMap.clear();
    remoteFiles = <WebDavFile>{};
  }

  static Future<Set<WebDavFile>> findRemoteFiles() async {
    final client = SaberSyncInterface.client;
    if (client == null) return {};

    try {
      return await client.webdav
          .propfind(
            PathUri.parse(NextcloudClientExtension.appRootDirectoryPrefix),
            prop: const WebDavPropWithoutValues.fromBools(
              davGetcontentlength: true,
              davGetlastmodified: true,
            ),
          )
          .then(
            (multistatus) => multistatus
                .toWebDavFiles()
                // ignore root directory itself
                .where(
                  (file) =>
                      file.path.path !=
                      '${NextcloudClientExtension.appRootDirectoryPrefix}/',
                )
                .toSet(),
          );
    } on DynamiteStatusCodeException catch (e, st) {
      if (e.statusCode == HttpStatus.notFound) {
        log.info('findRemoteFiles: Creating app directory', e, st);
        await client.webdav.mkcol(
          PathUri.parse(NextcloudClientExtension.appRootDirectoryPrefix),
        );
        return {};
      } else {
        log.severe('Failed to get list of remote files: $e', e, st);
        if (kDebugMode) rethrow;
        return {};
      }
    } on SocketException catch (e, st) {
      log.warning('findRemoteFiles: Network error: $e', e, st);
      return {};
    } catch (e, st) {
      log.severe('findRemoteFiles: Unknown error: $e', e, st);
      if (kDebugMode) rethrow;
      return {};
    }
  }

  static Future<String> encryptPath(
    NextcloudClient? client,
    String path,
  ) async {
    if (_encryptMap.containsKey(path)) return _encryptMap[path]!;

    if (client == null)
      throw Exception('Tried to encrypt path without being logged in');

    final encrypted = await FederCrypto.encryptPath(
      FederSession.masterKey,
      path,
    );

    _encryptMap[path] = encrypted;
    _decryptMap[encrypted] = path;
    return encrypted;
  }

  static Future<String?> decryptPath(
    NextcloudClient? client,
    String path,
  ) async {
    // Ignore README.md and other ignored files
    if (_ignoredFiles.any(path.endsWith)) return null;
    if (!path.endsWith(encExtension)) {
      log.info('remote file not in recognised encrypted format: $path');
      return null;
    }

    // File name without extension
    final encryptedName = path.substring(
      path.lastIndexOf('/') + 1,
      path.length - encExtension.length,
    );

    if (_decryptMap.containsKey(encryptedName))
      return _decryptMap[encryptedName]!;

    if (client == null)
      throw Exception('Tried to decrypt path without being logged in');

    final String decrypted;
    try {
      decrypted = await FederCrypto.decryptPath(
        FederSession.masterKey,
        encryptedName,
      );
    } on FederCryptoException catch (e) {
      log.warning('Dateiname nicht entschlüsselbar: $path ($e)');
      return null;
    }

    _encryptMap[decrypted] = encryptedName;
    _decryptMap[encryptedName] = decrypted;
    return decrypted;
  }

  /// Returns the best file to keep, local or remote.
  ///
  /// If the local file doesn't exist, [onLocalFileNotFound] is returned.
  ///
  /// If the remote and local files have the same last modified date,
  /// [onEqualFiles] is returned.
  static Future<BestFile> getBestFile(
    SaberSyncFile file, {
    required BestFile onLocalFileNotFound,
    required BestFile onEqualFiles,
    bool preferCache = true,
  }) async {
    if (!file.localFile.existsSync()) {
      // We either have a new remote file or a deleted local file
      return onLocalFileNotFound;
    }

    // get remote file
    file.remoteFile = await _getWebDavFileStatic(
      file.remotePath,
      preferCache: preferCache,
    );
    if (file.remoteFile == null) {
      // Remote file doesn't exist, keep local
      return .local;
    }

    final lastModifiedRemote = file.remoteFile!.lastModified;
    if (lastModifiedRemote == null) {
      // Remote file doesn't exist, keep local
      return .local;
    } else if (lastModifiedRemote.isBefore(
      stows.fileSyncResyncEverythingDate.value,
    )) {
      // If we've prompted a full resync at [resyncEverythingDate],
      // keep the local file if it was modified before [resyncEverythingDate]
      return .local;
    }

    // File exists locally, check if it's newer than the remote file
    final lastModifiedLocal = file.localFile.lastModifiedSync();
    if (lastModifiedRemote.difference(lastModifiedLocal).abs() <
        const Duration(milliseconds: 500)) {
      return onEqualFiles;
    } else if (lastModifiedRemote.isAfter(lastModifiedLocal)) {
      return .remote;
    } else {
      return .local;
    }
  }

  Future<WebDavFile?> getWebDavFile(
    String remotePath, {
    bool preferCache = true,
  }) => _getWebDavFileStatic(remotePath, preferCache: preferCache);

  static Future<WebDavFile?> _getWebDavFileStatic(
    String remotePath, {
    bool preferCache = true,
  }) async {
    final cachedWebDavFile = remoteFiles.firstWhereOrNull(
      (remoteFile) => remoteFile.path.path == remotePath,
    );
    if (preferCache && cachedWebDavFile != null) return cachedWebDavFile;

    final webDavFile = await _getWebDavFileUncached(remotePath);
    if (webDavFile != null) {
      remoteFiles
        ..remove(cachedWebDavFile)
        ..add(webDavFile);
    }
    return webDavFile ?? cachedWebDavFile;
  }

  static Future<WebDavFile?> _getWebDavFileUncached(String remotePath) async {
    final client = SaberSyncInterface.client;
    if (client == null) return null;

    try {
      return await client.webdav
          .propfind(
            PathUri.parse(remotePath),
            prop: const WebDavPropWithoutValues.fromBools(
              davGetcontentlength: true,
              davGetlastmodified: true,
            ),
          )
          .then((multistatus) => multistatus.toWebDavFiles().first);
    } catch (e, st) {
      log.fine('Remote file not found for $remotePath: $e', e, st);
    }

    return null;
  }

  /// the file extension of an encrypted base64 note
  static const encExtension = '.fde';

  /// List of files to ignore on the server.
  /// Prefixed with a slash so we can use [filePath.endsWith]
  static const _ignoredFiles = <String>[
    '/Readme.md',
    '/${NextcloudClientExtension.vaultFileName}',
  ];
}

/// Logischer Pfad einer Datei (mit führendem `/`), an den die Verschlüsselung
/// gebunden ist. Auf beiden Seiten identisch berechnet.
String _logicalPath(SaberSyncFile file) =>
    file.relativeLocalPath.replaceAll(Platform.pathSeparator, '/');

class SaberSyncFile extends AbstractSyncFile<File, WebDavFile> {
  late final relativeLocalPath = localFile.path.substring(
    FileManager.documentsDirectory.length,
  );

  late String remotePath;

  new({required super.remoteFile, String? remotePath, required super.localFile})
    : assert(
        remotePath != null || remoteFile != null,
        'At least one of remotePath or remoteFile must be provided',
      ) {
    this.remotePath = remotePath ?? remoteFile!.path.path;
  }

  static Future<SaberSyncFile> relative(String relativeFilePath) {
    final localFile = FileManager.getFile(relativeFilePath);
    return const SaberSyncInterface().getSyncFileFromLocalFile(localFile);
  }

  @override
  String toString() =>
      'SaberSyncFile(local: $relativeLocalPath, remote: $remotePath)';

  @override
  bool operator ==(Object other) =>
      other is SaberSyncFile && other.localFile.path == localFile.path;

  @override
  int get hashCode => localFile.path.hashCode;
}

extension SaberSyncerComponent on SyncerComponent {
  Future<bool> enqueueRel(String relativeFilePath) async {
    if (!stows.loggedIn) return false;

    final syncFile = await SaberSyncFile.relative(relativeFilePath);
    return enqueue(syncFile: syncFile);
  }
}

enum BestFile { local, remote }

/// Feder: Merkt sich pro Datei den Zeitstempel der zuletzt abgeglichenen
/// Version. Weicht die lokale oder die Server-Datei davon ab, wurde sie seit
/// dem letzten Abgleich geändert; ändern beide Seiten, ist es ein Konflikt.
class KnownMtimes {
  KnownMtimes._();

  static Map<String, int>? _cache;

  static Map<String, int> get _map {
    var map = _cache;
    if (map != null) return map;
    map = <String, int>{};
    try {
      final raw = stows.fileSyncKnownMtimes.value;
      if (raw.isNotEmpty) {
        (jsonDecode(raw) as Map).forEach((k, v) => map![k as String] = v as int);
      }
    } catch (_) {}
    return _cache = map;
  }

  static int? get(String relativePath) => _map[relativePath];

  static void set(String relativePath, DateTime time) {
    final ms = time.millisecondsSinceEpoch;
    if (_map[relativePath] == ms) return;
    _map[relativePath] = ms;
    _save();
  }

  static void remove(String relativePath) {
    if (_map.remove(relativePath) != null) _save();
  }

  static void _save() {
    stows.fileSyncKnownMtimes.value = jsonEncode(_map);
  }

  /// Unterscheiden sich [time] und der gemerkte Stand um mehr als 1 s?
  static bool differs(int? known, DateTime? time) {
    if (known == null || time == null) return false;
    return (time.millisecondsSinceEpoch - known).abs() > 1000;
  }

  /// Nur echte Notizen, keine Vorschaubilder (`.p`) o. Ä.
  static bool isNote(String relativePath) =>
      relativePath.endsWith(Editor.extension);

  /// Name der Konfliktkopie, z. B. `/Regal/Notiz (Konflikt 2026-11-28 14.05).sbn2`.
  static String conflictPath(String relativePath) {
    final base = relativePath.substring(
      0,
      relativePath.length - Editor.extension.length,
    );
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}-${two(now.month)}-${two(now.day)} '
        '${two(now.hour)}.${two(now.minute)}';
    return '$base (Konflikt $stamp)${Editor.extension}';
  }
}
