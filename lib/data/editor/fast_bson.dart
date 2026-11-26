import 'dart:convert';
import 'dart:typed_data';

/// Feder: Schneller Leser für das BSON-Format der Notizen.
///
/// Das Paket `bson` baut beim Lesen für jeden Wert Hilfsobjekte auf und
/// braucht dadurch bei großen Notizen (viele Striche) mehrere Sekunden.
/// Dieser Leser liefert direkt Map/List/Zahlen/Text und kopiert Binärdaten
/// als [Uint8List]. Unbekannte Typen lösen eine [FormatException] aus; der
/// Aufrufer fällt dann auf das Paket `bson` zurück.
class FastBson {
  FastBson._(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _pos = 0;

  /// Liest ein komplettes BSON-Dokument.
  static Map<String, dynamic> decode(Uint8List bytes) {
    final reader = FastBson._(bytes);
    return reader._readDocument();
  }

  Map<String, dynamic> _readDocument() {
    final start = _pos;
    final length = _data.getInt32(_pos, Endian.little);
    if (length < 5 || start + length > _bytes.length) {
      throw const FormatException('BSON: ungueltige Laenge');
    }
    _pos += 4;
    final end = start + length;
    final map = <String, dynamic>{};
    while (true) {
      final type = _bytes[_pos++];
      if (type == 0) break;
      final key = _readCString();
      map[key] = _readValue(type);
    }
    if (_pos != end) throw const FormatException('BSON: Laengenfehler');
    return map;
  }

  List<dynamic> _readArray() {
    final start = _pos;
    final length = _data.getInt32(_pos, Endian.little);
    if (length < 5 || start + length > _bytes.length) {
      throw const FormatException('BSON: ungueltige Laenge');
    }
    _pos += 4;
    final end = start + length;
    final list = <dynamic>[];
    while (true) {
      final type = _bytes[_pos++];
      if (type == 0) break;
      // Schluessel ("0", "1", ...) ueberspringen.
      while (_bytes[_pos] != 0) {
        _pos++;
      }
      _pos++;
      list.add(_readValue(type));
    }
    if (_pos != end) throw const FormatException('BSON: Laengenfehler');
    return list;
  }

  String _readCString() {
    final start = _pos;
    var ascii = true;
    while (_bytes[_pos] != 0) {
      if (_bytes[_pos] >= 0x80) ascii = false;
      _pos++;
    }
    final end = _pos;
    _pos++; // Null-Byte
    return ascii
        ? String.fromCharCodes(_bytes, start, end)
        : utf8.decode(Uint8List.sublistView(_bytes, start, end));
  }

  dynamic _readValue(int type) {
    switch (type) {
      case 0x01: // double
        final v = _data.getFloat64(_pos, Endian.little);
        _pos += 8;
        return v;
      case 0x02: // String
        final len = _data.getInt32(_pos, Endian.little);
        _pos += 4;
        final s = utf8.decode(Uint8List.sublistView(_bytes, _pos, _pos + len - 1));
        _pos += len;
        return s;
      case 0x03:
        return _readDocument();
      case 0x04:
        return _readArray();
      case 0x05: // Binary
        final len = _data.getInt32(_pos, Endian.little);
        final subtype = _bytes[_pos + 4];
        _pos += 5;
        if (subtype == 0x02) {
          // Veraltetes Format mit innerer Laenge.
          final inner = _data.getInt32(_pos, Endian.little);
          final out = Uint8List.fromList(
            Uint8List.sublistView(_bytes, _pos + 4, _pos + 4 + inner),
          );
          _pos += len;
          return out;
        }
        final out = Uint8List.fromList(
          Uint8List.sublistView(_bytes, _pos, _pos + len),
        );
        _pos += len;
        return out;
      case 0x08:
        return _bytes[_pos++] != 0;
      case 0x0A:
        return null;
      case 0x10:
        final v = _data.getInt32(_pos, Endian.little);
        _pos += 4;
        return v;
      case 0x12:
        final v = _data.getInt64(_pos, Endian.little);
        _pos += 8;
        return v;
      default:
        throw FormatException('BSON: Typ 0x${type.toRadixString(16)} nicht unterstuetzt');
    }
  }
}
