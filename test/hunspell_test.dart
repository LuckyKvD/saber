import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/spell/hunspell.dart';

void main() {
  late Hunspell hs;
  setUpAll(() {
    hs = Hunspell.parse(
      File('assets/dict/de_DE_frami.aff').readAsStringSync(),
      File('assets/dict/de_DE_frami.dic').readAsStringSync(),
    );
  });

  test('richtige Wörter und Komposita', () {
    for (final w in [
      'Haus', 'Häuser', 'Der', 'ist', 'werden', 'gehen', 'gegangen', 'Kapitän',
      'Hauptbahnhof', 'Hauptbahnhofsvorplatz', 'Donaudampfschifffahrtskapitän',
      'Arbeitszeitgesetz', 'Rechtschreibprüfung', 'Textverarbeitung', 'Notizbuch',
      'Genossenschaftsbank', 'Bereichsleiter', 'Verträge', 'unglaublich',
    ]) {
      expect(hs.check(w), isTrue, reason: w);
    }
  });

  test('falsche Wörter', () {
    for (final w in ['Tehst', 'Fehlren', 'geshen', 'Qwertzuiop', 'Hauptbahnhofsvorplatzx']) {
      expect(hs.check(w), isFalse, reason: w);
    }
  });

  test('Vorschläge', () {
    expect(hs.suggest('Tehst'), contains('Test'));
    expect(hs.suggest('geshen'), contains('gesehen'));
    expect(hs.suggest('Fehlren'), contains('Fehlern'));
  });
}
