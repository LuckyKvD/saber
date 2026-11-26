/// Feder: Erkennt in deutschem Text eine Fälligkeit ("bis Freitag",
/// "morgen 14 Uhr", "15.12.", "in 2 Wochen", "Ende des Monats").
class DueGuess {
  const DueGuess(this.date, {this.hour, this.minute});

  /// Nur Datum (Uhrzeit 00:00).
  final DateTime date;
  final int? hour;
  final int? minute;

  bool get hasTime => hour != null;

  @override
  String toString() => 'DueGuess($date, $hour:$minute)';
}

abstract class DueDateParser {
  static const _weekdays = {
    'montag': DateTime.monday,
    'dienstag': DateTime.tuesday,
    'mittwoch': DateTime.wednesday,
    'donnerstag': DateTime.thursday,
    'freitag': DateTime.friday,
    'samstag': DateTime.saturday,
    'sonnabend': DateTime.saturday,
    'sonntag': DateTime.sunday,
  };

  static const _months = {
    'januar': 1,
    'februar': 2,
    'märz': 3,
    'maerz': 3,
    'april': 4,
    'mai': 5,
    'juni': 6,
    'juli': 7,
    'august': 8,
    'september': 9,
    'oktober': 10,
    'november': 11,
    'dezember': 12,
  };

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _addDays(DateTime d, int n) =>
      DateTime(d.year, d.month, d.day + n);

  /// Gibt `null` zurück, wenn im Text nichts Erkennbares steht.
  static DueGuess? parse(String input, DateTime now) {
    var text = input.toLowerCase();
    final today = _day(now);
    DateTime? date;

    // 1) Datum mit Punkten: 15.12. / 15.12.26 / 15.12.2026
    final numeric = RegExp(r'(\d{1,2})\.\s?(\d{1,2})\.(?:\s?(\d{4}|\d{2}))?');
    final m1 = numeric.firstMatch(text);
    if (m1 != null) {
      final d = int.parse(m1.group(1)!);
      final mo = int.parse(m1.group(2)!);
      var y = m1.group(3) == null ? today.year : int.parse(m1.group(3)!);
      if (y < 100) y += 2000;
      if (_valid(y, mo, d)) {
        var candidate = DateTime(y, mo, d);
        if (m1.group(3) == null && candidate.isBefore(today)) {
          candidate = DateTime(y + 1, mo, d);
        }
        date = candidate;
        text = text.replaceRange(m1.start, m1.end, ' ');
      }
    }

    // 2) Datum mit Monatsname: 15. Dezember (2026)
    if (date == null) {
      final names = _months.keys.join('|');
      final named = RegExp('(\\d{1,2})\\.?\\s*($names)(?:\\s+(\\d{4}))?');
      final m2 = named.firstMatch(text);
      if (m2 != null) {
        final d = int.parse(m2.group(1)!);
        final mo = _months[m2.group(2)!]!;
        final y = m2.group(3) == null ? today.year : int.parse(m2.group(3)!);
        if (_valid(y, mo, d)) {
          var candidate = DateTime(y, mo, d);
          if (m2.group(3) == null && candidate.isBefore(today)) {
            candidate = DateTime(y + 1, mo, d);
          }
          date = candidate;
          text = text.replaceRange(m2.start, m2.end, ' ');
        }
      }
    }

    // 3) Relative Angaben
    if (date == null) {
      if (text.contains('übermorgen') || text.contains('uebermorgen')) {
        date = _addDays(today, 2);
      } else if (RegExp(r'(^|[^a-zäöüß])morgen($|[^a-zäöüß])').hasMatch(text)) {
        date = _addDays(today, 1);
      } else if (RegExp(r'(^|[^a-zäöüß])heute($|[^a-zäöüß])').hasMatch(text)) {
        date = today;
      }
    }
    if (date == null) {
      final inN = RegExp(
        r'in\s+(\d{1,2})\s+(tag|tagen|woche|wochen|monat|monaten)',
      ).firstMatch(text);
      if (inN != null) {
        final n = int.parse(inN.group(1)!);
        final unit = inN.group(2)!;
        if (unit.startsWith('tag')) {
          date = _addDays(today, n);
        } else if (unit.startsWith('woche')) {
          date = _addDays(today, 7 * n);
        } else {
          date = DateTime(today.year, today.month + n, today.day);
        }
      }
    }
    if (date == null) {
      if (RegExp(r'(ende (des )?monats|monatsende)').hasMatch(text)) {
        date = DateTime(today.year, today.month + 1, 0);
      } else if (RegExp(
        r'(ende (der )?woche|diese woche|wochenende)',
      ).hasMatch(text)) {
        var ahead = (DateTime.friday - today.weekday + 7) % 7;
        date = _addDays(today, ahead);
      } else if (RegExp(r'(nächste|naechste|kommende) woche').hasMatch(text)) {
        date = _addDays(today, (DateTime.monday - today.weekday + 7) % 7 + (today.weekday == DateTime.monday ? 7 : 0));
      }
    }
    if (date == null) {
      for (final entry in _weekdays.entries) {
        if (RegExp('(^|[^a-zäöüß])${entry.key}(\$|[^a-zäöüß])').hasMatch(text)) {
          var ahead = (entry.value - today.weekday + 7) % 7;
          if (ahead == 0) ahead = 7;
          date = _addDays(today, ahead);
          break;
        }
      }
    }

    if (date == null) return null;

    // Uhrzeit: "14:30", "14 Uhr", "um 9.30"
    int? hour, minute;
    final t1 = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
    final t2 = RegExp(r'(\d{1,2})(?:[.:](\d{2}))?\s*uhr').firstMatch(text);
    final t3 = RegExp(r'um\s+(\d{1,2})[.](\d{2})').firstMatch(text);
    final t = t1 ?? t2 ?? t3;
    if (t != null) {
      final h = int.parse(t.group(1)!);
      final mi = t.group(2) == null ? 0 : int.parse(t.group(2)!);
      if (h < 24 && mi < 60) {
        hour = h;
        minute = mi;
      }
    }
    return DueGuess(date, hour: hour, minute: minute);
  }

  static bool _valid(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return false;
    final dt = DateTime(y, m, d);
    return dt.month == m && dt.day == d;
  }
}
