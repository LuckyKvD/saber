import 'dart:math' as math;

/// Feder: Rechner für handgeschriebene Matheaufgaben – komplett auf dem Gerät.
///
/// Kann: + − · ÷ ^ Klammern, Wurzel (√), Dezimalzahlen (Komma/Punkt),
/// Gleichungen mit einer Unbekannten bis x² (inkl. Rechenweg).
/// Rechnet mit exakten Brüchen, nur Wurzeln aus Nicht-Quadratzahlen sind Näherungen.

class MathError implements Exception {
  MathError(this.message);
  final String message;
  @override
  String toString() => message;
}

class MathSolution {
  const MathSolution({
    required this.result,
    required this.steps,
    this.note,
    String? writeText,
  }) : writeText = writeText ?? result;

  /// Kurzes Ergebnis, z. B. `x = 5`.
  final String result;

  /// Rechenweg, je Eintrag eine Zeile.
  final List<String> steps;
  final String? note;

  /// Kurzform zum Hinschreiben hinter die Aufgabe, z. B. `8` oder `x = 5`.
  final String writeText;
}

abstract class MathSolver {
  /// Vereinheitlicht typische Schreib- und Erkennungsvarianten.
  static String normalize(String raw) {
    var s = raw.toLowerCase();
    s = s.replaceAll(RegExp(r'\s+'), '');
    s = s.replaceAll(RegExp('[−–—]'), '-');
    s = s.replaceAll('÷', '/').replaceAll(':', '/');
    s = s.replaceAll('×', '*').replaceAll('·', '*').replaceAll('•', '*');
    s = s.replaceAll('＝', '=');
    s = s.replaceAll('[', '(').replaceAll(']', ')');
    s = s.replaceAll('{', '(').replaceAll('}', ')');
    s = s.replaceAll('²', '^2').replaceAll('³', '^3');
    s = s.replaceAll('sqrt', '√').replaceAll('wurzel', '√');
    s = s.replaceAll(',', '.');
    // "3x4" (Ziffer x Ziffer) ist Malnehmen, nicht die Unbekannte.
    s = s.replaceAll(RegExp(r'(?<=[0-9])x(?=[0-9])'), '*');
    // Ein schlecht erkanntes Gleichheitszeichen kommt oft als - oder _ an;
    // am Ende der Aufgabe ist jedes Rechenzeichen ohnehin unvollständig.
    s = s.replaceFirst(RegExp(r'[=?_~≡≈+\-*/^]+$'), '');
    return s;
  }

  static String _pretty(String normalized) =>
      normalized.replaceAll('*', '·').replaceAll('/', '÷');

  static MathSolution solve(String raw) {
    final n = normalize(raw);
    if (n.isEmpty) throw MathError('Keine Aufgabe eingegeben.');
    if (n.length > 200) throw MathError('Die Aufgabe ist zu lang.');
    final sides = n.split('=');
    if (sides.length > 2) throw MathError('Mehr als ein Gleichheitszeichen.');
    if (sides.length == 1 || sides[1].isEmpty || sides[1] == '?') {
      if (sides[0].isEmpty) throw MathError('Keine Aufgabe eingegeben.');
      return _expression(sides[0]);
    }
    if (sides[0].isEmpty) {
      throw MathError('Links vom Gleichheitszeichen fehlt etwas.');
    }
    return _equation(sides[0], sides[1]);
  }

  static _Poly _parse(String s, _Ctx ctx) {
    final toks = _tokenize(s);
    if (toks.isEmpty) throw MathError('Die Aufgabe ist unvollständig.');
    final parser = _Parser(toks, ctx);
    final result = parser.expr();
    if (parser.pos != toks.length) {
      throw MathError('Unerwartetes Zeichen "${toks[parser.pos].text}".');
    }
    return result;
  }

  static MathSolution _expression(String s) {
    final ctx = _Ctx();
    final p = _parse(s, ctx);
    final note = ctx.approx
        ? 'Wurzeln aus Nicht-Quadratzahlen sind Näherungswerte.'
        : null;
    if (p.isConstant) {
      final v = p.c[0].full();
      return MathSolution(
        result: v,
        steps: ['Aufgabe: ${_pretty(s)}', 'Ergebnis: $v'],
        note: note,
        writeText: p.c[0].short(),
      );
    }
    final v = ctx.variable ?? 'x';
    final text = p.toText(v);
    return MathSolution(
      result: text,
      steps: ['Aufgabe: ${_pretty(s)}', 'Zusammengefasst: $text'],
      note: note,
    );
  }

  static MathSolution _equation(String left, String right) {
    final ctx = _Ctx();
    final pL = _parse(left, ctx);
    final pR = _parse(right, ctx);
    final v = ctx.variable ?? 'x';
    final diff = pL - pR;
    final head = 'Aufgabe: ${_pretty(left)} = ${_pretty(right)}';
    final note = ctx.approx
        ? 'Wurzeln aus Nicht-Quadratzahlen sind Näherungswerte.'
        : null;

    if (ctx.variable == null) {
      final l = pL.c[0];
      final r = pR.c[0];
      return MathSolution(
        result: diff.c[0].isZero
            ? 'Stimmt: beide Seiten sind ${l.plain()}'
            : 'Stimmt nicht: links ${l.plain()}, rechts ${r.plain()}',
        steps: [head],
        note: note,
      );
    }

    if (diff.degree == 0) {
      return MathSolution(
        result: diff.c[0].isZero
            ? 'Die Gleichung ist immer wahr.'
            : 'Die Gleichung hat keine Lösung.',
        steps: [head, 'Zusammengefasst: ${pL.toText(v)} = ${pR.toText(v)}'],
        note: note,
      );
    }

    if (diff.degree == 1) {
      final a = diff.coef(1);
      final b = diff.coef(0);
      final rightSide = -b;
      final x = rightSide / a;
      final steps = <String>[
        head,
        'Beide Seiten zusammenfassen: ${pL.toText(v)} = ${pR.toText(v)}',
        'x-Terme nach links, Zahlen nach rechts: '
            '${_Poly([_Frac.zero, a]).toText(v)} = ${rightSide.plain()}',
        if (!a.isOne) 'Durch ${a.plain()} teilen: $v = ${x.plain()}',
      ];
      if (!ctx.approx) {
        steps.add(
          'Probe: links ${pL.eval(x).plain()}, rechts ${pR.eval(x).plain()}',
        );
      }
      return MathSolution(
        result: '$v = ${x.full()}',
        steps: steps,
        note: note,
      );
    }

    if (diff.degree == 2) {
      final a = diff.coef(2);
      final b = diff.coef(1);
      final c = diff.coef(0);
      final disc = b * b - _Frac.fromInt(4) * a * c;
      final twoA = _Frac.fromInt(2) * a;
      final steps = <String>[
        head,
        'Normalform: ${diff.toText(v)} = 0',
        'a = ${a.plain()}, b = ${b.plain()}, c = ${c.plain()}',
        'Diskriminante D = b² - 4·a·c = ${disc.plain()}',
      ];
      if (disc.isNegative) {
        steps.add('D ist negativ, also gibt es keine reelle Lösung.');
        return MathSolution(
          result: 'Keine reelle Lösung',
          steps: steps,
          note: note,
        );
      }
      if (disc.isZero) {
        final x = (-b) / twoA;
        steps.add('D = 0: eine Lösung, $v = -b / 2a = ${x.plain()}');
        return MathSolution(
          result: '$v = ${x.full()}',
          steps: steps,
          note: note,
        );
      }
      final s = disc.sqrtExact();
      if (s != null) {
        final x1 = ((-b) - s) / twoA;
        final x2 = ((-b) + s) / twoA;
        final lo = x1.toDouble() <= x2.toDouble() ? x1 : x2;
        final hi = identical(lo, x1) ? x2 : x1;
        steps.add(
          '$v = (-b ± √D) / 2a = (${(-b).plain()} ± ${s.plain()}) / ${twoA.plain()}',
        );
        return MathSolution(
          result: '$v = ${lo.full()} oder $v = ${hi.full()}',
          steps: steps,
          note: note,
        );
      }
      final sd = math.sqrt(disc.toDouble());
      final den = twoA.toDouble();
      final r1 = (-b.toDouble() - sd) / den;
      final r2 = (-b.toDouble() + sd) / den;
      final lo = math.min(r1, r2);
      final hi = math.max(r1, r2);
      steps.add(
        '$v = (-b ± √D) / 2a = (${(-b).plain()} ± √${disc.plain()}) / ${twoA.plain()}',
      );
      return MathSolution(
        result: '$v ≈ ${_dec(lo)} oder $v ≈ ${_dec(hi)}',
        steps: steps,
        note: note,
      );
    }

    throw MathError('Gleichungen über x² werden noch nicht gelöst.');
  }

  static String _dec(double v) {
    var s = v.toStringAsFixed(6);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    }
    if (s == '-0') s = '0';
    return s.replaceAll('.', ',');
  }
}

// ---------------------------------------------------------------- Bruchzahl

BigInt _isqrt(BigInt x) {
  if (x < BigInt.two) return x;
  if (x.bitLength > 1000) throw MathError('Die Zahl ist zu groß.');
  var r = BigInt.from(math.sqrt(x.toDouble()).floor());
  while (r * r > x) {
    r -= BigInt.one;
  }
  while ((r + BigInt.one) * (r + BigInt.one) <= x) {
    r += BigInt.one;
  }
  return r;
}

class _Frac {
  _Frac._(this.n, this.d);

  factory _Frac(BigInt n, [BigInt? d]) {
    var num = n;
    var den = d ?? BigInt.one;
    if (den == BigInt.zero) throw MathError('Division durch Null.');
    if (den.isNegative) {
      num = -num;
      den = -den;
    }
    final g = num.gcd(den);
    if (g > BigInt.one) {
      num = num ~/ g;
      den = den ~/ g;
    }
    return _Frac._(num, den);
  }

  factory _Frac.fromInt(int v) => _Frac(BigInt.from(v));

  factory _Frac.fromDouble(double v) =>
      _Frac(BigInt.from((v * 1e9).round()), BigInt.from(1000000000));

  /// Zahl wie `2.5` oder `7`.
  factory _Frac.parse(String s) {
    final parts = s.split('.');
    final frac = parts.length > 1 ? parts[1] : '';
    final digits = (parts[0].isEmpty ? '0' : parts[0]) + frac;
    return _Frac(BigInt.parse(digits), BigInt.from(10).pow(frac.length));
  }

  static final zero = _Frac._(BigInt.zero, BigInt.one);
  static final one = _Frac._(BigInt.one, BigInt.one);

  final BigInt n;
  final BigInt d;

  bool get isZero => n == BigInt.zero;
  bool get isOne => n == BigInt.one && d == BigInt.one;
  bool get isInt => d == BigInt.one;
  bool get isNegative => n.isNegative;

  _Frac abs() => _Frac._(n.abs(), d);

  _Frac operator +(_Frac o) => _Frac(n * o.d + o.n * d, d * o.d);
  _Frac operator -(_Frac o) => _Frac(n * o.d - o.n * d, d * o.d);
  _Frac operator *(_Frac o) => _Frac(n * o.n, d * o.d);
  _Frac operator /(_Frac o) {
    if (o.isZero) throw MathError('Division durch Null.');
    return _Frac(n * o.d, d * o.n);
  }

  _Frac operator -() => _Frac._(-n, d);

  double toDouble() => n.toDouble() / d.toDouble();

  _Frac powInt(int e) {
    if (e >= 0) return _Frac(n.pow(e), d.pow(e));
    if (isZero) throw MathError('Division durch Null.');
    return _Frac(d.pow(-e), n.pow(-e));
  }

  _Frac? sqrtExact() {
    if (n.isNegative) return null;
    final a = _isqrt(n);
    final b = _isqrt(d);
    if (a * a == n && b * b == d) return _Frac(a, b);
    return null;
  }

  String plain() => isInt ? n.toString() : '$n/$d';

  bool _terminates(int digits) =>
      (n.abs() * BigInt.from(10).pow(digits)) % d == BigInt.zero;

  String _decimal(int digits) {
    final scale = BigInt.from(10).pow(digits);
    final scaled = (n.abs() * scale * BigInt.two + d) ~/ (d * BigInt.two);
    final s = scaled.toString().padLeft(digits + 1, '0');
    final intPart = s.substring(0, s.length - digits);
    final frac = s.substring(s.length - digits).replaceFirst(RegExp(r'0+$'), '');
    final sign = n.isNegative && scaled != BigInt.zero ? '-' : '';
    return '$sign$intPart${frac.isEmpty ? '' : ',$frac'}';
  }

  /// Kurzform zum Hinschreiben: Ganzzahl, Dezimalzahl oder Näherung.
  String short() {
    if (isInt) return n.toString();
    return _terminates(6) ? _decimal(6) : '≈ ${_decimal(4)}';
  }

  /// Ganzzahl oder Bruch mit Dezimalwert.
  String full() {
    if (isInt) return n.toString();
    return _terminates(6)
        ? '$n/$d = ${_decimal(6)}'
        : '$n/$d ≈ ${_decimal(6)}';
  }
}

// ---------------------------------------------------------------- Polynom

String _sup(int k) => switch (k) {
  2 => '²',
  3 => '³',
  _ => '^$k',
};

class _Poly {
  _Poly(List<_Frac> coeffs) : c = _trim(coeffs);

  factory _Poly.constant(_Frac f) => _Poly([f]);

  final List<_Frac> c;

  static List<_Frac> _trim(List<_Frac> l) {
    final r = [...l];
    while (r.length > 1 && r.last.isZero) {
      r.removeLast();
    }
    if (r.isEmpty) r.add(_Frac.zero);
    return r;
  }

  int get degree => c.length - 1;
  bool get isConstant => degree == 0;
  _Frac coef(int k) => k < c.length ? c[k] : _Frac.zero;

  _Poly operator +(_Poly o) {
    final len = math.max(c.length, o.c.length);
    return _Poly([for (var i = 0; i < len; i++) coef(i) + o.coef(i)]);
  }

  _Poly operator -(_Poly o) {
    final len = math.max(c.length, o.c.length);
    return _Poly([for (var i = 0; i < len; i++) coef(i) - o.coef(i)]);
  }

  _Poly operator -() => _Poly([for (final x in c) -x]);

  _Poly operator *(_Poly o) {
    if (c.length + o.c.length - 1 > 9) {
      throw MathError('Der Ausdruck ist zu komplex.');
    }
    final r = List<_Frac>.filled(c.length + o.c.length - 1, _Frac.zero);
    for (var i = 0; i < c.length; i++) {
      for (var j = 0; j < o.c.length; j++) {
        r[i + j] = r[i + j] + c[i] * o.c[j];
      }
    }
    return _Poly(r);
  }

  _Poly scale(_Frac f) => _Poly([for (final x in c) x * f]);

  _Frac eval(_Frac x) {
    var r = _Frac.zero;
    for (var k = c.length - 1; k >= 0; k--) {
      r = r * x + c[k];
    }
    return r;
  }

  String toText(String v) {
    final sb = StringBuffer();
    var first = true;
    for (var k = degree; k >= 0; k--) {
      final co = coef(k);
      if (co.isZero && !(degree == 0 && k == 0)) continue;
      final neg = co.isNegative;
      final a = co.abs();
      final String body;
      if (k == 0) {
        body = a.plain();
      } else {
        final varPart = k == 1 ? v : '$v${_sup(k)}';
        if (a.isOne) {
          body = varPart;
        } else if (a.isInt) {
          body = '${a.plain()}$varPart';
        } else {
          body = '(${a.plain()})·$varPart';
        }
      }
      if (first) {
        sb.write(neg ? '-' : '');
      } else {
        sb.write(neg ? ' - ' : ' + ');
      }
      sb.write(body);
      first = false;
    }
    return sb.toString();
  }
}

// ---------------------------------------------------------------- Parser

class _Ctx {
  String? variable;
  bool approx = false;
}

class _Tok {
  const _Tok(this.kind, this.text, [this.value]);

  /// `n` Zahl, `v` Unbekannte, `o` Operator.
  final String kind;
  final String text;
  final _Frac? value;
}

List<_Tok> _tokenize(String s) {
  final out = <_Tok>[];
  final isNum = RegExp(r'[0-9.]');
  final isVar = RegExp(r'[a-z]');
  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (isNum.hasMatch(ch)) {
      var j = i;
      var dots = 0;
      while (j < s.length && isNum.hasMatch(s[j])) {
        if (s[j] == '.') dots++;
        j++;
      }
      final txt = s.substring(i, j);
      if (dots > 1 || txt == '.') {
        throw MathError('Ungültige Zahl "$txt".');
      }
      out.add(_Tok('n', txt, _Frac.parse(txt)));
      i = j;
    } else if ('+-*/^()√'.contains(ch)) {
      out.add(_Tok('o', ch));
      i++;
    } else if (isVar.hasMatch(ch)) {
      out.add(_Tok('v', ch));
      i++;
    } else {
      throw MathError('Unbekanntes Zeichen "$ch".');
    }
  }
  return out;
}

class _Parser {
  _Parser(this.toks, this.ctx);

  final List<_Tok> toks;
  final _Ctx ctx;
  int pos = 0;

  bool _is(String op) {
    if (pos >= toks.length) return false;
    final t = toks[pos];
    return t.kind == 'o' && t.text == op;
  }

  bool get _startsFactor {
    if (pos >= toks.length) return false;
    final t = toks[pos];
    return t.kind == 'v' || (t.kind == 'o' && (t.text == '(' || t.text == '√'));
  }

  _Poly expr() {
    var v = _term();
    while (_is('+') || _is('-')) {
      final plus = toks[pos++].text == '+';
      final r = _term();
      v = plus ? v + r : v - r;
    }
    return v;
  }

  _Poly _term() {
    var v = _unary();
    while (true) {
      if (_is('*')) {
        pos++;
        v = v * _unary();
      } else if (_is('/')) {
        pos++;
        final q = _unary();
        if (!q.isConstant) {
          throw MathError('Teilen durch einen Ausdruck mit x geht noch nicht.');
        }
        v = v.scale(_Frac.one / q.c[0]);
      } else if (_startsFactor) {
        v = v * _power();
      } else {
        return v;
      }
    }
  }

  _Poly _unary() {
    if (_is('-')) {
      pos++;
      return -_unary();
    }
    if (_is('+')) {
      pos++;
      return _unary();
    }
    return _power();
  }

  _Poly _power() {
    final base = _atom();
    if (!_is('^')) return base;
    pos++;
    var neg = false;
    if (_is('-')) {
      neg = true;
      pos++;
    } else if (_is('+')) {
      pos++;
    }
    final ex = _power();
    if (!ex.isConstant || !ex.c[0].isInt) {
      throw MathError('Hochzahlen müssen ganze Zahlen sein.');
    }
    if (ex.c[0].n.abs() > BigInt.from(64)) {
      throw MathError('Die Hochzahl ist zu groß.');
    }
    var e = ex.c[0].n.toInt();
    if (neg) e = -e;
    return _pow(base, e);
  }

  _Poly _pow(_Poly base, int e) {
    if (e == 0) return _Poly.constant(_Frac.one);
    if (base.isConstant) return _Poly.constant(base.c[0].powInt(e));
    if (e < 0) {
      throw MathError('Negative Hochzahl bei x geht noch nicht.');
    }
    var r = base;
    for (var i = 1; i < e; i++) {
      r = r * base;
    }
    return r;
  }

  _Poly _atom() {
    if (pos >= toks.length) throw MathError('Die Aufgabe ist unvollständig.');
    final t = toks[pos++];
    if (t.kind == 'n') return _Poly.constant(t.value!);
    if (t.kind == 'v') {
      final v = ctx.variable;
      if (v != null && v != t.text) {
        throw MathError(
          'Nur eine Unbekannte erlaubt (gefunden: $v und ${t.text}).',
        );
      }
      ctx.variable = t.text;
      return _Poly([_Frac.zero, _Frac.one]);
    }
    if (t.text == '(') {
      final e = expr();
      if (!_is(')')) throw MathError('Klammer nicht geschlossen.');
      pos++;
      return e;
    }
    if (t.text == '√') {
      return _sqrt(_atom());
    }
    throw MathError('Unerwartetes Zeichen "${t.text}".');
  }

  _Poly _sqrt(_Poly a) {
    if (!a.isConstant) {
      throw MathError('Wurzel aus einem Ausdruck mit x geht noch nicht.');
    }
    final x = a.c[0];
    if (x.isNegative) throw MathError('Wurzel aus einer negativen Zahl.');
    final exact = x.sqrtExact();
    if (exact != null) return _Poly.constant(exact);
    ctx.approx = true;
    return _Poly.constant(_Frac.fromDouble(math.sqrt(x.toDouble())));
  }
}
