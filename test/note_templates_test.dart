import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tables/table_builder.dart';
import 'package:saber/data/templates/note_templates.dart';

void main() {
  const page = Size(1000, 1400);
  final date = DateTime(2026, 11, 27);

  test('Datum deutsch', () {
    expect(NoteTemplates.formatDate(date), '27.11.2026');
  });

  test('Besprechung enthält Titel, Datum und eine Aufgabentabelle', () {
    final c = NoteTemplates.build(
      NoteTemplate.meeting,
      page: page,
      cell: 40,
      date: date,
      rng: math.Random(1),
    );
    expect(c.texts.any((t) => t.text == 'Besprechung'), isTrue);
    expect(c.texts.any((t) => t.text == '27.11.2026'), isTrue);
    // 4 Aufgaben + Kopfzeile = 5 Zeilen -> 6 waagerechte, 3 Spalten -> 4 senkrechte Linien
    expect(c.tableLines.where((l) => l.axis == TableBuilder.horizontal).length, 6);
    expect(c.tableLines.where((l) => l.axis == TableBuilder.vertical).length, 4);
  });

  test('Alles liegt innerhalb der Seite', () {
    for (final t in NoteTemplate.values) {
      final c = NoteTemplates.build(
        t,
        page: page,
        cell: 40,
        date: date,
        rng: math.Random(2),
      );
      for (final line in [...c.underlines, ...c.tableLines.map((l) => l.points)]) {
        for (final p in line) {
          expect(p.dx, inInclusiveRange(0, page.width));
          expect(p.dy, inInclusiveRange(0, page.height));
        }
      }
    }
  });

  test('Vorlagenname wird erkannt', () {
    expect(NoteTemplate.parse('meeting'), NoteTemplate.meeting);
    expect(NoteTemplate.parse('jourFixe'), NoteTemplate.jourFixe);
    expect(NoteTemplate.parse('x'), isNull);
  });
}
