import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:saber/data/prefs.dart';

/// Zugriff auf den lokal gespeicherten Hauptschlüssel (im sicheren Speicher,
/// `stows.key`). Das Verschlüsselungspasswort selbst wird nie gespeichert.
class FederSession {
  FederSession._();

  static Future<void> save(SecretKey masterKey) async {
    stows.key.value = base64.encode(await masterKey.extractBytes());
  }

  static void clear() => stows.key.value = '';

  static bool get isUnlocked => stows.key.value.isNotEmpty;

  /// Wirft einen [StateError], wenn nicht entsperrt.
  static SecretKey get masterKey {
    final v = stows.key.value;
    if (v.isEmpty) throw StateError('Feder ist nicht entsperrt.');
    return SecretKey(base64.decode(v));
  }
}
