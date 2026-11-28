import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:saber/data/documents.dart';

/// Ein Textabschnitt mit einheitlicher Formatierung.
class DocRun {
  DocRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.size,
    this.font,
  });

  final String text;
  final bool bold, italic, underline, strike;
  final double? size;
  final String? font;
}

/// Ein Absatz.
class DocPara {
  final runs = <DocRun>[];
  String? align; // left, center, right, justify
  int? header; // 1–3
  String? list; // bullet, ordered, checked, unchecked
  int indent = 0;
}

/// Gemeinsame Zahlen für Bildschirm und Export.
abstract class DocDefaults {
  static const fontSize = 11.0;
  static const defaultFont = 'LiberationSans';
  static const headerSizes = {1: 20.0, 2: 16.0, 3: 14.0};

  /// Einzug pro Ebene in Zentimetern.
  static const indentCm = 1.27;

  /// Schriftfamilie → (Word-Name, Anzeigename)
  static const fonts = {
    'LiberationSans': 'Arial',
    'LiberationSerif': 'Times New Roman',
    'LiberationMono': 'Courier New',
    'Carlito': 'Calibri',
  };
}

/// Zerlegt ein Quill-Delta (JSON) in Absätze. Bilder und andere Einbettungen
/// werden ausgelassen.
List<DocPara> parseDelta(List<dynamic> ops) {
  final paras = <DocPara>[];
  var cur = DocPara();
  for (final op in ops) {
    if (op is! Map) continue;
    final insert = op['insert'];
    if (insert is! String) continue;
    final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
    final parts = insert.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final text = parts[i];
      if (text.isNotEmpty) {
        cur.runs.add(
          DocRun(
            text,
            bold: attrs['bold'] == true,
            italic: attrs['italic'] == true,
            underline: attrs['underline'] == true,
            strike: attrs['strike'] == true,
            size: double.tryParse('${attrs['size'] ?? ''}'),
            font: attrs['font'] as String?,
          ),
        );
      }
      if (i < parts.length - 1) {
        cur
          ..align = attrs['align'] as String?
          ..header = attrs['header'] as int?
          ..list = attrs['list'] as String?
          ..indent = (attrs['indent'] as int?) ?? 0;
        paras.add(cur);
        cur = DocPara();
      }
    }
  }
  if (cur.runs.isNotEmpty) paras.add(cur);
  return paras;
}

/// Wörter im Delta (grobe Zählung).
int countWords(List<dynamic> ops) {
  var n = 0;
  for (final op in ops) {
    if (op is Map && op['insert'] is String) {
      n += RegExp(r'\S+').allMatches(op['insert'] as String).length;
    }
  }
  return n;
}

// ---------------------------------------------------------------- Word

abstract class DocxExport {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static int _twips(double cm) => (cm * 567).round();

  static String _runXml(DocPara para, DocRun run, {String? textOverride}) {
    final font = DocDefaults.fonts[run.font ?? DocDefaults.defaultFont] ?? 'Arial';
    final headerSize = para.header == null
        ? null
        : DocDefaults.headerSizes[para.header];
    final size = run.size ?? headerSize ?? DocDefaults.fontSize;
    final bold = run.bold || para.header != null;
    final rpr = StringBuffer()
      ..write('<w:rFonts w:ascii="$font" w:hAnsi="$font" w:cs="$font"/>')
      ..write(bold ? '<w:b/>' : '')
      ..write(run.italic ? '<w:i/>' : '')
      ..write(run.strike ? '<w:strike/>' : '')
      ..write(run.underline ? '<w:u w:val="single"/>' : '')
      ..write('<w:sz w:val="${(size * 2).round()}"/>')
      ..write('<w:szCs w:val="${(size * 2).round()}"/>');
    final out = StringBuffer('<w:r><w:rPr>$rpr</w:rPr>');
    final text = textOverride ?? run.text;
    final segments = text.split('\t');
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) out.write('<w:tab/>');
      if (segments[i].isNotEmpty) {
        out.write('<w:t xml:space="preserve">${_esc(segments[i])}</w:t>');
      }
    }
    out.write('</w:r>');
    return out.toString();
  }

  static String documentXml(List<DocPara> paras, DocMargins m) {
    final body = StringBuffer();
    var counter = 0;
    for (final para in paras) {
      String? prefix;
      if (para.list == 'ordered') {
        counter++;
        prefix = '$counter.';
      } else {
        counter = 0;
        if (para.list == 'bullet') prefix = '•';
        if (para.list == 'checked') prefix = '☑';
        if (para.list == 'unchecked') prefix = '☐';
      }
      final left = _twips(para.indent * DocDefaults.indentCm) +
          (prefix != null ? 720 : 0);
      final jc = switch (para.align) {
        'center' => 'center',
        'right' => 'right',
        'justify' => 'both',
        _ => null,
      };
      final ppr = StringBuffer('<w:pPr>')
        ..write('<w:spacing w:after="120" w:line="276" w:lineRule="auto"/>');
      if (left > 0 || prefix != null) {
        ppr.write(
          prefix != null
              ? '<w:ind w:left="$left" w:hanging="360"/>'
              : '<w:ind w:left="$left"/>',
        );
      }
      if (jc != null) ppr.write('<w:jc w:val="$jc"/>');
      ppr.write('</w:pPr>');

      body.write('<w:p>$ppr');
      if (prefix != null) {
        body.write(
          _runXml(
            para,
            DocRun('', font: para.runs.firstOrNull?.font),
            textOverride: '$prefix\t',
          ),
        );
      }
      for (final run in para.runs) {
        body.write(_runXml(para, run));
      }
      body.write('</w:p>');
    }
    body.write(
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="${_twips(m.top)}" w:right="${_twips(m.right)}" '
      'w:bottom="${_twips(m.bottom)}" w:left="${_twips(m.left)}" '
      'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>',
    );
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body</w:body></w:document>';
  }

  static const _contentTypes =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';

  static const _rels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  /// Erstellt die .docx-Datei und gibt sie zurück.
  static Future<File> build(String title, FederDoc doc) async {
    final tmp = await getTemporaryDirectory();
    final work = Directory('${tmp.path}/docx_${DateTime.now().microsecondsSinceEpoch}')
      ..createSync(recursive: true);
    await Directory('${work.path}/_rels').create();
    await Directory('${work.path}/word').create();
    await File('${work.path}/[Content_Types].xml').writeAsString(_contentTypes);
    await File('${work.path}/_rels/.rels').writeAsString(_rels);
    await File('${work.path}/word/document.xml').writeAsString(
      documentXml(parseDelta(doc.delta), doc.margins),
    );
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final out = '${tmp.path}/$safe.docx';
    if (File(out).existsSync()) File(out).deleteSync();
    final encoder = ZipFileEncoder()..create(out);
    await encoder.addFile(File('${work.path}/[Content_Types].xml'), '[Content_Types].xml');
    await encoder.addFile(File('${work.path}/_rels/.rels'), '_rels/.rels');
    await encoder.addFile(File('${work.path}/word/document.xml'), 'word/document.xml');
    await encoder.close();
    work.deleteSync(recursive: true);
    return File(out);
  }
}

// ----------------------------------------------------------------- PDF

abstract class PdfExport {
  static const _files = {
    'LiberationSans': 'assets/fonts/liberation/LiberationSans',
    'LiberationSerif': 'assets/fonts/liberation/LiberationSerif',
    'LiberationMono': 'assets/fonts/liberation/LiberationMono',
    'Carlito': 'assets/fonts/carlito/Carlito',
  };

  static final _cache = <String, List<pw.Font>>{};

  /// [Regular, Bold, Italic, BoldItalic]
  static Future<List<pw.Font>> _family(String name) async {
    final key = _files.containsKey(name) ? name : DocDefaults.defaultFont;
    final cached = _cache[key];
    if (cached != null) return cached;
    final base = _files[key]!;
    final fonts = <pw.Font>[];
    for (final suffix in ['Regular', 'Bold', 'Italic', 'BoldItalic']) {
      fonts.add(pw.Font.ttf(await rootBundle.load('$base-$suffix.ttf')));
    }
    return _cache[key] = fonts;
  }

  static Future<Uint8List> build(FederDoc doc) async {
    final paras = parseDelta(doc.delta);
    final fonts = <String, List<pw.Font>>{
      for (final name in _files.keys) name: await _family(name),
    };
    final m = doc.margins;
    const cm = PdfPageFormat.cm;

    pw.TextStyle styleFor(DocPara para, DocRun run) {
      final f = fonts[run.font] ?? fonts[DocDefaults.defaultFont]!;
      final bold = run.bold || para.header != null;
      final index = (bold ? 1 : 0) + (run.italic ? 2 : 0);
      final size =
          run.size ?? DocDefaults.headerSizes[para.header] ?? DocDefaults.fontSize;
      final deco = [
        if (run.underline) pw.TextDecoration.underline,
        if (run.strike) pw.TextDecoration.lineThrough,
      ];
      return pw.TextStyle(
        font: f[index],
        fontSize: size,
        lineSpacing: size * 0.18,
        decoration: deco.isEmpty ? null : pw.TextDecoration.combine(deco),
      );
    }

    final widgets = <pw.Widget>[];
    var counter = 0;
    for (final para in paras) {
      String? prefix;
      if (para.list == 'ordered') {
        counter++;
        prefix = '$counter.';
      } else {
        counter = 0;
        if (para.list == 'bullet') prefix = '•';
        if (para.list == 'checked') prefix = '[x]';
        if (para.list == 'unchecked') prefix = '[ ]';
      }
      final align = switch (para.align) {
        'center' => pw.TextAlign.center,
        'right' => pw.TextAlign.right,
        'justify' => pw.TextAlign.justify,
        _ => pw.TextAlign.left,
      };
      if (para.runs.isEmpty) {
        widgets.add(pw.SizedBox(height: DocDefaults.fontSize * 1.3));
        continue;
      }
      final span = pw.TextSpan(
        children: [
          for (final run in para.runs)
            pw.TextSpan(text: run.text, style: styleFor(para, run)),
        ],
      );
      final rich = pw.RichText(text: span, textAlign: align);
      final indentPt = para.indent * DocDefaults.indentCm * cm;
      if (para.indent == 0 && prefix == null) {
        widgets
          ..add(rich)
          ..add(pw.SizedBox(height: 6));
      } else {
        widgets.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(left: indentPt, bottom: 6),
            child: prefix == null
                ? rich
                : pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.SizedBox(
                        width: 18,
                        child: pw.Text(
                          prefix,
                          style: styleFor(para, para.runs.first),
                        ),
                      ),
                      pw.Expanded(child: rich),
                    ],
                  ),
          ),
        );
      }
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 2000,
        margin: pw.EdgeInsets.fromLTRB(
          m.left * cm,
          m.top * cm,
          m.right * cm,
          m.bottom * cm,
        ),
        build: (context) => widgets.isEmpty ? [pw.SizedBox()] : widgets,
      ),
    );
    return pdf.save();
  }
}
