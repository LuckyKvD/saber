import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// Feder-Sicherung: packt alle Notizen, Tagebuch, Bilder und Vorschauen in
/// eine ZIP-Datei. Lokal verschlüsselte Notizen bleiben darin verschlüsselt,
/// weil die Dateien unverändert so abgelegt werden, wie sie auf dem Gerät
/// liegen.
abstract class Backup {
  static const keepLocal = 3;

  static Future<Directory> _backupDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/Sicherungen');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// Erstellt die Sicherung lokal (außerhalb des Sync-Ordners) und gibt die
  /// Datei zurück. Es bleiben die letzten [keepLocal] Sicherungen erhalten.
  static Future<File> create() async {
    final dir = await _backupDir();
    final now = DateTime.now();
    final name =
        'feder-sicherung-${now.year}-${_two(now.month)}-${_two(now.day)}_'
        '${_two(now.hour)}${_two(now.minute)}.zip';
    final target = '${dir.path}/$name';
    final source = FileManager.documentsDirectory;

    final count = await compute(_zip, [source, target]);
    if (count == 0) {
      File(target).deleteSync();
      throw StateError('Keine Dateien zum Sichern gefunden.');
    }

    final old =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.zip'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in old.skip(keepLocal)) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
    return File(target);
  }

  static Future<int> _zip(List<String> args) async {
    final source = Directory(args[0]);
    final encoder = ZipFileEncoder()..create(args[1]);
    var count = 0;
    for (final entity in source.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (entity.path.endsWith('.feder-tmp')) continue;
      final relative = entity.path
          .substring(source.path.length)
          .replaceAll('\\', '/')
          .replaceFirst(RegExp('^/'), '');
      await encoder.addFile(entity, relative);
      count++;
    }
    await encoder.close();
    return count;
  }

  /// Spielt eine Sicherung ein.
  ///
  /// [replaceExisting] = false: nur Dateien, die lokal fehlen.
  /// [replaceExisting] = true: alle Dateien aus der Sicherung; vorhandene
  /// werden überschrieben (vorher wird automatisch eine Sicherung erstellt).
  static Future<({int restored, int skipped})> restore(
    File zipFile, {
    required bool replaceExisting,
  }) async {
    if (replaceExisting) await create();

    final input = InputFileStream(zipFile.path);
    var restored = 0;
    var skipped = 0;
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive) {
        if (!entry.isFile) continue;
        final name = entry.name.replaceAll('\\', '/');
        // Pfad-Tricks ausschließen.
        if (name.startsWith('/') ||
            name.split('/').any((part) => part == '..' || part.isEmpty)) {
          skipped++;
          continue;
        }
        final relative = '/$name';
        if (!replaceExisting && FileManager.getFile(relative).existsSync()) {
          skipped++;
          continue;
        }
        final bytes = entry.content as List<int>;
        await FileManager.restoreRawFile(relative, bytes);
        restored++;
      }
    } finally {
      await input.close();
    }
    return (restored: restored, skipped: skipped);
  }
}
