import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:saber/data/tables/table_builder.dart';

enum NoteTemplate {
  meeting('Besprechung'),
  jourFixe('Jour fixe');

  const NoteTemplate(this.label);
  final String label;

  static NoteTemplate? parse(String? name) {
    for (final t in values) {
      if (t.name == name) return t;
    }
    return null;
  }
}

class TemplateText {
  const TemplateText(this.text, this.topLeft, this.fontSize);

  final String text;
  final Offset topLeft;
  final double fontSize;
}

/// Inhalt einer Vorlage: Beschriftungen (werden als Handschrift-Bilder gesetzt),
/// Schreiblinien (freie Striche) und Tabellenlinien.
class TemplateContent {
  final texts = <TemplateText>[];
  final underlines = <List<Offset>>[];
  final tableLines = <TableLine>[];

  /// Abschnitte, die nicht mehr auf die Seite gepasst haben.
  var skipped = 0;

  /// Unterkante des gesamten Inhalts (für die Suche nach freiem Platz).
  double get maxY {
    var m = 0.0;
    for (final t in texts) {
      m = math.max(m, t.topLeft.dy + t.fontSize * 1.5);
    }
    for (final l in underlines) {
      for (final p in l) {
        m = math.max(m, p.dy);
      }
    }
    for (final l in tableLines) {
      for (final p in l.points) {
        m = math.max(m, p.dy);
      }
    }
    return m;
  }
}

abstract class NoteTemplates {
  /// Mittlere Zeichenbreite der Handschrift-Schrift (Anteil der Schriftgröße).
  static const _charWidth = 0.52;

  static String formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.'
      '${d.month.toString().padLeft(2, '0')}.${d.year}';

  /// Baut die Vorlage für eine Seite der Größe [page] mit Kästchengröße [cell].
  static TemplateContent build(
    NoteTemplate template, {
    required Size page,
    required double cell,
    required DateTime date,
    required math.Random rng,
    double? top,
  }) {
    final c = cell;
    final m = 2 * c;
    final left = m;
    final right = page.width - m;
    final bottom = page.height - 2 * c;
    final out = TemplateContent();
    var y = top ?? m;

    double textWidth(String s, double fs) => s.length * fs * _charWidth;

    void line(double x1, double x2, double yy) {
      out.underlines.add(
        TableBuilder.wobblyLine(Offset(x1, yy), Offset(x2, yy), rng),
      );
    }

    void title(String text) {
      out.texts.add(TemplateText(text, Offset(left, y), 1.6 * c));
      final d = formatDate(date);
      final fs = 0.9 * c;
      out.texts.add(
        TemplateText(d, Offset(right - textWidth(d, fs), y + 0.7 * c), fs),
      );
      line(left, right, y + 2.0 * c);
      y += 2.8 * c;
    }

    void field(String label, {int extraLines = 0}) {
      if (y + 1.5 * c > bottom) {
        out.skipped++;
        return;
      }
      final fs = 0.9 * c;
      out.texts.add(TemplateText(label, Offset(left, y), fs));
      final start = left + textWidth(label, fs) + 0.4 * c;
      line(start, right, y + 1.1 * c);
      for (var i = 1; i <= extraLines; i++) {
        line(left, right, y + 1.1 * c + i * 1.5 * c);
      }
      y += (1.9 + extraLines * 1.5) * c;
    }

    void section(String label, int lines) {
      if (y + (1.8 + lines * 1.5) * c > bottom) {
        out.skipped++;
        return;
      }
      out.texts.add(TemplateText(label, Offset(left, y), 1.1 * c));
      y += 1.9 * c;
      for (var i = 0; i < lines; i++) {
        line(left, right, y + 1.1 * c);
        y += 1.5 * c;
      }
      y += 0.6 * c;
    }

    void tableSection(String label, List<String> headers, List<double> shares, int rows) {
      final rowH = 1.5 * c;
      final needed = 1.8 * c + (rows + 1) * rowH;
      if (y + needed > bottom) {
        out.skipped++;
        return;
      }
      out.texts.add(TemplateText(label, Offset(left, y), 1.1 * c));
      y += 1.9 * c;
      final width = right - left;
      final xs = <double>[left];
      for (final s in shares) {
        xs.add(xs.last + width * s);
      }
      final ys = [for (var r = 0; r <= rows + 1; r++) y + r * rowH];
      for (final yy in ys) {
        out.tableLines.add(
          TableLine(
            TableBuilder.horizontal,
            TableBuilder.wobblyLine(Offset(xs.first, yy), Offset(xs.last, yy), rng),
          ),
        );
      }
      for (final x in xs) {
        out.tableLines.add(
          TableLine(
            TableBuilder.vertical,
            TableBuilder.wobblyLine(Offset(x, ys.first), Offset(x, ys.last), rng),
          ),
        );
      }
      for (var i = 0; i < headers.length; i++) {
        out.texts.add(
          TemplateText(headers[i], Offset(xs[i] + 0.3 * c, y + 0.2 * c), 0.85 * c),
        );
      }
      y += (rows + 1) * rowH + 0.8 * c;
    }

    switch (template) {
      case NoteTemplate.meeting:
        title('Besprechung');
        field('Thema:');
        field('Teilnehmer:', extraLines: 1);
        section('Tagesordnung', 3);
        section('Beschlüsse', 2);
        tableSection('Aufgaben', ['Wer', 'Was', 'Bis wann'], [0.22, 0.5, 0.28], 4);
        section('Notizen', 3);
      case NoteTemplate.jourFixe:
        title('Jour fixe');
        field('Teilnehmer:', extraLines: 1);
        tableSection(
          'Letzte Aufgaben',
          ['Was', 'Wer', 'Status'],
          [0.5, 0.22, 0.28],
          3,
        );
        section('Neues', 4);
        section('Offenes / Nächste Schritte', 3);
    }
    return out;
  }
}
