import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/crypto/feder_crypto.dart';

// Kleine Parameter, damit die Tests schnell laufen.
const _fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);

void main() {
  test('Datei: verschlüsseln und entschlüsseln', () async {
    final v = await FederCrypto.createVault('Passphrase eins', kdf: _fast);
    final plain = utf8.encode('Meine geheime Notiz äöü');
    final enc = await FederCrypto.encryptFile(v.masterKey, plain, path: '/a.sbn2');
    expect(enc, isNotEmpty);
    expect(utf8.decode(enc, allowMalformed: true), isNot(contains('geheime')));
    final dec = await FederCrypto.decryptFile(v.masterKey, enc, path: '/a.sbn2');
    expect(dec, plain);
  });

  test('gleiche Daten ergeben jedes Mal anderen Chiffretext', () async {
    final v = await FederCrypto.createVault('pw', kdf: _fast);
    final a = await FederCrypto.encryptFile(v.masterKey, [1, 2, 3], path: '/x');
    final b = await FederCrypto.encryptFile(v.masterKey, [1, 2, 3], path: '/x');
    expect(a, isNot(b));
  });

  test('Manipulation wird erkannt', () async {
    final v = await FederCrypto.createVault('pw', kdf: _fast);
    final enc = await FederCrypto.encryptFile(v.masterKey, [1, 2, 3, 4], path: '/x');
    enc[enc.length - 1] ^= 1;
    expect(
      () => FederCrypto.decryptFile(v.masterKey, enc, path: '/x'),
      throwsA(isA<FederCryptoException>()),
    );
  });

  test('Datei lässt sich nicht an anderen Pfad verschieben', () async {
    final v = await FederCrypto.createVault('pw', kdf: _fast);
    final enc = await FederCrypto.encryptFile(v.masterKey, [9, 9], path: '/a');
    expect(
      () => FederCrypto.decryptFile(v.masterKey, enc, path: '/b'),
      throwsA(isA<FederCryptoException>()),
    );
  });

  test('Passwort entsperrt, falsches Passwort nicht', () async {
    final v = await FederCrypto.createVault('richtig', kdf: _fast);
    final key = await FederCrypto.unlockWithPassword(v.vault, 'richtig');
    expect(await key.extractBytes(), await v.masterKey.extractBytes());
    expect(
      () => FederCrypto.unlockWithPassword(v.vault, 'falsch'),
      throwsA(isA<FederCryptoException>()),
    );
  });

  test('Wiederherstellungsschlüssel entsperrt (auch mit Leerzeichen/klein)', () async {
    final v = await FederCrypto.createVault('pw', kdf: _fast);
    final messy = v.recoveryKey.toLowerCase().replaceAll('-', ' ');
    final key = await FederCrypto.unlockWithRecoveryKey(v.vault, messy);
    expect(await key.extractBytes(), await v.masterKey.extractBytes());
    expect(
      () => FederCrypto.unlockWithRecoveryKey(v.vault, 'AAAAA-BBBBB'),
      throwsA(isA<FederCryptoException>()),
    );
  });

  test('Passwort ändern: neues gilt, altes nicht, Recovery bleibt', () async {
    final v = await FederCrypto.createVault('alt', kdf: _fast);
    final changed = await FederCrypto.changePassword(
      v.vault,
      v.masterKey,
      'neu',
      kdf: _fast,
    );
    final key = await FederCrypto.unlockWithPassword(changed, 'neu');
    expect(await key.extractBytes(), await v.masterKey.extractBytes());
    expect(
      () => FederCrypto.unlockWithPassword(changed, 'alt'),
      throwsA(isA<FederCryptoException>()),
    );
    final viaRecovery = await FederCrypto.unlockWithRecoveryKey(
      changed,
      v.recoveryKey,
    );
    expect(await viaRecovery.extractBytes(), await v.masterKey.extractBytes());
  });

  test('Base32 Hin- und Rückweg', () {
    final bytes = List<int>.generate(32, (i) => i * 7 % 256);
    final s = FederCrypto.encodeRecoveryKey(bytes);
    expect(FederCrypto.decodeRecoveryKey(s), bytes);
  });

  test('Tresor-JSON ist serialisierbar', () async {
    final v = await FederCrypto.createVault('pw', kdf: _fast);
    final back = jsonDecode(jsonEncode(v.vault)) as Map<String, dynamic>;
    final key = await FederCrypto.unlockWithPassword(back, 'pw');
    expect(await key.extractBytes(), await v.masterKey.extractBytes());
  });

  test('Dateiname: deterministisch, umkehrbar, nur Kleinbuchstaben/Ziffern', () async {
    final v = await FederCrypto.createVault('pw', kdf: _fast);
    final a = await FederCrypto.encryptPath(v.masterKey, '/Schule/Mathe äöü.sbn2');
    final b = await FederCrypto.encryptPath(v.masterKey, '/Schule/Mathe äöü.sbn2');
    final c = await FederCrypto.encryptPath(v.masterKey, '/Schule/Mathe2.sbn2');
    expect(a, b);
    expect(a, isNot(c));
    expect(RegExp(r'^[a-z2-7]+$').hasMatch(a), isTrue);
    expect(await FederCrypto.decryptPath(v.masterKey, a), '/Schule/Mathe äöü.sbn2');
  });

  test('Dateiname: falscher Schlüssel oder Manipulation wird erkannt', () async {
    final v = await FederCrypto.createVault('pw', kdf: _fast);
    final w = await FederCrypto.createVault('pw', kdf: _fast);
    final a = await FederCrypto.encryptPath(v.masterKey, '/x.sbn2');
    expect(
      () => FederCrypto.decryptPath(w.masterKey, a),
      throwsA(isA<FederCryptoException>()),
    );
    final tampered = '${a.substring(0, a.length - 1)}${a.endsWith('a') ? 'b' : 'a'}';
    expect(
      () => FederCrypto.decryptPath(v.masterKey, tampered),
      throwsA(isA<FederCryptoException>()),
    );
    expect(
      () => FederCrypto.decryptPath(v.masterKey, '!!!'),
      throwsA(isA<FederCryptoException>()),
    );
  });
}
