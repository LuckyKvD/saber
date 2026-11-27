import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/tables/table_builder.dart';

void main() {
  final rng = math.Random(1);

  test('Neue Tabelle hat Zeilen+1 waagerechte und Spalten+1 senkrechte Linien', () {
    final lines = TableBuilder.grid(
      origin: const Offset(100, 100),
      cols: 3,
      rows: 2,
      cellW: 120,
      cellH: 60,
      rng: rng,
    );
    expect(lines.where((l) => l.axis == TableBuilder.horizontal).length, 3);
    expect(lines.where((l) => l.axis == TableBuilder.vertical).length, 4);
  });

  test('Geometrie wird aus den Linien erkannt', () {
    final lines = TableBuilder.grid(
      origin: const Offset(100, 100),
      cols: 3,
      rows: 2,
      cellW: 120,
      cellH: 60,
      rng: rng,
    );
    final g = TableBuilder.geometry(lines)!;
    expect(g.ys.length, 3);
    expect(g.xs.length, 4);
    expect(g.ys.first, closeTo(100, 3));
    expect(g.xs.last, closeTo(460, 3));
  });

  test('Erweitern: 1 Zeile + 1 Spalte', () {
    final lines = TableBuilder.grid(
      origin: Offset.zero,
      cols: 2,
      rows: 2,
      cellW: 100,
      cellH: 50,
      rng: rng,
    );
    final more = TableBuilder.extend(lines, addRows: 1, addCols: 1, rng: rng);
    // Zeile: 1 waagerechte + 3 senkrechte Stücke; Spalte: 1 senkrechte + 4 waagerechte Stücke.
    expect(more.length, 1 + 3 + 1 + 4);
    final all = [...lines, ...more];
    final g = TableBuilder.geometry(all)!;
    expect(g.ys.length, 4);
    expect(g.xs.length, 4);
  });

  test('Ohne Tabelle nichts erweitern', () {
    expect(TableBuilder.extend(const [], addRows: 1, addCols: 0, rng: rng), isEmpty);
  });
}
