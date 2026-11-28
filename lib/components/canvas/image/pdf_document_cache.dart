import 'dart:async';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

class PdfDocumentCache {
  final Map<String, FutureOr<PdfDocument>> _cache = {};

  /// Loads a PDF document from [filePath].
  /// If the bytes are provided, they are used instead of reading from disk.
  ///
  /// Feder: [readBytes] wird nur bei einem Cache-Fehlgriff aufgerufen. Vorher
  /// wurde die komplette (ggf. entschlüsselte) PDF-Datei für JEDE Seite neu
  /// gelesen, auch wenn das Dokument längst im Cache lag.
  FutureOr<PdfDocument> load(
    String filePath, {
    Uint8List? pdfBytes,
    Future<Uint8List> Function()? readBytes,
  }) {
    return _cache[filePath] ??= _loadCacheMiss(
      filePath,
      pdfBytes: pdfBytes,
      readBytes: readBytes,
    );
  }

  Future<PdfDocument> _loadCacheMiss(
    String filePath, {
    Uint8List? pdfBytes,
    Future<Uint8List> Function()? readBytes,
  }) async {
    pdfBytes ??= await readBytes?.call();
    final document = pdfBytes == null
        ? PdfDocument.openFile(filePath, useProgressiveLoading: true)
        : PdfDocument.openData(
            pdfBytes,
            useProgressiveLoading: true,
            sourceName: filePath,
          );
    _cache[filePath] = document;
    return document;
  }

  void dispose() {
    for (final documentFuture in _cache.values) {
      Future.value(documentFuture).then((document) => document.dispose());
    }
    _cache.clear();
  }
}
