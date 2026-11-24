import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/import/saber_legacy_crypto.dart';

/// Baut eine config.sbc und Dateien exakt wie das alte Saber-Verfahren.
Map<String, dynamic> _fakeSaberConfig(String password, IV iv) {
  final keyBytes = sha256
      .convert(utf8.encode(password + SaberLegacyCrypto.reproducibleSalt))
      .bytes;
  final encrypter = Encrypter(AES(Key.fromBase64(base64.encode(keyBytes))));
  final fileKey = Key.fromSecureRandom(32);
  return {
    'key': encrypter.encrypt(fileKey.base64, iv: iv).base64,
    'iv': iv.base64,
  };
}

Encrypter _enc(String password) => Encrypter(
  AES(
    Key.fromBase64(
      base64.encode(
        sha256
            .convert(utf8.encode(password + SaberLegacyCrypto.reproducibleSalt))
            .bytes,
      ),
    ),
  ),
);

void main() {
  final iv = IV.fromSecureRandom(16);

  test('richtiges Saber-Passwort wird akzeptiert, falsches abgelehnt', () {
    final config = _fakeSaberConfig('mein altes Passwort', iv);
    expect(
      () => SaberLegacyCrypto.fromConfig(config, 'mein altes Passwort'),
      returnsNormally,
    );
    expect(
      () => SaberLegacyCrypto.fromConfig(config, 'falsch'),
      throwsA(isA<SaberLegacyWrongPassword>()),
    );
  });

  test('Pfad (Hex) wird wie in Saber entschlüsselt', () {
    final config = _fakeSaberConfig('pw', iv);
    final crypto = SaberLegacyCrypto.fromConfig(config, 'pw');
    final hex = _enc('pw').encrypt('/Schule/Mathe.sbn2', iv: iv).base16;
    expect(crypto.decryptPath(hex), '/Schule/Mathe.sbn2');
    expect(crypto.decryptPath('zzzz'), isNull);
  });

  test('Binärdatei und alte JSON-Datei werden entschlüsselt', () async {
    final config = _fakeSaberConfig('pw', iv);
    final crypto = SaberLegacyCrypto.fromConfig(config, 'pw');
    final bytes = List<int>.generate(1000, (i) => i % 256);
    final encBytes = _enc('pw').encryptBytes(bytes, iv: iv).bytes;
    expect(await crypto.decryptFile(encBytes, isOldJson: false), bytes);

    final jsonText = '{"a": "äöü"}';
    final encJson = utf8.encode(_enc('pw').encrypt(jsonText, iv: iv).base64);
    final dec = await crypto.decryptFile(
      Uint8List.fromList(encJson),
      isOldJson: true,
    );
    expect(utf8.decode(dec), jsonText);
  });
}
