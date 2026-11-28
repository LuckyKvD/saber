import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/pages/editor/editor.dart';

/// Ort, an dem ein Tagebuchtag begonnen wurde.
class DiaryLocation {
  const DiaryLocation({required this.lat, required this.lon, this.accuracy});

  final double lat;
  final double lon;
  final double? accuracy;

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon, 'acc': accuracy};

  static DiaryLocation? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return DiaryLocation(
      lat: lat,
      lon: lon,
      accuracy: (json['acc'] as num?)?.toDouble(),
    );
  }

  String get label =>
      '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

  Uri get mapUri => Uri.parse('geo:$lat,$lon?q=$lat,$lon');
}

/// Feder-Tagebuch: Ein Notizbuch pro Kalendertag unter
/// `/Tagebuch/JJJJ/MM/JJJJ-MM-TT`. Mehrere Einträge eines Tages sind weitere
/// Seiten desselben Notizbuchs. Der Ort liegt in `….ort` daneben.
abstract class Diary {
  static final _log = Logger('Diary');

  static const rootName = 'Tagebuch';
  static const root = '/$rootName';

  static const _channel = MethodChannel('de.luckykvd.feder/location');

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String monthDir(int year, int month) =>
      '$root/$year/${_two(month)}';

  static String pathFor(DateTime day) =>
      '${monthDir(day.year, day.month)}/'
      '${day.year}-${_two(day.month)}-${_two(day.day)}';

  static bool exists(DateTime day) =>
      FileManager.doesFileExist('${pathFor(day)}${Editor.extension}');

  static bool isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  static bool isDiaryPath(String filePath) => filePath.startsWith('$root/');

  /// Liest ein Datum aus einem Dateinamen: `2026-11-28` oder `28.11.2026`.
  static DateTime? dayFromName(String name) {
    var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(name.trim());
    int? y, mo, d;
    if (m != null) {
      y = int.parse(m.group(1)!);
      mo = int.parse(m.group(2)!);
      d = int.parse(m.group(3)!);
    } else {
      m = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(name.trim());
      if (m == null) return null;
      d = int.parse(m.group(1)!);
      mo = int.parse(m.group(2)!);
      y = int.parse(m.group(3)!);
    }
    final date = DateTime(y, mo, d);
    if (date.year != y || date.month != mo || date.day != d) return null;
    return date;
  }

  /// Einträge unter `/Tagebuch`, deren Name kein Datum ist (z. B. nach dem
  /// Umbenennen). Sie lassen sich im Editor per Titel wieder auf ein Datum
  /// setzen.
  static Future<List<String>> strayEntries() async {
    final all = await FileManager.getAllFiles();
    return all
        .where(
          (p) =>
              isDiaryPath(p) &&
              dayFromName(p.substring(p.lastIndexOf('/') + 1)) == null,
        )
        .toList()
      ..sort();
  }

  /// Tage (1–31) des Monats, für die ein Eintrag existiert.
  static Future<Set<int>> daysWithEntries(int year, int month) async {
    final children = await FileManager.getChildrenOfDirectory(
      monthDir(year, month),
    );
    final days = <int>{};
    final pattern = RegExp(r'(\d{4})-(\d{2})-(\d{2})$');
    for (final file in children?.files ?? const <String>[]) {
      final m = pattern.firstMatch(file);
      if (m == null) continue;
      days.add(int.parse(m.group(3)!));
    }
    return days;
  }

  /// Fragt (falls nötig) die Berechtigung und liefert den aktuellen Ort,
  /// oder `null`. Der Ort kommt vom Betriebssystem, es werden keine
  /// Online-Dienste befragt.
  static Future<DiaryLocation?> captureLocation() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return null;
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('get')
          .timeout(const Duration(seconds: 15));
      if (raw == null) return null;
      return DiaryLocation.fromJson(raw.cast<String, dynamic>());
    } catch (e) {
      _log.warning('Ort nicht ermittelbar: $e');
      return null;
    }
  }

  /// Alle gespeicherten Orte mit ihrem Tag.
  static Future<List<(DateTime, DiaryLocation)>> allLocations() async {
    final result = <(DateTime, DiaryLocation)>[];
    final dir = Directory('${FileManager.documentsDirectory}$root');
    if (!dir.existsSync()) return result;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.ort')) continue;
      final base = entity.path.substring(
        entity.path.lastIndexOf('/') + 1,
        entity.path.length - 4,
      );
      final day = dayFromName(base);
      if (day == null) continue;
      final loc = await readLocation(day);
      if (loc != null) result.add((day, loc));
    }
    result.sort((a, b) => a.$1.compareTo(b.$1));
    return result;
  }

  static String _locPath(DateTime day) => '${pathFor(day)}.ort';

  static Future<void> saveLocation(DateTime day, DiaryLocation loc) async {
    if (FileManager.doesFileExist(_locPath(day))) return;
    await FileManager.writeFile(
      _locPath(day),
      utf8.encode(jsonEncode(loc.toJson())),
      awaitWrite: true,
    );
  }

  static Future<DiaryLocation?> readLocation(DateTime day) async {
    final path = _locPath(day);
    if (!FileManager.doesFileExist(path)) return null;
    try {
      final bytes = await FileManager.readBytes(FileManager.getFile(path));
      return DiaryLocation.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
    } catch (e) {
      _log.warning('Ort nicht lesbar: $e');
      return null;
    }
  }
}
