import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:saber/data/crypto/feder_crypto.dart';
import 'package:saber/data/crypto/feder_session.dart';
import 'package:saber/data/prefs.dart';

/// Lokale Verschlüsselung der Notizdateien auf dem Gerät.
///
/// Format: "FDL1" + 24 Byte Nonce + Chiffretext + 16 Byte MAC
/// (XChaCha20-Poly1305). Der Schlüssel wird per HKDF aus dem Hauptschlüssel
/// abgeleitet (getrennt vom Sync-Schlüssel). Der Pfad wird NICHT gebunden,
/// damit Dateien umbenannt/verschoben werden können.
class LocalCrypto {
  LocalCrypto._();

  static const _magic = [0x46, 0x44, 0x4C, 0x31]; // "FDL1"
  static const _overhead = 4 + 24 + 16;

  /// Dateien, die lokal verschlüsselt werden: Notizen, alte JSON-Notizen,
  /// Vorschaubilder und Anhänge (`.sbn2.0`, `.sbn2.p` …).
  static final _encryptablePath = RegExp(r'\.sbn2?(\.[\dp]+)?$');

  static bool isEncryptablePath(String path) => _encryptablePath.hasMatch(path);

  /// Lokale Verschlüsselung ist nur aktiv, wenn der Hauptschlüssel vorliegt.
  static bool get isActive => FederSession.isUnlocked;

  /// Wartet, bis der gespeicherte Schlüssel geladen ist (App-Start).
  static Future<void> ensureReady() async {
    if (!stows.key.loaded) await stows.key.waitUntilRead();
  }

  static bool isEncrypted(List<int> data) {
    if (data.length < _overhead) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<Uint8List> encrypt(List<int> plain) async {
    final keyBytes = await FederCrypto.localFileKeyBytes(
      FederSession.masterKey,
    );
    final input = plain is Uint8List ? plain : Uint8List.fromList(plain);
    return Isolate.run(() => encryptWithKey(keyBytes, input));
  }

  static Future<Uint8List> decrypt(List<int> data) async {
    final keyBytes = await FederCrypto.localFileKeyBytes(
      FederSession.masterKey,
    );
    final input = data is Uint8List ? data : Uint8List.fromList(data);
    return Isolate.run(() => decryptWithKey(keyBytes, input));
  }

  /// Nur für Tests und den Isolate-Aufruf.
  static Future<Uint8List> encryptWithKey(
    List<int> keyBytes,
    Uint8List plain,
  ) async {
    final cipher = Xchacha20.poly1305Aead();
    final box = await cipher.encrypt(
      plain,
      secretKey: SecretKey(keyBytes),
      nonce: cipher.newNonce(),
      aad: _magic,
    );
    final out = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(box.concatenation());
    return out.toBytes();
  }

  static Future<Uint8List> decryptWithKey(
    List<int> keyBytes,
    Uint8List data,
  ) async {
    if (!isEncrypted(data)) {
      throw const FormatException('Keine lokal verschlüsselte Datei.');
    }
    final cipher = Xchacha20.poly1305Aead();
    final box = SecretBox.fromConcatenation(
      Uint8List.sublistView(data, _magic.length),
      nonceLength: 24,
      macLength: 16,
    );
    try {
      final clear = await cipher.decrypt(
        box,
        secretKey: SecretKey(keyBytes),
        aad: _magic,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Lokale Datei manipuliert oder falscher Schlüssel.',
      );
    }
  }
}
