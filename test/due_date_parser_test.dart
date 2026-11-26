import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tasks/due_date_parser.dart';

void main() {
  // Donnerstag, 26.11.2026
  final now = DateTime(2026, 11, 26, 9, 0);

  test('Wochentag: nächster Freitag', () {
    expect(DueDateParser.parse('Angebot prüfen bis Freitag', now)?.date,
        DateTime(2026, 11, 27));
  });
  test('Gleicher Wochentag heißt nächste Woche', () {
    expect(DueDateParser.parse('Donnerstag Bericht', now)?.date,
        DateTime(2026, 12, 3));
  });
  test('morgen mit Uhrzeit', () {
    final g = DueDateParser.parse('Anruf morgen 14 Uhr', now)!;
    expect(g.date, DateTime(2026, 11, 27));
    expect(g.hour, 14);
    expect(g.minute, 0);
  });
  test('übermorgen', () {
    expect(DueDateParser.parse('übermorgen erledigen', now)?.date,
        DateTime(2026, 11, 28));
  });
  test('Datum ohne Jahr', () {
    expect(DueDateParser.parse('bis 15.12.', now)?.date, DateTime(2026, 12, 15));
  });
  test('Datum ohne Jahr in der Vergangenheit: nächstes Jahr', () {
    expect(DueDateParser.parse('1.11.', now)?.date, DateTime(2027, 11, 1));
  });
  test('Datum mit Jahr', () {
    expect(DueDateParser.parse('am 3.2.2027', now)?.date, DateTime(2027, 2, 3));
  });
  test('Monatsname', () {
    expect(DueDateParser.parse('bis 30. Dezember', now)?.date,
        DateTime(2026, 12, 30));
  });
  test('in 2 Wochen', () {
    expect(DueDateParser.parse('in 2 Wochen', now)?.date, DateTime(2026, 12, 10));
  });
  test('Monatsende', () {
    expect(DueDateParser.parse('Ende des Monats', now)?.date,
        DateTime(2026, 11, 30));
  });
  test('nichts erkannt', () {
    expect(DueDateParser.parse('Angebot einholen', now), isNull);
  });
}
