import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/search/line_grouper.dart';
import 'package:saber/data/search/search_text.dart';

void main() {
  group('SearchText', () {
    test('normalize vereinfacht Umlaute und Sonderzeichen', () {
      expect(SearchText.normalize('  Größe: ÜBER-all! '), 'grosse uber all');
    });

    test('findet Teilwörter und Wortanfänge', () {
      expect(SearchText.matches('Protokoll der Besprechung', 'besprech'), isTrue);
      expect(SearchText.matches('Protokoll der Besprechung', 'protokol'), isTrue);
    });

    test('toleriert einen Erkennungsfehler bei längeren Wörtern', () {
      expect(SearchText.matches('Besprechnng heute', 'Besprechung'), isTrue);
      expect(SearchText.matches('Rechnung', 'Rechnnng'), isTrue);
    });

    test('kurze Wörter müssen exakt passen', () {
      expect(SearchText.matches('Haus Garten', 'Hans'), isFalse);
      expect(SearchText.matches('Haus Garten', 'Haus'), isTrue);
    });

    test('alle Suchwörter müssen vorkommen', () {
      expect(SearchText.matches('Rechnung Strom Januar', 'rechnung januar'), isTrue);
      expect(SearchText.matches('Rechnung Strom', 'rechnung januar'), isFalse);
    });

    test('leere Suche findet nichts', () {
      expect(SearchText.matches('Text', '   '), isFalse);
    });

    test('Editierabstand bricht ab', () {
      expect(SearchText.distance('abc', 'abc'), 0);
      expect(SearchText.distance('abcd', 'abxd'), 1);
      expect(SearchText.distance('abcdef', 'uvwxyz', limit: 2), 3);
    });
  });

  group('LineGrouper', () {
    Rect r(double l, double t, double w, double h) => Rect.fromLTWH(l, t, w, h);

    test('Striche auf gleicher Höhe bilden eine Zeile, links nach rechts', () {
      final boxes = [r(100, 100, 20, 30), r(10, 105, 20, 25), r(50, 98, 20, 32)];
      final g = LineGrouper.group(boxes, cell: 40);
      expect(g, [
        [1, 2, 0],
      ]);
    });

    test('Zwei Zeilen werden getrennt, oben zuerst', () {
      final boxes = [r(10, 200, 30, 30), r(10, 100, 30, 30), r(60, 205, 30, 25)];
      final g = LineGrouper.group(boxes, cell: 40);
      expect(g, [
        [1],
        [0, 2],
      ]);
    });

    test('Große Lücke trennt Spalten', () {
      final boxes = [r(10, 100, 30, 30), r(60, 100, 30, 30), r(600, 100, 30, 30)];
      final g = LineGrouper.group(boxes, cell: 40);
      expect(g, [
        [0, 1],
        [2],
      ]);
    });
  });
}
