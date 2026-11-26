import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/pages/editor/editor.dart';

/// Einband eines Notizbuchs: Farbe, Material und Motiv. Wird in einer kleinen
/// Zusatzdatei neben der Notiz gespeichert (`name.sbn2.c`), genau wie das
/// Vorschaubild (`name.sbn2.p`). Notizen ohne Einband bekommen eine Farbe,
/// die sich aus dem Namen ergibt.
@immutable
class NoteCover {
  const NoteCover({required this.color, this.material = 0, this.motif = 0});

  /// ARGB-Wert der Einbandfarbe.
  final int color;

  /// Index in [materialNames].
  final int material;

  /// Index in [motifNames].
  final int motif;

  static const palette = <int>[
    0xFF14284B, // Nachtblau
    0xFF6D1F2B, // Bordeaux
    0xFF1F4D3A, // Waldgruen
    0xFF1C1C1E, // Schwarz
    0xFF5B3A29, // Kastanie
    0xFF0F5560, // Petrol
    0xFF47285E, // Violett
    0xFF4A5560, // Schiefer
    0xFF9A7414, // Senf
    0xFF9B2D20, // Rot
  ];

  static const materialNames = [
    'Leder',
    'Glatt',
    'Karo',
    'Streifen',
    'Marmor',
    'Punkte',
    'Leinen',
  ];

  static const motifNames = [
    'Kein Motiv',
    'Herz',
    'Totenkopf',
    'LuckyKvD',
    'Feder',
    'Stern',
  ];

  /// Fertige Einbaende zur schnellen Auswahl.
  static const presets = <(String, NoteCover)>[
    ('Nachtblau', NoteCover(color: 0xFF14284B, material: 0, motif: 3)),
    ('Pirat', NoteCover(color: 0xFF1C1C1E, material: 0, motif: 2)),
    ('Herzblatt', NoteCover(color: 0xFF6D1F2B, material: 0, motif: 1)),
    ('Marmor', NoteCover(color: 0xFF1F4D3A, material: 4, motif: 4)),
    ('Schottisch', NoteCover(color: 0xFF9B2D20, material: 2, motif: 0)),
    ('Petrol', NoteCover(color: 0xFF0F5560, material: 6, motif: 5)),
    ('Kastanie', NoteCover(color: 0xFF5B3A29, material: 0, motif: 4)),
    ('Violett', NoteCover(color: 0xFF47285E, material: 5, motif: 1)),
    ('Schiefer', NoteCover(color: 0xFF4A5560, material: 3, motif: 2)),
    ('Senf', NoteCover(color: 0xFF9A7414, material: 1, motif: 3)),
  ];

  static const gold = Color(0xFFE3B84B);
  static const goldLight = Color(0xFFF0D98A);
  static const navy = Color(0xFF0B1A33);

  Color get colorValue => Color(color);

  /// Schriftfarbe, die auf dem Einband gut lesbar ist.
  Color get ink => colorValue.computeLuminance() > 0.4 ? navy : goldLight;

  NoteCover copyWith({int? color, int? material, int? motif}) => NoteCover(
    color: color ?? this.color,
    material: material ?? this.material,
    motif: motif ?? this.motif,
  );

  @override
  bool operator ==(Object other) =>
      other is NoteCover &&
      other.color == color &&
      other.material == material &&
      other.motif == motif;

  @override
  int get hashCode => Object.hash(color, material, motif);

  static final Map<String, NoteCover> _cache = {};

  /// Zaehlt hoch, wenn irgendein Einband geaendert wurde.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static String _name(String filePath) =>
      filePath.substring(filePath.lastIndexOf('/') + 1);

  /// Stabile Zahl aus dem Namen (z. B. fuer Farbe und Buchhoehe).
  static int nameHash(String filePath) {
    var h = 0;
    for (final unit in _name(filePath).codeUnits) {
      h = (h * 31 + unit) & 0x7fffffff;
    }
    return h;
  }

  static NoteCover defaultFor(String filePath) =>
      NoteCover(color: palette[nameHash(filePath) % palette.length]);

  /// Sofort verfuegbarer Einband (aus dem Speicher oder der Standardfarbe).
  static NoteCover peek(String filePath) =>
      _cache[filePath] ?? defaultFor(filePath);

  static String _sidecar(String filePath) => '$filePath${Editor.extension}.c';

  static Future<NoteCover> load(String filePath) async {
    try {
      final file = FileManager.getFile(_sidecar(filePath));
      if (file.existsSync()) {
        final bytes = await FileManager.readBytes(file);
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final cover = NoteCover(
          color: (json['c'] as num).toInt(),
          material: ((json['m'] ?? 0) as num).toInt(),
          motif: ((json['o'] ?? 0) as num).toInt(),
        );
        _cache[filePath] = cover;
        return cover;
      }
    } catch (_) {
      // Defekte Zusatzdatei: Standardeinband verwenden.
    }
    return peek(filePath);
  }

  Future<void> save(String filePath) async {
    _cache[filePath] = this;
    await FileManager.writeFile(
      _sidecar(filePath),
      utf8.encode(jsonEncode({'c': color, 'm': material, 'o': motif})),
      awaitWrite: true,
    );
    changes.value++;
  }
}
