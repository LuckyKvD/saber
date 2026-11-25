import 'dart:typed_data';

import 'package:saber/components/canvas/_asset_cache.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/pages/editor/editor.dart';

/// Kopiert Seiten aus [source] ans Ende des Notizbuchs [targetPath]
/// (Pfad ohne Dateiendung). Das Zielbuch wird geladen, erweitert und
/// gespeichert. Gibt die Zahl der kopierten Seiten zurück.
Future<int> copyPagesToNote({
  required EditorCoreInfo source,
  required List<int> pageIndexes,
  required String targetPath,
}) async {
  final target = await EditorCoreInfo.loadFromFilePath(targetPath);
  try {
    if (target.readOnly) {
      throw StateError('Zielnotizbuch ist schreibgeschützt');
    }

    final sorted = [...pageIndexes]..sort();
    final newPages = <EditorPage>[];
    for (final index in sorted) {
      final assets = OrderedAssetCache();
      final json = source.pages[index].toJson(assets);
      final bytes = <Uint8List>[
        for (var i = 0; i < assets.length; ++i) await assets.getBytes(i),
      ];
      final page = EditorPage.fromJson(
        json,
        inlineAssets: bytes,
        readOnly: false,
        fileVersion: EditorCoreInfo.sbnVersion,
        sbnPath: targetPath,
        assetCache: target.assetCache,
      );
      // Bild-IDs müssen innerhalb eines Notizbuchs eindeutig sein.
      for (final image in page.images) {
        image.id = target.nextImageId++;
      }
      final background = page.backgroundImage;
      if (background != null) background.id = target.nextImageId++;
      newPages.add(page);
    }

    // Vor einer leeren Schlussseite einfügen und eine Schlussseite sichern.
    final insertAt = (target.pages.isNotEmpty && target.pages.last.isEmpty)
        ? target.pages.length - 1
        : target.pages.length;
    target.pages.insertAll(insertAt, newPages);
    if (!target.pages.last.isEmpty) target.pages.add(EditorPage());
    for (var i = 0; i < target.pages.length; i++) {
      target.pages[i].updatePageIndex(i);
    }

    final Uint8List bson;
    final OrderedAssetCache targetAssets;
    target.assetCache.allowRemovingAssets = false;
    try {
      (bson, targetAssets) = target.saveToBinary(currentPageIndex: null);
    } finally {
      target.assetCache.allowRemovingAssets = true;
    }

    // Erst alles lesen, dann schreiben.
    final assetBytes = <Uint8List>[
      for (var i = 0; i < targetAssets.length; ++i)
        await targetAssets.getBytes(i),
    ];
    final filePath = targetPath + Editor.extension;
    await Future.wait([
      FileManager.writeFile(filePath, bson, awaitWrite: true),
      for (var i = 0; i < assetBytes.length; ++i)
        FileManager.writeFile('$filePath.$i', assetBytes[i], awaitWrite: true),
      FileManager.removeUnusedAssets(filePath, numAssets: targetAssets.length),
    ]);
    return newPages.length;
  } finally {
    target.dispose();
  }
}
