import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:saber/data/file_manager/file_manager.dart';

/// Wie [FileImage], liest die Datei aber über [FileManager.readBytes] und
/// entschlüsselt sie damit bei Bedarf (lokale Verschlüsselung).
class DecryptedFileImage extends FileImage {
  DecryptedFileImage(File file, {double scale = 1.0})
    : super(file, scale: scale);

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: key.scale,
      debugLabel: key.file.path,
      informationCollector: () => <DiagnosticsNode>[
        ErrorDescription('Path: ${key.file.path}'),
      ],
    );
  }

  Future<ui.Codec> _load(FileImage key, ImageDecoderCallback decode) async {
    final bytes = await FileManager.readBytes(key.file);
    if (bytes.lengthInBytes == 0) {
      PaintingBinding.instance.imageCache.evict(key);
      throw StateError('${key.file.path} is empty and cannot be loaded.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }
}
