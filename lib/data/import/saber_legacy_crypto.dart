import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// NUR LESEN: Entschlüsselung des alten Saber-Verfahrens, ausschließlich für
/// den Import eigener Notizen als Kopie. Feder verschlüsselt nie mehr so.
///
/// Das alte Verfahren (aus dem Saber-Quelltext): Schlüssel = SHA-256(Passwort +
/// festes Salz), AES (Standardmodus des `encrypt`-Pakets: SIC, ohne
/// Authentifizierung), ein IV pro Konto aus `config.sbc`.
class SaberLegacyCrypto {
  SaberLegacyCrypto._(this._keyBytes, this._iv);

  static const reproducibleSalt = r'8MnPs64@R&mF8XjWeLrD';

  final Uint8List _keyBytes;
  final IV _iv;

  Encrypter get _encrypter => Encrypter(AES(Key(_keyBytes)));

  /// Erstellt den Entschlüsseler aus dem Inhalt der Saber-`config.sbc`.
  /// Wirft [SaberLegacyWrongPassword], wenn das Passwort nicht passt.
  static SaberLegacyCrypto fromConfig(
    Map<String, dynamic> config,
    String password,
  ) {
    final ivB64 = config['iv'] as String?;
    final encKey = config['key'] as String?;
    if (ivB64 == null || encKey == null) {
      throw const SaberLegacyWrongPassword('config.sbc unvollständig.');
    }
    final hashed = sha256.convert(utf8.encode(password + reproducibleSalt));
    final keyBytes = Uint8List.fromList(hashed.bytes);
    final iv = IV.fromBase64(ivB64);

    // Prüfung: Der gespeicherte Dateischlüssel muss sich zu 32 gültigen Bytes
    // entschlüsseln lassen (es gibt keine echte Authentifizierung).
    try {
      final key = Encrypter(AES(Key(keyBytes))).decrypt64(encKey, iv: iv);
      if (base64.decode(key).length != 32) {
        throw const FormatException('Länge');
      }
    } catch (_) {
      throw const SaberLegacyWrongPassword('Falsches Saber-Passwort.');
    }
    return SaberLegacyCrypto._(keyBytes, iv);
  }

  /// Hex-Dateiname (ohne `.sbe`) -> ursprünglicher Pfad, z. B. `/Ordner/a.sbn2`.
  String? decryptPath(String hexName) {
    try {
      var decrypted = _encrypter.decrypt16(hexName, iv: _iv);
      // Saber-Altlast: Dateien, die mit `null/` statt `/` beginnen.
      if (decrypted.startsWith('null/')) {
        decrypted = decrypted.substring('null/'.length - 1);
      }
      if (!decrypted.startsWith('/')) return null;
      return decrypted;
    } catch (_) {
      return null;
    }
  }

  /// Dateiinhalt entschlüsseln. [isOldJson]: alte `.sbn`-Dateien sind Base64-Text.
  Future<Uint8List> decryptFile(
    Uint8List encrypted, {
    required bool isOldJson,
  }) {
    final keyBytes = _keyBytes;
    final ivBytes = _iv.bytes;
    return Isolate.run(() {
      final encrypter = Encrypter(AES(Key(keyBytes)));
      final iv = IV(ivBytes);
      if (isOldJson) {
        final text = utf8.decode(encrypted);
        return Uint8List.fromList(utf8.encode(encrypter.decrypt64(text, iv: iv)));
      }
      return Uint8List.fromList(
        encrypter.decryptBytes(Encrypted(encrypted), iv: iv),
      );
    });
  }

  /// Entschlüsselt OHNE Padding-Prüfung (nur für Diagnose/Rettung defekter
  /// Server-Dateien). Liefert die rohen Bytes.
  Future<Uint8List> decryptRaw(Uint8List encrypted) {
    final keyBytes = _keyBytes;
    final ivBytes = _iv.bytes;
    return Isolate.run(() {
      final encrypter = Encrypter(AES(Key(keyBytes), padding: null));
      return Uint8List.fromList(
        encrypter.decryptBytes(Encrypted(encrypted), iv: IV(ivBytes)),
      );
    });
  }
}

class SaberLegacyWrongPassword implements Exception {
  const SaberLegacyWrongPassword(this.message);
  final String message;
  @override
  String toString() => message;
}
