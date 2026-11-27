import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/components/canvas/image/editor_image.dart';
import 'package:saber/components/canvas/image/png_editor_image.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/pages/editor/editor.dart';

/// Geladener Inhalt einer eigenen Vorlage (Koordinaten relativ zur linken
/// oberen Ecke, Größe in [size]).
class LoadedTemplate {
  const LoadedTemplate(this.strokes, this.images, this.size);

  final List<Stroke> strokes;

  /// Bilder als Rohdaten: (Endung, Bytes, Rechteck relativ zur Ecke).
  final List<(String, Uint8List, Rect)> images;
  final Size size;
}

/// Feder: Eigene Vorlagen sind ganz normale Feder-Notizen im versteckten
/// Ordner `/_Vorlagen`. Dadurch gelten Verschlüsselung und der Abgleich über
/// Nextcloud automatisch; es gibt kein eigenes Dateiformat.
abstract class CustomTemplates {
  static const folder = '/_Vorlagen';

  /// Gehört [path] zum Vorlagen-Ordner (wird in Listen und Zuletzt-Liste
  /// nicht angezeigt)?
  static bool isTemplatePath(String path) =>
      path == folder || path.startsWith('$folder/');

  static String _clean(String name) => name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Namen aller eigenen Vorlagen, alphabetisch.
  static Future<List<String>> list() async {
    final children = await FileManager.getChildrenOfDirectory(
      folder,
      hideInternal: false,
    );
    final names = [...?children?.files];
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static Future<bool> exists(String name) async =>
      (await list()).any((n) => n.toLowerCase() == _clean(name).toLowerCase());

  /// Speichert [strokes] und [images] (absolute Seitenkoordinaten) unter [name].
  /// Gibt die Anzahl nicht übernommener Bilder zurück.
  static Future<int> save(
    String name, {
    required List<Stroke> strokes,
    required List<EditorImage> images,
  }) async {
    name = _clean(name);
    if (name.isEmpty) throw ArgumentError('Name fehlt');

    var minX = double.infinity, minY = double.infinity;
    for (final s in strokes) {
      for (final p in s.pointsAsOffsets()) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
      }
    }
    for (final i in images) {
      minX = math.min(minX, i.dstRect.left);
      minY = math.min(minY, i.dstRect.top);
    }
    final origin = Offset(minX, minY);

    final path = '$folder/$name';
    final core = EditorCoreInfo(filePath: path);
    final page = EditorPage();
    core.pages.add(page);

    for (final s in strokes) {
      final copy = s.copy()
        ..shift(-origin)
        ..pageIndex = 0
        ..page = page;
      page.strokes.add(copy);
    }

    var skipped = 0;
    for (final i in images) {
      if (i is! PngEditorImage) {
        skipped++;
        continue;
      }
      try {
        final provider = i.imageProvider;
        final Uint8List bytes;
        if (provider is MemoryImage) {
          bytes = provider.bytes;
        } else if (provider is FileImage) {
          bytes = await FileManager.readBytes(provider.file);
        } else {
          skipped++;
          continue;
        }
        page.images.add(
          PngEditorImage(
            id: core.nextImageId++,
            extension: i.extension,
            imageProvider: MemoryImage(bytes),
            pageIndex: 0,
            pageSize: page.size,
            onMoveImage: null,
            onDeleteImage: null,
            onMiscChange: null,
            onLoad: null,
            newImage: false,
            assetCache: core.assetCache,
            dstRect: i.dstRect.shift(-origin),
          ),
        );
      } catch (_) {
        skipped++;
      }
    }

    final (bson, assets) = core.saveToBinary(currentPageIndex: 0);
    final assetBytes = [
      for (var n = 0; n < assets.length; n++) await assets.getBytes(n),
    ];
    final file = path + Editor.extension;
    await FileManager.writeFile(file, bson, awaitWrite: true);
    for (var n = 0; n < assetBytes.length; n++) {
      await FileManager.writeFile('$file.$n', assetBytes[n], awaitWrite: true);
    }
    return skipped;
  }

  /// Lädt eine Vorlage. Gibt null zurück, wenn sie fehlt oder leer ist.
  static Future<LoadedTemplate?> load(String name) async {
    final core = await EditorCoreInfo.loadFromFilePath('$folder/$name');
    if (core.pages.isEmpty) return null;
    final page = core.pages.first;

    var maxX = 0.0, maxY = 0.0;
    for (final s in page.strokes) {
      for (final p in s.pointsAsOffsets()) {
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
    }

    final images = <(String, Uint8List, Rect)>[];
    for (final i in page.images) {
      if (i is! PngEditorImage) continue;
      try {
        final provider = i.imageProvider;
        final Uint8List bytes;
        if (provider is MemoryImage) {
          bytes = provider.bytes;
        } else if (provider is FileImage) {
          bytes = await FileManager.readBytes(provider.file);
        } else {
          continue;
        }
        images.add((i.extension, bytes, i.dstRect));
        maxX = math.max(maxX, i.dstRect.right);
        maxY = math.max(maxY, i.dstRect.bottom);
      } catch (_) {
        // Bild überspringen
      }
    }
    if (page.strokes.isEmpty && images.isEmpty) return null;
    return LoadedTemplate([...page.strokes], images, Size(maxX, maxY));
  }

  static Future<void> delete(String name) =>
      FileManager.deleteFile('$folder/$name${Editor.extension}');
}
