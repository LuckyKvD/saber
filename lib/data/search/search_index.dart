import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saber/components/canvas/_circle_stroke.dart';
import 'package:saber/components/canvas/_rectangle_stroke.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/crypto/local_crypto.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/search/line_grouper.dart';
import 'package:saber/data/search/search_text.dart';
import 'package:saber/data/tasks/ink_recognition.dart';
import 'package:saber/pages/editor/editor.dart';

/// Ein Treffer der Handschrift-Suche.
class SearchHit {
  const SearchHit(this.path, this.pageIndex, this.snippet, this.score);

  /// Pfad der Notiz ohne Endung, z. B. `/Ordner/Notiz`.
  final String path;
  final int pageIndex;
  final String snippet;

  /// Größer = besserer Treffer (mehr passende Zeilen).
  final int score;
}

/// Feder: Suchindex für Handschrift und getippten Text. Liegt nur lokal auf
/// dem Gerät (App-Ordner), wird bei aktiver lokaler Verschlüsselung
/// verschlüsselt und nicht mit Nextcloud abgeglichen. Jedes Gerät baut seinen
/// eigenen Index.
abstract class SearchIndex {
  static final log = Logger('SearchIndex');

  /// Einträge: Notizpfad → {m: Änderungszeit (ms), pages: [[Zeilen]]}.
  /// Eine Zeile ist `beste|Alternative|Alternative` (Erkennungs-Kandidaten).
  static Map<String, dynamic>? _data;

  static Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/feder_suche');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return File('${dir.path}/index.bin');
  }

  static Future<Map<String, dynamic>> load() async {
    if (_data != null) return _data!;
    try {
      final f = await _file();
      if (f.existsSync()) {
        var bytes = await f.readAsBytes();
        if (LocalCrypto.isEncrypted(bytes)) {
          await LocalCrypto.ensureReady();
          bytes = await LocalCrypto.decrypt(bytes);
        }
        _data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      }
    } catch (e) {
      log.warning('Suchindex nicht lesbar, wird neu aufgebaut: $e');
    }
    return _data ??= <String, dynamic>{};
  }

  static Future<void> _save() async {
    final data = _data;
    if (data == null) return;
    var bytes = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    await LocalCrypto.ensureReady();
    if (LocalCrypto.isActive) bytes = await LocalCrypto.encrypt(bytes);
    await (await _file()).writeAsBytes(bytes);
  }

  static Future<void> clear() async {
    _data = <String, dynamic>{};
    final f = await _file();
    if (f.existsSync()) await f.delete();
  }

  static int get indexedNotes => _data?.length ?? 0;

  // ---- Hintergrund-Indexierung -------------------------------------------

  /// Alle Indexläufe laufen nacheinander (Suchseite, Hintergrund, Speichern).
  static Future<void> _tail = Future<void>.value();

  static Future<T> _exclusive<T>(Future<T> Function() job) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        done.complete(await job());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  static final _noteTimers = <String, Timer>{};
  static Timer? _startTimer;
  static var _backgroundRunning = false;

  /// Eine Notiz wurde gespeichert: nach kurzer Ruhe nur diese Notiz neu lesen.
  static void noteSaved(String path) {
    if (!stows.searchBackgroundIndex.value || !InkRecognition.supported) return;
    _noteTimers[path]?.cancel();
    _noteTimers[path] = Timer(const Duration(seconds: 30), () {
      _noteTimers.remove(path);
      unawaited(_updateNote(path));
    });
  }

  static Future<void> _updateNote(String path) => _exclusive(() async {
    try {
      final data = await load();
      final mtime = FileManager.lastModified(path + Editor.extension)
          .millisecondsSinceEpoch;
      final pages = await _readNote(path);
      data[path] = {'m': mtime, 'pages': pages};
      await _save();
    } catch (e) {
      log.fine('Hintergrund-Indexierung (Notiz) übersprungen: $e');
    }
  });

  /// Beim Start und beim Zurückkehren in die App: nach einer Wartezeit neue
  /// oder geänderte Notizen (z. B. von einem anderen Gerät) leise nachziehen.
  static void scheduleBackgroundRefresh({
    Duration delay = const Duration(seconds: 45),
  }) {
    if (!stows.searchBackgroundIndex.value || !InkRecognition.supported) return;
    if (_backgroundRunning) return;
    _startTimer?.cancel();
    _startTimer = Timer(delay, () async {
      if (_backgroundRunning || !stows.searchBackgroundIndex.value) return;
      _backgroundRunning = true;
      try {
        await refresh(pause: const Duration(milliseconds: 250));
      } catch (e) {
        log.fine('Hintergrund-Indexierung abgebrochen: $e');
      } finally {
        _backgroundRunning = false;
      }
    });
  }

  /// Striche, die wie Schrift aussehen (keine Linien, Tabellen, Formen, Bilder).
  static bool _looksLikeWriting(Stroke s, double cell) {
    if (s is CircleStroke || s is RectangleStroke) return false;
    if (s.tableAxis != null || s.isEmpty) return false;
    final b = _bounds(s);
    if (b.height > cell * 4) return false; // Zeichnung
    if (b.width > cell * 8 && b.height < cell * 0.3) return false; // Linie
    return true;
  }

  static Rect _bounds(Stroke s) {
    var l = double.infinity, t = double.infinity;
    var r = -double.infinity, b = -double.infinity;
    for (final p in s.pointsAsOffsets()) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  /// Liest alle Seiten einer Notiz und gibt je Seite die Zeilen zurück.
  static Future<List<List<String>>> _readNote(String path) async {
    final core = await EditorCoreInfo.loadFromFilePath(path);
    final cell = core.lineHeight.toDouble();
    final pages = <List<String>>[];
    for (final page in core.pages) {
      final lines = <String>[];

      // Getippter Text: direkt, ohne Erkennung.
      try {
        final typed = [
          page.quill.controller.document.toPlainText(),
          for (final b in page.textBoxes)
            b.quill.controller.document.toPlainText(),
          if (page.bookmark != null) page.bookmark!,
        ].join('\n');
        for (final line in typed.split('\n')) {
          if (line.trim().isNotEmpty) lines.add(line.trim());
        }
      } catch (_) {}

      // Handschrift: zeilenweise erkennen.
      if (InkRecognition.supported) {
        final writing = [
          for (final s in page.strokes)
            if (_looksLikeWriting(s, cell)) s,
        ];
        final groups = LineGrouper.group([
          for (final s in writing) _bounds(s),
        ], cell: cell);
        for (final g in groups) {
          try {
            final candidates = await InkRecognition.recognize([
              for (final i in g) writing[i],
            ]);
            if (candidates.isNotEmpty) {
              lines.add(candidates.take(3).join('|'));
            }
          } catch (e) {
            // Modell fehlt o. ä.: wird oben in der Oberfläche gemeldet.
            rethrow;
          }
        }
      }
      pages.add(lines);
    }
    return pages;
  }

  /// Aktualisiert den Index: neue und geänderte Notizen werden gelesen,
  /// gelöschte entfernt. [onProgress] meldet (erledigt, gesamt).
  /// Gibt die Anzahl neu gelesener Notizen zurück.
  static Future<int> refresh({
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
    Duration pause = Duration.zero,
  }) => _exclusive(
    () => _refresh(
      onProgress: onProgress,
      isCancelled: isCancelled,
      pause: pause,
    ),
  );

  static Future<int> _refresh({
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
    Duration pause = Duration.zero,
  }) async {
    final data = await load();
    final files = await FileManager.getAllFiles();
    final present = files.toSet();

    var changed = false;
    for (final key in data.keys.toList()) {
      if (!present.contains(key)) {
        data.remove(key);
        changed = true;
      }
    }

    final todo = <String>[];
    for (final path in files) {
      final entry = data[path] as Map<String, dynamic>?;
      final mtime = FileManager.lastModified(path + Editor.extension)
          .millisecondsSinceEpoch;
      if (entry == null || entry['m'] != mtime) todo.add(path);
    }

    var done = 0;
    onProgress?.call(0, todo.length);
    for (final path in todo) {
      if (isCancelled?.call() ?? false) break;
      try {
        final mtime = FileManager.lastModified(path + Editor.extension)
            .millisecondsSinceEpoch;
        final pages = await _readNote(path);
        data[path] = {'m': mtime, 'pages': pages};
        changed = true;
      } on UnsupportedError {
        rethrow;
      } catch (e, st) {
        log.warning('Notiz konnte nicht indexiert werden: $e', e, st);
        // Als gelesen markieren, damit sie nicht jedes Mal neu versucht wird.
        final mtime = FileManager.lastModified(path + Editor.extension)
            .millisecondsSinceEpoch;
        data[path] = {'m': mtime, 'pages': <List<String>>[]};
        changed = true;
      }
      done++;
      onProgress?.call(done, todo.length);
      if (done % 5 == 0) await _save();
      if (pause > Duration.zero) await Future<void>.delayed(pause);
    }
    if (changed) await _save();
    return done;
  }

  /// Sucht in allen indexierten Notizen. Beste Treffer zuerst.
  static Future<List<SearchHit>> search(String query, {String? scope}) async {
    final data = await load();
    final hits = <SearchHit>[];
    final folderPrefix = scope == null
        ? null
        : (scope.endsWith('/') ? scope : '$scope/');
    for (final entry in data.entries) {
      if (scope != null &&
          scope != '/' &&
          entry.key != scope &&
          !entry.key.startsWith(folderPrefix!)) {
        continue;
      }
      final pages = (entry.value as Map<String, dynamic>)['pages'] as List;
      for (var i = 0; i < pages.length; i++) {
        final lines = (pages[i] as List).cast<String>();
        var score = 0;
        String? snippet;
        // Treffer pro Zeile; zusätzlich Seitentreffer, wenn die Wörter auf
        // mehrere Zeilen verteilt sind.
        for (final line in lines) {
          if (SearchText.matches(line.replaceAll('|', ' '), query)) {
            score += 2;
            snippet ??= line.split('|').first;
          }
        }
        if (score == 0 && lines.isNotEmpty) {
          final all = lines.map((l) => l.split('|').first).join(' ');
          if (SearchText.matches(all, query)) {
            score = 1;
            snippet = lines.first.split('|').first;
          }
        }
        if (score > 0) {
          hits.add(SearchHit(entry.key, i, snippet ?? '', score));
        }
      }
    }
    hits.sort((a, b) {
      final c = b.score.compareTo(a.score);
      return c != 0 ? c : a.path.compareTo(b.path);
    });
    return hits;
  }
}
