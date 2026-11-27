import 'dart:convert';

import 'package:saber/data/prefs.dart';

/// Feder: Korrekturwörterbuch für die Handschrifterkennung.
///
/// Die Erkennung selbst lässt sich nicht trainieren. Stattdessen merkt sich
/// dieses Wörterbuch, was du in „Handschrift in Text" verbessert hast
/// (erkannt → richtig) und wendet es danach automatisch an. Die Einträge
/// liegen nur auf dem Gerät in den Einstellungen.
abstract final class CorrectionDictionary {
  static const _maxEntries = 800;

  static Map<String, String> _load() {
    try {
      final raw = stows.handwritingCorrections.value;
      if (raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String) e.key.toString(): e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  static void _save(Map<String, String> map) {
    stows.handwritingCorrections.value = jsonEncode(map);
  }

  static int get count => _load().length;

  static void clear() => stows.handwritingCorrections.value = '';

  static final _word = RegExp(r'[^\s]+');

  /// Trennt Satzzeichen am Rand ab: „Haus," → ('', 'Haus', ',').
  static (String, String, String) _split(String token) {
    final m = RegExp(r'^([^\p{L}\p{N}]*)(.*?)([^\p{L}\p{N}]*)$', unicode: true)
        .firstMatch(token);
    if (m == null) return ('', token, '');
    return (m.group(1)!, m.group(2)!, m.group(3)!);
  }

  static String _matchCase(String replacement, String original) {
    if (original.isNotEmpty &&
        replacement.isNotEmpty &&
        original[0] == original[0].toUpperCase() &&
        original[0] != original[0].toLowerCase()) {
      return replacement[0].toUpperCase() + replacement.substring(1);
    }
    return replacement;
  }

  /// Wendet das Wörterbuch auf [text] an (Wort für Wort).
  static String apply(String text) {
    final map = _load();
    if (map.isEmpty || text.isEmpty) return text;
    return text.replaceAllMapped(_word, (m) {
      final (pre, core, post) = _split(m.group(0)!);
      final fix = map[core.toLowerCase()];
      if (fix == null) return m.group(0)!;
      return '$pre${_matchCase(fix, core)}$post';
    });
  }

  /// Lernt aus einer Verbesserung: [recognized] ist, was die Erkennung
  /// geliefert hat, [corrected] der Text nach deiner Bearbeitung.
  /// Es wird nur gelernt, wenn beide gleich viele Wörter haben.
  /// Gibt die Zahl neu gelernter Wörter zurück.
  static int learn(String recognized, String corrected) {
    final a = _word.allMatches(recognized).map((m) => m.group(0)!).toList();
    final b = _word.allMatches(corrected).map((m) => m.group(0)!).toList();
    if (a.length != b.length || a.isEmpty) return 0;
    final map = _load();
    var learned = 0;
    var changed = false;
    for (var i = 0; i < a.length; i++) {
      final from = _split(a[i]).$2.toLowerCase();
      final to = _split(b[i]).$2;
      if (from.isEmpty || to.isEmpty) continue;
      if (from == to.toLowerCase()) {
        // Du hast die Erkennung bestätigt: alte Regel für dieses Wort löschen.
        if (map.remove(from) != null) changed = true;
        continue;
      }
      // Nur ein Wort ersetzen, keine Zahlen-/Satzteile mischen.
      if (map[from] != to.toLowerCase() && map[from] != to) {
        map[from] = to;
        learned++;
        changed = true;
      }
    }
    if (map.length > _maxEntries) {
      final drop = map.keys.take(map.length - _maxEntries).toList();
      for (final k in drop) {
        map.remove(k);
      }
    }
    if (changed) _save(map);
    return learned;
  }
}
