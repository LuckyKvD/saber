import 'package:flutter/services.dart' show rootBundle;
import 'package:saber/data/spell/hunspell.dart';

/// Ein gefundener Rechtschreibfehler.
class SpellIssue {
  const SpellIssue(this.start, this.length, this.word);
  final int start, length;
  final String word;
}

/// Rechtschreibprüfung mit eigenem Hunspell-Wörterbuch (Deutsch, de_DE_frami).
abstract final class SpellCheck {
  static Hunspell? _hs;
  static Future<Hunspell>? _loading;

  static Future<Hunspell> get engine => _loading ??= _load();

  static Future<Hunspell> _load() async {
    final aff = await rootBundle.loadString('assets/dict/de_DE_frami.aff');
    final dic = await rootBundle.loadString('assets/dict/de_DE_frami.dic');
    return _hs = await Hunspell.parseAsync(aff, dic);
  }

  static final _token = RegExp(r'\p{L}+(?:[-’\x27]\p{L}+)*', unicode: true);

  /// Fehler im [text]; Teile mit Bindestrich werden einzeln geprüft.
  static Future<List<SpellIssue>> check(String text, {Set<String> ignore = const {}}) async {
    final hs = await engine;
    final out = <SpellIssue>[];
    for (final m in _token.allMatches(text)) {
      final w = m.group(0)!;
      var offset = m.start;
      for (final part in w.split(RegExp(r'[-’\x27]'))) {
        final len = part.length;
        if (len > 1 && !_acronym(part) && !ignore.contains(part) && !hs.check(part)) {
          out.add(SpellIssue(offset, len, part));
        }
        offset += len + 1;
      }
    }
    return out;
  }

  static bool _acronym(String w) => w.length <= 5 && w == w.toUpperCase() && w != w.toLowerCase();

  static Future<List<String>> suggest(String word) async => (await engine).suggest(word);
}
