import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// Seitenränder in Zentimetern.
class DocMargins {
  const DocMargins({
    this.top = 2.5,
    this.bottom = 2.0,
    this.left = 2.5,
    this.right = 2.0,
  });

  final double top, bottom, left, right;

  DocMargins copyWith({double? top, double? bottom, double? left, double? right}) =>
      DocMargins(
        top: top ?? this.top,
        bottom: bottom ?? this.bottom,
        left: left ?? this.left,
        right: right ?? this.right,
      );

  List<double> toJson() => [top, bottom, left, right];

  static DocMargins fromJson(Object? json) {
    if (json is List && json.length == 4) {
      final v = [for (final e in json) (e as num).toDouble()];
      return DocMargins(top: v[0], bottom: v[1], left: v[2], right: v[3]);
    }
    return const DocMargins();
  }
}

/// Inhalt eines Feder-Dokuments: Quill-Delta plus Seitenränder.
class FederDoc {
  FederDoc({List<dynamic>? delta, this.margins = const DocMargins()})
    : delta = delta ?? const [];

  List<dynamic> delta;
  DocMargins margins;

  String toJsonString() => jsonEncode({
    'v': 1,
    'm': margins.toJson(),
    'd': delta,
  });

  static FederDoc fromJsonString(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return FederDoc(
      delta: (json['d'] as List?) ?? const [],
      margins: DocMargins.fromJson(json['m']),
    );
  }
}

/// Feder-Dokumente (Textverarbeitung): `/Dokumente/…/Name.fdoc`. Verschlüsselung,
/// Nextcloud-Sync und Sicherung laufen wie bei allen anderen Dateien.
abstract class Documents {
  static final _log = Logger('Documents');

  static const rootName = 'Dokumente';
  static const root = '/$rootName';
  static const extension = '.fdoc';

  static bool isDocPath(String path) => path.startsWith('$root/');

  static String baseName(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  /// Ordner und Dokumente (Pfad ohne Endung) direkt in [dir].
  static ({List<String> folders, List<String> docs}) list(String dir) {
    final d = Directory('${FileManager.documentsDirectory}$dir');
    final folders = <String>[];
    final docs = <String>[];
    if (d.existsSync()) {
      for (final e in d.listSync(followLinks: false)) {
        final name = e.path.substring(e.path.lastIndexOf(Platform.pathSeparator) + 1);
        if (e is Directory) {
          folders.add(name);
        } else if (e is File && name.endsWith(extension)) {
          docs.add(name.substring(0, name.length - extension.length));
        }
      }
    }
    int cmp(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    folders.sort(cmp);
    docs.sort(cmp);
    return (folders: folders, docs: docs);
  }

  static bool exists(String path) =>
      FileManager.doesFileExist('$path$extension');

  static Future<FederDoc> load(String path) async {
    if (!exists(path)) return FederDoc();
    try {
      final bytes = await FileManager.readBytes(
        FileManager.getFile('$path$extension'),
      );
      if (bytes.isEmpty) return FederDoc();
      return FederDoc.fromJsonString(utf8.decode(bytes));
    } catch (e, st) {
      _log.severe('Dokument nicht lesbar: $path', e, st);
      rethrow;
    }
  }

  static Future<void> save(String path, FederDoc doc) async {
    await FileManager.writeFile(
      '$path$extension',
      utf8.encode(doc.toJsonString()),
      awaitWrite: true,
    );
  }

  /// Freier Name in [dir] (hängt bei Bedarf " 2", " 3" … an).
  static String uniquePath(String dir, String name) {
    var path = '$dir/$name';
    var n = 2;
    while (exists(path)) {
      path = '$dir/$name $n';
      n++;
    }
    return path;
  }

  static Future<void> delete(String path) =>
      FileManager.deleteFile('$path$extension');

  /// Benennt um oder verschiebt (neuer vollständiger Pfad ohne Endung).
  static Future<String> move(String oldPath, String newPath) async {
    final moved = await FileManager.moveFile(
      '$oldPath$extension',
      '$newPath$extension',
    );
    return moved.substring(0, moved.length - extension.length);
  }
}
