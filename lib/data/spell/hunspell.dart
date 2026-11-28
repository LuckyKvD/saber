/// Schlanker Hunspell-Prüfer (Wortprüfung inkl. Affixen und Komposita).
///
/// Wörterbuch: LibreOffice „de_DE_frami“ (igerman98), GPL-2.0 oder GPL-3.0.
/// Unterstützt: PFX/SFX mit Bedingung, Strip, Folgeflags, NEEDAFFIX,
/// ONLYINCOMPOUND, FORBIDDENWORD, COMPOUNDBEGIN/MIDDLE/END, COMPOUNDPERMITFLAG,
/// COMPOUNDMIN. Nicht unterstützt: CIRCUMFIX (Bindestrichformen werden über
/// das Zerlegen an Bindestrichen abgedeckt), REP/MAP, Mehrwort-Einträge.
library;

class _Rule {
  _Rule(this.flag, this.strip, this.app, this.cont, this.rx);
  final String flag, strip, app, cont;
  final RegExp rx;
}

class _Group {
  _Group(this.cross);
  final bool cross;
  final rules = <_Rule>[];
}

class _Hit {
  _Hit(this.entry, this.pfx, this.sfx, this.pr, this.sr);
  final String entry, pfx, sfx;
  final _Rule? pr, sr;
  String get conts => (pr?.cont ?? '') + (sr?.cont ?? '');
  bool get affixed => pfx.isNotEmpty || sfx.isNotEmpty;
}

class Hunspell {
  Hunspell.parse(String aff, String dic) {
    _parseAff(aff);
    _parseDic(dic);
    _finish();
  }

  /// Wie [Hunspell.parse], gibt aber dem UI-Thread zwischendurch Luft.
  static Future<Hunspell> parseAsync(String aff, String dic) async {
    final h = Hunspell._empty();
    h._parseAff(aff);
    final lines = dic.split('\n');
    for (var i = 1; i < lines.length; i++) {
      h._addDicLine(lines[i]);
      if (i % 25000 == 0) await Future<void>.delayed(Duration.zero);
    }
    h._finish();
    return h;
  }

  Hunspell._empty();

  final _sfx = <String, _Group>{};
  final _pfx = <String, _Group>{};
  final _opt = <String, String>{};
  final _d = <String, List<String>>{};
  final _sfxByApp = <String, List<_Rule>>{};
  final _pfxByApp = <String, List<_Rule>>{};
  int _maxSl = 0, _maxPl = 0, _min = 3;
  String _need = '', _only = '', _forb = '', _cb = '', _cm = '', _ce = '';
  String _permit = '', _circ = '';

  int get wordCount => _d.length;

  void _parseAff(String aff) {
    for (var line in aff.split('\n')) {
      final hash = line.indexOf('#');
      if (hash >= 0) line = line.substring(0, hash);
      line = line.trim();
      if (line.isEmpty) continue;
      final p = line.split(RegExp(r'\s+'));
      final kind = p[0];
      if (kind == 'SFX' || kind == 'PFX') {
        final tbl = kind == 'SFX' ? _sfx : _pfx;
        if (p.length == 4 && (p[2] == 'Y' || p[2] == 'N') && int.tryParse(p[3]) != null) {
          tbl[p[1]] = _Group(p[2] == 'Y');
        } else if (p.length >= 4 && tbl[p[1]] != null) {
          var strip = p[2];
          var app = p[3];
          final cond = p.length > 4 ? p[4] : '.';
          var cont = '';
          final slash = app.indexOf('/');
          if (slash >= 0) {
            cont = app.substring(slash + 1);
            app = app.substring(0, slash);
          }
          if (strip == '0') strip = '';
          if (app == '0') app = '';
          RegExp rx;
          try {
            rx = RegExp(kind == 'SFX' ? '(?:$cond)\$' : '^(?:$cond)');
          } catch (_) {
            continue;
          }
          tbl[p[1]]!.rules.add(_Rule(p[1], strip, app, cont, rx));
        }
      } else if (p.length >= 2 && RegExp(r'^[A-Z]+$').hasMatch(kind) && kind != 'TRY' && kind != 'MAP' && kind != 'REP' && kind != 'KEY' && kind != 'SET') {
        _opt[kind] = p[1];
      }
    }
  }

  void _parseDic(String dic) {
    final lines = dic.split('\n');
    for (var i = 1; i < lines.length; i++) {
      _addDicLine(lines[i]);
    }
  }

  void _addDicLine(String ln) {
    if (ln.isEmpty || ln.startsWith('#') || ln.startsWith('\t')) return;
    final tab = ln.indexOf('\t');
    if (tab >= 0) ln = ln.substring(0, tab);
    ln = ln.trimRight();
    if (ln.isEmpty) return;
    final slash = ln.indexOf('/');
    final w = slash >= 0 ? ln.substring(0, slash) : ln;
    final f = slash >= 0 ? ln.substring(slash + 1) : '';
    (_d[w] ??= <String>[]).add(f);
  }

  void _finish() {
    _need = _opt['NEEDAFFIX'] ?? '';
    _only = _opt['ONLYINCOMPOUND'] ?? '';
    _forb = _opt['FORBIDDENWORD'] ?? '';
    _cb = _opt['COMPOUNDBEGIN'] ?? '';
    _cm = _opt['COMPOUNDMIDDLE'] ?? '';
    _ce = _opt['COMPOUNDEND'] ?? '';
    _permit = _opt['COMPOUNDPERMITFLAG'] ?? '';
    _circ = _opt['CIRCUMFIX'] ?? '';
    _min = int.tryParse(_opt['COMPOUNDMIN'] ?? '') ?? 3;
    for (final g in _sfx.values) {
      for (final r in g.rules) {
        (_sfxByApp[r.app] ??= []).add(r);
        if (r.app.length > _maxSl) _maxSl = r.app.length;
      }
    }
    for (final g in _pfx.values) {
      for (final r in g.rules) {
        (_pfxByApp[r.app] ??= []).add(r);
        if (r.app.length > _maxPl) _maxPl = r.app.length;
      }
    }
  }

  bool _has(String flags, String f) => f.isNotEmpty && flags.contains(f);

  List<_Hit> _analyses(String p) {
    final out = <_Hit>[];
    for (final e in _d[p] ?? const <String>[]) {
      out.add(_Hit(e, '', '', null, null));
    }
    final maxK = p.length < _maxSl ? p.length : _maxSl;
    for (var k = 0; k <= maxK; k++) {
      final app = p.substring(p.length - k);
      for (final r in _sfxByApp[app] ?? const <_Rule>[]) {
        final stem = p.substring(0, p.length - k) + r.strip;
        if (!r.rx.hasMatch(stem)) continue;
        for (final e in _d[stem] ?? const <String>[]) {
          if (e.contains(r.flag)) out.add(_Hit(e, '', r.flag, null, r));
        }
        if (_sfx[r.flag]!.cross) {
          final maxKk = stem.length < _maxPl ? stem.length : _maxPl;
          for (var kk = 0; kk <= maxKk; kk++) {
            final papp = stem.substring(0, kk);
            for (final pr in _pfxByApp[papp] ?? const <_Rule>[]) {
              if (!_pfx[pr.flag]!.cross) continue;
              final st2 = pr.strip + stem.substring(kk);
              if (!pr.rx.hasMatch(st2)) continue;
              for (final e2 in _d[st2] ?? const <String>[]) {
                if (e2.contains(pr.flag) && e2.contains(r.flag)) {
                  out.add(_Hit(e2, pr.flag, r.flag, pr, r));
                }
              }
            }
          }
        }
      }
    }
    final maxP = p.length < _maxPl ? p.length : _maxPl;
    for (var kk = 1; kk <= maxP; kk++) {
      final papp = p.substring(0, kk);
      for (final pr in _pfxByApp[papp] ?? const <_Rule>[]) {
        final st2 = pr.strip + p.substring(kk);
        if (!pr.rx.hasMatch(st2)) continue;
        for (final e2 in _d[st2] ?? const <String>[]) {
          if (e2.contains(pr.flag)) out.add(_Hit(e2, pr.flag, '', pr, null));
        }
      }
    }
    return out;
  }

  bool _okWhole(String p) {
    final hits = _analyses(p);
    for (final h in hits) {
      if (_has(h.entry, _forb)) return false;
    }
    for (final h in hits) {
      final conts = h.conts;
      if (_has(conts, _circ)) continue;
      if (_has(h.entry, _only) || _has(conts, _only)) continue;
      if (_has(h.entry, _need) && !h.affixed) continue;
      return true;
    }
    return false;
  }

  bool _partOk(String p, int pos) {
    // pos: 0 Anfang, 1 Mitte, 2 Ende
    final need = pos == 0 ? _cb : (pos == 1 ? _cm : _ce);
    for (final h in _analyses(p)) {
      final conts = h.conts;
      if (_has(h.entry, _forb)) continue;
      if (_has(conts, _circ)) continue;
      if (!(_has(h.entry, need) || _has(conts, need))) continue;
      if (h.sr != null && pos != 2 && !_has(conts, _permit)) continue;
      if (h.pr != null && pos != 0 && !_has(conts, _permit)) continue;
      if (_has(h.entry, _need) && !h.affixed) continue;
      return true;
    }
    return false;
  }

  bool _compound(String w) {
    final n = w.length;
    final memo = <int, bool>{};
    bool go(int i, int cnt) {
      final key = i * 2 + cnt;
      final cached = memo[key];
      if (cached != null) return cached;
      var result = false;
      for (var j = i + _min; j <= n; j++) {
        if (j < n && n - j < _min) continue;
        if (i == 0 && j == n) continue;
        final pos = i == 0 ? 0 : (j == n ? 2 : 1);
        if (_partOk(w.substring(i, j), pos)) {
          if (j == n) {
            result = cnt + 1 >= 2;
          } else if (go(j, cnt + 1 > 1 ? 1 : cnt + 1)) {
            result = true;
          }
          if (result) break;
        }
      }
      return memo[key] = result;
    }

    return go(0, 0);
  }

  bool _checkWord(String w) => _okWhole(w) || _compound(w);

  static bool _isUpper(String s) => s != s.toLowerCase() && s == s.toUpperCase();

  /// `true`, wenn [word] korrekt geschrieben ist (ein Wort ohne Bindestrich).
  bool check(String word) {
    if (word.isEmpty) return true;
    if (RegExp(r'\d').hasMatch(word)) return true;
    final cands = <String>[word];
    final first = word.substring(0, 1);
    final rest = word.substring(1);
    if (_isUpper(first) && rest.isNotEmpty && rest == rest.toLowerCase() && rest != rest.toUpperCase()) {
      cands.add(first.toLowerCase() + rest);
    }
    if (word.length > 1 && _isUpper(word)) {
      cands.add(first + rest.toLowerCase());
      cands.add(word.toLowerCase());
    }
    return cands.any(_checkWord);
  }

  static const _alphabet = 'esijanrtolcdugmphbyfvkwqxzäüößESIJANRTOLCDUGMPHBYFVKWQXZÄÜÖ';

  /// Vorschläge mit genau einer Änderung (Löschen, Vertauschen, Ersetzen, Einfügen).
  List<String> suggest(String word, {int max = 6}) {
    final found = <String>{};
    void tryIt(String c) {
      if (c != word && c.length > 1 && !found.contains(c) && check(c)) found.add(c);
    }

    for (var i = 0; i <= word.length; i++) {
      if (i < word.length) tryIt(word.substring(0, i) + word.substring(i + 1));
      if (i < word.length - 1) {
        tryIt(word.substring(0, i) + word[i + 1] + word[i] + word.substring(i + 2));
      }
      for (final c in _alphabet.split('')) {
        if (i < word.length) tryIt(word.substring(0, i) + c + word.substring(i + 1));
        tryIt(word.substring(0, i) + c + word.substring(i));
      }
      if (found.length >= max * 3) break;
    }
    final list = found.toList()
      ..sort((a, b) => (a.length - word.length).abs().compareTo((b.length - word.length).abs()));
    return list.take(max).toList();
  }
}
