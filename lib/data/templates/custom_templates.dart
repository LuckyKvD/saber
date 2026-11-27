import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Feder: Eine selbst gespeicherte Vorlage (Striche und Bilder aus einer
/// Lasso-Auswahl). Liegt als JSON-Datei nur lokal auf dem Gerät, nicht in
/// den Notizen, nicht im Code und nicht im Repository.
class CustomTemplate {
  const CustomTemplate({
    required this.id,
    required this.name,
    required this.width,
    required this.height,
    required this.originX,
    required this.strokes,
    required this.images,
  });

  final String id;
  final String name;

  /// Größe des gespeicherten Bereichs in Seiteneinheiten.
  final double width, height;

  /// Ursprüngliche linke Kante auf der Seite (für die Einfüge-Position).
  final double originX;

  /// Striche als JSON, Koordinaten relativ zur linken oberen Ecke des Bereichs.
  final List<Map<String, dynamic>> strokes;

  /// Bilder: `b` (Base64), `e` (Endung), `x`, `y`, `w`, `h` relativ zur Ecke.
  final List<Map<String, dynamic>> images;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'id': id,
    'name': name,
    'w': width,
    'h': height,
    'ox': originX,
    'strokes': strokes,
    'images': images,
  };

  static CustomTemplate? fromJson(Map<String, dynamic> json) {
    try {
      return CustomTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
        originX: (json['ox'] as num?)?.toDouble() ?? 0,
        strokes: [
          for (final s in json['strokes'] as List<dynamic>)
            Map<String, dynamic>.from(s as Map),
        ],
        images: [
          for (final i in json['images'] as List<dynamic>)
            Map<String, dynamic>.from(i as Map),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

abstract class CustomTemplates {
  static Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/feder_vorlagen');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<CustomTemplate>> list() async {
    final dir = await _dir();
    final result = <CustomTemplate>[];
    for (final f in dir.listSync()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final t = CustomTemplate.fromJson(json);
        if (t != null) result.add(t);
      } catch (_) {
        // beschädigte Datei überspringen
      }
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  static Future<void> save(CustomTemplate template) async {
    final dir = await _dir();
    await File('${dir.path}/${template.id}.json').writeAsString(
      jsonEncode(template.toJson()),
    );
  }

  static Future<void> delete(String id) async {
    final dir = await _dir();
    final f = File('${dir.path}/$id.json');
    if (f.existsSync()) await f.delete();
  }

  /// Neue, eindeutige Kennung (nur Ziffern, Dateiname-tauglich).
  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
