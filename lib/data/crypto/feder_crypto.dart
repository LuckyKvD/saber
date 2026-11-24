import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Fehler der Feder-Verschlüsselung (falsches Passwort, manipulierte Daten …).
class FederCryptoException implements Exception {
  const FederCryptoException(this.message);
  final String message;
  @override
  String toString() => 'FederCryptoException: $message';
}

/// Parameter der Passwort-Ableitung (Argon2id). Werden im Tresor gespeichert,
/// damit sie später erhöht werden können, ohne alte Tresore zu brechen.
class KdfParams {
  const KdfParams({
    this.memoryKiB = 32768,
    this.iterations = 3,
    this.parallelism = 1,
  });

  /// Speicher in KiB (32768 = 32 MiB).
  final int memoryKiB;
  final int iterations;
  final int parallelism;
}

/// Ergebnis von [FederCrypto.createVault].
class VaultCreation {
  const VaultCreation({
    required this.vault,
    required this.masterKey,
    required this.recoveryKey,
  });

  /// Wird unverschlüsselt (aber nur mit eingepacktem Schlüssel) gespeichert.
  final Map<String, dynamic> vault;

  /// Schlüssel für alle Dateien. Nie speichern, außer geschützt.
  final SecretKey masterKey;

  /// Zum Ausdrucken/Aufschreiben. Nur dieses eine Mal sichtbar.
  final String recoveryKey;
}

/// Verschlüsselung für Feder (Phase 4, Format „Feder-Krypto 1“).
///
/// - Passwort -> Argon2id (Zufalls-Salz) -> Schlüssel zum Einpacken
/// - Zufälliger 256-Bit-Hauptschlüssel, eingepackt mit Passwort UND
///   Wiederherstellungsschlüssel (so ist Passwortwechsel/-reset möglich)
/// - Dateien: XChaCha20-Poly1305 (authentifiziert), zufälliges 192-Bit-Nonce
///   pro Datei, Pfad als zugehörige Daten (Dateien lassen sich nicht
///   unbemerkt vertauschen)
///
/// Nur symmetrische 256-Bit-Verfahren; keine asymmetrische Kryptografie.
class FederCrypto {
  FederCrypto._();

  static const vaultVersion = 1;
  static final _cipher = Xchacha20.poly1305Aead();
  static const _magic = [0x46, 0x44, 0x52, 0x31]; // "FDR1"
  static const _nonceLength = 24;
  static const _macLength = 16;

  static const _wrapAadPassword = 'feder-vault-v1-password';
  static const _wrapAadRecovery = 'feder-vault-v1-recovery';

  // ---- Tresor -------------------------------------------------------------

  static Future<VaultCreation> createVault(
    String password, {
    KdfParams kdf = const KdfParams(),
  }) async {
    final masterKey = await _cipher.newSecretKey();
    final masterBytes = await masterKey.extractBytes();

    final salt = _randomBytes(16);
    final passwordKek = await _deriveKek(password, salt, kdf);

    final recoveryBytes = _randomBytes(32);
    final recoveryKek = await _recoveryKek(recoveryBytes);

    final vault = <String, dynamic>{
      'v': vaultVersion,
      'kdf': {
        'alg': 'argon2id',
        'm': kdf.memoryKiB,
        't': kdf.iterations,
        'p': kdf.parallelism,
        'salt': base64.encode(salt),
      },
      'pw': await _wrap(passwordKek, masterBytes, _wrapAadPassword),
      'rec': await _wrap(recoveryKek, masterBytes, _wrapAadRecovery),
    };
    return VaultCreation(
      vault: vault,
      masterKey: masterKey,
      recoveryKey: encodeRecoveryKey(recoveryBytes),
    );
  }

  static Future<SecretKey> unlockWithPassword(
    Map<String, dynamic> vault,
    String password,
  ) async {
    _checkVersion(vault);
    final kdf = vault['kdf'] as Map<String, dynamic>;
    final kek = await _deriveKek(
      password,
      base64.decode(kdf['salt'] as String),
      KdfParams(
        memoryKiB: kdf['m'] as int,
        iterations: kdf['t'] as int,
        parallelism: kdf['p'] as int,
      ),
    );
    return _unwrap(
      kek,
      vault['pw'] as Map<String, dynamic>,
      _wrapAadPassword,
      'Falsches Passwort oder beschädigter Tresor.',
    );
  }

  static Future<SecretKey> unlockWithRecoveryKey(
    Map<String, dynamic> vault,
    String recoveryKey,
  ) async {
    _checkVersion(vault);
    final kek = await _recoveryKek(decodeRecoveryKey(recoveryKey));
    return _unwrap(
      kek,
      vault['rec'] as Map<String, dynamic>,
      _wrapAadRecovery,
      'Falscher Wiederherstellungsschlüssel oder beschädigter Tresor.',
    );
  }

  /// Neues Passwort (neues Salz); der Wiederherstellungsschlüssel bleibt gültig.
  static Future<Map<String, dynamic>> changePassword(
    Map<String, dynamic> vault,
    SecretKey masterKey,
    String newPassword, {
    KdfParams kdf = const KdfParams(),
  }) async {
    _checkVersion(vault);
    final salt = _randomBytes(16);
    final kek = await _deriveKek(newPassword, salt, kdf);
    return {
      ...vault,
      'kdf': {
        'alg': 'argon2id',
        'm': kdf.memoryKiB,
        't': kdf.iterations,
        'p': kdf.parallelism,
        'salt': base64.encode(salt),
      },
      'pw': await _wrap(
        kek,
        await masterKey.extractBytes(),
        _wrapAadPassword,
      ),
    };
  }

  // ---- Dateien ------------------------------------------------------------

  /// Verschlüsselt [plain]. [path] ist der logische Pfad der Datei (z. B.
  /// `/Notiz.sbn2`) und wird an die Verschlüsselung gebunden.
  static Future<Uint8List> encryptFile(
    SecretKey masterKey,
    List<int> plain, {
    required String path,
  }) async {
    final fileKey = await _fileKey(masterKey);
    final box = await _cipher.encrypt(
      plain,
      secretKey: fileKey,
      nonce: _cipher.newNonce(),
      aad: _fileAad(path),
    );
    return Uint8List.fromList([..._magic, ...box.concatenation()]);
  }

  static Future<Uint8List> decryptFile(
    SecretKey masterKey,
    List<int> data, {
    required String path,
  }) async {
    if (data.length < _magic.length + _nonceLength + _macLength) {
      throw const FederCryptoException('Datei zu kurz.');
    }
    for (int i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) {
        throw const FederCryptoException('Kein Feder-verschlüsseltes Format.');
      }
    }
    final box = SecretBox.fromConcatenation(
      data.sublist(_magic.length),
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    try {
      final clear = await _cipher.decrypt(
        box,
        secretKey: await _fileKey(masterKey),
        aad: _fileAad(path),
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const FederCryptoException(
        'Datei manipuliert, falscher Schlüssel oder falscher Pfad.',
      );
    }
  }

  // ---- Dateinamen ---------------------------------------------------------

  /// Deterministische, authentifizierte Verschlüsselung eines Pfads
  /// (SIV-Konstruktion: Nonce = HMAC(Pfad)). Gleicher Pfad -> gleicher Name
  /// (nötig, damit alle Geräte dieselbe Datei finden), verschiedene Pfade ->
  /// verschiedene Nonces. Ergebnis: Kleinbuchstaben-Base32, ohne Padding.
  static Future<String> encryptPath(SecretKey masterKey, String path) async {
    final nonceKey = await _subKey(masterKey, 'feder-name-nonce-v1');
    final nameKey = await _subKey(masterKey, 'feder-name-v1');
    final pathBytes = utf8.encode(path);
    final mac = await Hmac.sha256().calculateMac(
      pathBytes,
      secretKey: nonceKey,
    );
    final box = await _cipher.encrypt(
      pathBytes,
      secretKey: nameKey,
      nonce: mac.bytes.sublist(0, _nonceLength),
      aad: utf8.encode('feder-name-v1'),
    );
    return _b32Encode(box.concatenation()).toLowerCase();
  }

  static Future<String> decryptPath(SecretKey masterKey, String name) async {
    try {
      final box = SecretBox.fromConcatenation(
        _b32Decode(name),
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final clear = await _cipher.decrypt(
        box,
        secretKey: await _subKey(masterKey, 'feder-name-v1'),
        aad: utf8.encode('feder-name-v1'),
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw const FederCryptoException('Dateiname ungültig oder manipuliert.');
    } on FormatException {
      throw const FederCryptoException('Dateiname ungültig.');
    }
  }

  // ---- Wiederherstellungsschlüssel ---------------------------------------

  static const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static String _b32Encode(List<int> bytes) {
    final sb = StringBuffer();
    int buffer = 0, bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | b;
      bits += 8;
      while (bits >= 5) {
        sb.write(_b32[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) sb.write(_b32[(buffer << (5 - bits)) & 31]);
    return sb.toString();
  }

  static Uint8List _b32Decode(String input) {
    final out = <int>[];
    int buffer = 0, bits = 0;
    for (final ch in input.toUpperCase().split('')) {
      final v = _b32.indexOf(ch);
      if (v < 0) throw const FormatException('Ungültiges Base32-Zeichen');
      buffer = (buffer << 5) | v;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 255);
        bits -= 8;
        buffer &= (1 << bits) - 1;
      }
    }
    // Nur kanonische Kodierung zulassen (übrige Bits müssen 0 sein), sonst
    // gäbe es mehrere Namen für dieselbe Datei.
    if (buffer != 0) throw const FormatException('Nicht kanonisches Base32');
    return Uint8List.fromList(out);
  }

  /// 32 Bytes -> 52 Zeichen Base32 in Fünfergruppen, getrennt durch `-`.
  static String encodeRecoveryKey(List<int> bytes) {
    final raw = _b32Encode(bytes);
    return [
      for (int i = 0; i < raw.length; i += 5)
        raw.substring(i, i + 5 > raw.length ? raw.length : i + 5),
    ].join('-');
  }

  static Uint8List decodeRecoveryKey(String key) {
    final cleaned = key.replaceAll(RegExp(r'[\s-]'), '');
    final Uint8List out;
    try {
      out = _b32Decode(cleaned);
    } on FormatException {
      throw const FederCryptoException(
        'Ungültiges Zeichen im Wiederherstellungsschlüssel.',
      );
    }
    if (out.length != 32) {
      throw const FederCryptoException(
        'Wiederherstellungsschlüssel hat die falsche Länge.',
      );
    }
    return out;
  }

  // ---- intern -------------------------------------------------------------

  static void _checkVersion(Map<String, dynamic> vault) {
    if (vault['v'] != vaultVersion) {
      throw FederCryptoException(
        'Unbekannte Tresor-Version: ${vault['v']}.',
      );
    }
  }

  static Uint8List _randomBytes(int n) {
    final key = SecretKeyData.random(length: n);
    return Uint8List.fromList(key.bytes);
  }

  static List<int> _fileAad(String path) => [..._magic, ...utf8.encode(path)];

  static Future<SecretKey> _fileKey(SecretKey master) =>
      _subKey(master, 'feder-file-v1');

  static Future<SecretKey> _subKey(SecretKey master, String info) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: master,
      nonce: const <int>[],
      info: utf8.encode(info),
    );
  }

  static Future<SecretKey> _recoveryKek(List<int> recoveryBytes) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(recoveryBytes),
      nonce: const <int>[],
      info: utf8.encode('feder-recovery-v1'),
    );
  }

  /// Argon2id im Hintergrund-Isolate, damit die Oberfläche nicht einfriert.
  static Future<SecretKey> _deriveKek(
    String password,
    List<int> salt,
    KdfParams p,
  ) async {
    final pw = utf8.encode(password);
    final bytes = await Isolate.run(() async {
      final key = await Argon2id(
        parallelism: p.parallelism,
        memory: p.memoryKiB,
        iterations: p.iterations,
        hashLength: 32,
      ).deriveKey(secretKey: SecretKey(pw), nonce: salt);
      return key.extractBytes();
    });
    return SecretKey(bytes);
  }

  static Future<Map<String, dynamic>> _wrap(
    SecretKey kek,
    List<int> master,
    String aad,
  ) async {
    final box = await _cipher.encrypt(
      master,
      secretKey: kek,
      nonce: _cipher.newNonce(),
      aad: utf8.encode(aad),
    );
    return {'data': base64.encode(box.concatenation())};
  }

  static Future<SecretKey> _unwrap(
    SecretKey kek,
    Map<String, dynamic> wrapped,
    String aad,
    String failureMessage,
  ) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64.decode(wrapped['data'] as String),
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      final master = await _cipher.decrypt(
        box,
        secretKey: kek,
        aad: utf8.encode(aad),
      );
      return SecretKey(master);
    } on SecretBoxAuthenticationError {
      throw FederCryptoException(failureMessage);
    }
  }
}
