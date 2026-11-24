import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/crypto/local_crypto.dart';

void main() {
  final key = List<int>.generate(32, (i) => i);
  final otherKey = List<int>.generate(32, (i) => 255 - i);

  test('Roundtrip', () async {
    final plain = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final enc = await LocalCrypto.encryptWithKey(key, plain);
    expect(LocalCrypto.isEncrypted(enc), isTrue);
    expect(enc.length, plain.length + 44);
    expect(await LocalCrypto.decryptWithKey(key, enc), plain);
  });

  test('Klartext wird nicht als verschlüsselt erkannt', () {
    expect(LocalCrypto.isEncrypted(Uint8List(100)), isFalse);
    expect(LocalCrypto.isEncrypted(Uint8List.fromList([0x89, 0x50, 0x4E])), isFalse);
  });

  test('Zwei Verschlüsselungen derselben Daten unterscheiden sich', () async {
    final plain = Uint8List.fromList([1, 2, 3, 4, 5]);
    final a = await LocalCrypto.encryptWithKey(key, plain);
    final b = await LocalCrypto.encryptWithKey(key, plain);
    expect(a, isNot(equals(b)));
  });

  test('Falscher Schlüssel wird abgelehnt', () async {
    final enc = await LocalCrypto.encryptWithKey(
      key,
      Uint8List.fromList([1, 2, 3]),
    );
    expect(
      () => LocalCrypto.decryptWithKey(otherKey, enc),
      throwsA(isA<FormatException>()),
    );
  });

  test('Manipulierte Datei wird abgelehnt', () async {
    final enc = await LocalCrypto.encryptWithKey(
      key,
      Uint8List.fromList(List.filled(100, 7)),
    );
    enc[40] ^= 1;
    expect(
      () => LocalCrypto.decryptWithKey(key, enc),
      throwsA(isA<FormatException>()),
    );
  });

  test('Leere Daten', () async {
    final enc = await LocalCrypto.encryptWithKey(key, Uint8List(0));
    expect(await LocalCrypto.decryptWithKey(key, enc), isEmpty);
  });

  test('Welche Dateien werden verschlüsselt', () {
    for (final p in [
      '/a.sbn2',
      '/a.sbn',
      '/a.sbn2.p',
      '/a.sbn2.0',
      '/Ordner/b.sbn2.12',
    ]) {
      expect(LocalCrypto.isEncryptablePath(p), isTrue, reason: p);
    }
    for (final p in ['/a.pdf', '/a.sbn2.feder-tmp', '/readme.md', '/a.png']) {
      expect(LocalCrypto.isEncryptablePath(p), isFalse, reason: p);
    }
  });
}
