/// Feder: Textvergleich für die Handschrift-Suche. Handschrift-Erkennung macht
/// Fehler, deshalb wird unscharf verglichen (Tippfehler, Umlaute, Wortanfänge).
abstract class SearchText {
  static const _map = {
    'ä': 'a', 'ö': 'o', 'ü': 'u', 'ß': 'ss',
    'á': 'a', 'à': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ç': 'c', 'ñ': 'n',
  };

  /// Kleinbuchstaben, Umlaute und Akzente vereinfacht, Sonderzeichen → Leerzeichen.
  static String normalize(String s) {
    final b = StringBuffer();
    for (final rune in s.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final mapped = _map[ch];
      if (mapped != null) {
        b.write(mapped);
      } else if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        b.write(ch);
      } else {
        b.write(' ');
      }
    }
    return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static List<String> tokens(String normalized) =>
      normalized.isEmpty ? const [] : normalized.split(' ');

  /// Erlaubte Abweichung (Editierabstand) je Wortlänge.
  static int maxDistance(int length) {
    if (length <= 4) return 0;
    if (length <= 8) return 1;
    return 2;
  }

  /// Editierabstand (Levenshtein), bricht ab, wenn [limit] überschritten ist.
  static int distance(String a, String b, {int limit = 3}) {
    if ((a.length - b.length).abs() > limit) return limit + 1;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j - 1] + cost;
        if (prev[j] + 1 < v) v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > limit) return limit + 1;
      prev = cur;
    }
    return prev[b.length];
  }

  /// Passt das Suchwort [q] auf das Textwort [t]? (Teilwort, Wortanfang oder
  /// kleiner Abstand, so dass auch "Besprech" ein "Besprechung" findet.)
  static bool tokenMatches(String q, String t) {
    if (q.isEmpty) return false;
    if (t.contains(q)) return true;
    final limit = maxDistance(q.length);
    if (limit == 0) return false;
    if (distance(q, t, limit: limit) <= limit) return true;
    if (t.length > q.length) {
      return distance(q, t.substring(0, q.length), limit: limit) <= limit;
    }
    return false;
  }

  /// Enthält [text] alle Wörter aus [query] (unscharf)? Beide unnormalisiert.
  static bool matches(String text, String query) {
    final qTokens = tokens(normalize(query));
    if (qTokens.isEmpty) return false;
    final tTokens = tokens(normalize(text));
    for (final q in qTokens) {
      if (!tTokens.any((t) => tokenMatches(q, t))) return false;
    }
    return true;
  }
}
