import 'dart:async';

import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';
import 'package:saber/data/doc_export.dart';
import 'package:saber/data/documents.dart';
import 'package:saber/data/spell_check.dart';
import 'package:share_plus/share_plus.dart';

/// Editor für Feder-Textdokumente (A4-Blatt, Ränder, Export als PDF/Word).
class DocumentEditorPage extends StatefulWidget {
  const new({super.key, required this.path});

  final String path;

  @override
  State<DocumentEditorPage> createState() => _DocumentEditorPageState();
}

class _DocumentEditorPageState extends State<DocumentEditorPage> {
  static const a4WidthPt = 595.28;
  static const ptPerCm = 28.3465;

  QuillController? _controller;
  FederDoc _doc = FederDoc();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  Timer? _timer;
  var _dirty = false;
  var _saving = false;
  StreamSubscription<dynamic>? _changes;

  String get _title => widget.path.split('/').last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await Documents.load(widget.path);
    if (!mounted) return;
    final c = QuillController(
      document: doc.delta.isEmpty
          ? Document()
          : Document.fromJson(doc.delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _changes = c.document.changes.listen((_) => _markDirty());
    setState(() {
      _doc = doc;
      _controller = c;
    });
  }

  void _markDirty() {
    _dirty = true;
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), _save);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final c = _controller;
    if (c == null || !_dirty || _saving) return;
    _saving = true;
    _dirty = false;
    try {
      _doc.delta = c.document.toDelta().toJson();
      await Documents.save(widget.path, _doc);
    } finally {
      _saving = false;
    }
    if (_dirty) unawaited(_save());
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _changes?.cancel();
    final c = _controller;
    if (c != null && _dirty) {
      _doc.delta = c.document.toDelta().toJson();
      unawaited(Documents.save(widget.path, _doc));
    }
    c?.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _editMargins() async {
    final m = _doc.margins;
    final fields = {
      'Oben': TextEditingController(text: m.top.toString()),
      'Unten': TextEditingController(text: m.bottom.toString()),
      'Links': TextEditingController(text: m.left.toString()),
      'Rechts': TextEditingController(text: m.right.toString()),
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ränder (cm)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in fields.entries)
              TextField(
                controller: e.value,
                decoration: InputDecoration(labelText: e.key),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    double v(String k, double fallback) {
      final x = double.tryParse(fields[k]!.text.replaceAll(',', '.'));
      return x == null ? fallback : x.clamp(0.0, 8.0).toDouble();
    }

    setState(() {
      _doc.margins = DocMargins(
        top: v('Oben', m.top),
        bottom: v('Unten', m.bottom),
        left: v('Links', m.left),
        right: v('Rechts', m.right),
      );
    });
    _markDirty();
  }

  void _syncDoc() {
    _doc.delta = _controller!.document.toDelta().toJson();
  }

  Future<void> _export(String what) async {
    if (_controller == null) return;
    _syncDoc();
    try {
      switch (what) {
        case 'pdf':
          await Printing.layoutPdf(
            name: _title,
            onLayout: (_) => PdfExport.build(_doc),
          );
        case 'word':
          final file = await DocxExport.build(_title, _doc);
          await SharePlus.instance.share(
            ShareParams(files: [XFile(file.path)]),
          );
        case 'spell':
          await _spell(_controller!.document.toPlainText());
        case 'spelltest':
          await _spell(
            'Das ist ein Tehst mit Fehlren, einem Hauptbahnhofsvorplatz '
            'und einem Donaudampfschifffahrtskapitän. Ich habe es geshen.',
          );
        case 'words':
          final n = countWords(_doc.delta);
          _snack('$n Wörter');
      }
    } catch (e) {
      _snack('Export fehlgeschlagen: $e');
    }
  }

  Future<void> _spell(String text) async {
    final sw = Stopwatch()..start();
    final issues = await SpellCheck.check(text);
    final hs = await SpellCheck.engine;
    sw.stop();
    if (!mounted) return;
    final seen = <String>{};
    final lines = <String>[];
    for (final i in issues) {
      if (!seen.add(i.word)) continue;
      if (lines.length >= 40) break;
      lines.add('${i.word} → ${hs.suggest(i.word, max: 3).join(', ')}');
    }
    final body = issues.isEmpty
        ? 'Keine Fehler (${text.length} Zeichen, ${sw.elapsedMilliseconds} ms, '
              '${hs.wordCount} Wörter im Wörterbuch).'
        : '${issues.length} Fehler (${sw.elapsedMilliseconds} ms):\n\n${lines.join('\n')}';
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Rechtschreibung (Hunspell, Deutsch)'),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: Text(
                _dirty || _saving ? 'Speichert …' : 'Gespeichert',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ränder',
            icon: const Icon(Icons.aspect_ratio),
            onPressed: c == null ? null : _editMargins,
          ),
          PopupMenuButton<String>(
            tooltip: 'Exportieren',
            icon: const Icon(Icons.ios_share),
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'word', child: Text('Als Word (.docx) teilen')),
              PopupMenuItem(value: 'pdf', child: Text('Drucken / PDF speichern')),
              PopupMenuItem(value: 'words', child: Text('Wörter zählen')),
              PopupMenuItem(value: 'spell', child: Text('Rechtschreibung prüfen (Test)')),
              PopupMenuItem(value: 'spelltest', child: Text('Prüfer mit Testsatz testen')),
            ],
          ),
        ],
      ),
      body: c == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                QuillSimpleToolbar(
                  controller: c,
                  config: QuillSimpleToolbarConfig(
                    multiRowsDisplay: false,
                    showDividers: false,
                    showSubscript: false,
                    showSuperscript: false,
                    showInlineCode: false,
                    showCodeBlock: false,
                    showQuote: false,
                    showLink: false,
                    showColorButton: false,
                    showBackgroundColorButton: false,
                    showSmallButton: false,
                    showClipboardCut: false,
                    showClipboardCopy: false,
                    showClipboardPaste: false,
                    showJustifyAlignment: true,
                    showIndent: true,
                    showSearchButton: true,
                    buttonOptions: QuillSimpleToolbarButtonOptions(
                      fontFamily: const QuillToolbarFontFamilyButtonOptions(
                        items: {
                          'Arial': 'LiberationSans',
                          'Times New Roman': 'LiberationSerif',
                          'Courier New': 'LiberationMono',
                          'Calibri': 'Carlito',
                        },
                        initialValue: 'Arial',
                      ),
                      fontSize: QuillToolbarFontSizeButtonOptions(
                        items: {
                          for (final s in [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48])
                            '$s': '$s',
                        },
                        initialValue: '11',
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _sheet(c)),
              ],
            ),
    );
  }

  Widget _sheet(QuillController c) {
    return LayoutBuilder(
      builder: (context, box) {
        final sheetW = (box.maxWidth - 16).clamp(200.0, 860.0).toDouble();
        final k = sheetW / a4WidthPt;
        final m = _doc.margins;
        TextStyle base([double size = DocDefaults.fontSize, bool bold = false]) =>
            TextStyle(
              fontFamily: DocDefaults.defaultFont,
              fontSize: size,
              height: 1.15,
              color: const Color(0xFF000000),
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            );
        DefaultTextBlockStyle block(TextStyle st) => DefaultTextBlockStyle(
          st,
          HorizontalSpacing.zero,
          const VerticalSpacing(0, 6),
          VerticalSpacing.zero,
          null,
        );
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.topCenter,
          child: Container(
            width: sheetW,
            margin: const EdgeInsets.symmetric(vertical: 8),
            color: const Color(0xFFFFFFFF),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(k),
              ),
              child: QuillEditor(
                controller: c,
                focusNode: _focus,
                scrollController: _scroll,
                config: QuillEditorConfig(
                  expands: true,
                  scrollable: true,
                  padding: EdgeInsets.fromLTRB(
                    m.left * ptPerCm * k,
                    m.top * ptPerCm * k,
                    m.right * ptPerCm * k,
                    m.bottom * ptPerCm * k,
                  ),
                  customStyles: DefaultStyles(
                    paragraph: block(base()),
                    h1: block(base(DocDefaults.headerSizes[1]!, true)),
                    h2: block(base(DocDefaults.headerSizes[2]!, true)),
                    h3: block(base(DocDefaults.headerSizes[3]!, true)),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
