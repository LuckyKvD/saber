import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/crypto/feder_crypto.dart';
import 'package:saber/data/crypto/feder_session.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';

enum _Mode { loading, loadFailed, unlock, create, showRecovery }

/// Verschlüsselungs-Schritt der Anmeldung (Feder-Krypto 1).
///
/// - Neuer Tresor: Passwort festlegen -> Wiederherstellungsschlüssel anzeigen
///   -> erst nach Bestätigung wird der Tresor hochgeladen.
/// - Vorhandener Tresor: Passwort oder Wiederherstellungsschlüssel eingeben.
class EncLoginStep extends HookWidget {
  const new({super.key, required this.recheckCurrentStep});

  final void Function() recheckCurrentStep;

  static const width = 400.0;
  static const minPasswordLength = 12;

  static final log = Logger('EncLoginStep');

  @override
  Widget build(BuildContext context) {
    final mode = useState(_Mode.loading);
    final vault = useState<Map<String, dynamic>?>(null);
    final pending = useState<VaultCreation?>(null);
    final busy = useState(false);
    final error = useState('');
    final useRecovery = useState(false);
    final saved = useState(false);
    final hidePw = useState(true);

    final pw1 = useTextEditingController();
    final pw2 = useTextEditingController();
    final recoveryInput = useTextEditingController();

    Future<void> loadVault() async {
      mode.value = _Mode.loading;
      error.value = '';
      try {
        final client = NextcloudClientExtension.fromNextcloudCredentials();
        if (client == null) throw StateError('Nicht bei Nextcloud angemeldet.');
        final v = await client.getVault();
        vault.value = v;
        mode.value = v == null ? _Mode.create : _Mode.unlock;
      } catch (e, st) {
        log.warning('Tresor konnte nicht geladen werden: $e', e, st);
        error.value = 'Verbindung zu Nextcloud fehlgeschlagen:\n$e';
        mode.value = _Mode.loadFailed;
      }
    }

    useEffect(() {
      loadVault();
      return null;
    }, const []);

    Future<void> finishWith(SecretKey masterKey) async {
      await FederSession.save(masterKey);
      SaberSyncInterface.clearPathCaches();
      recheckCurrentStep();
    }

    Future<void> unlock() async {
      busy.value = true;
      error.value = '';
      try {
        final SecretKey key;
        if (useRecovery.value) {
          key = await FederCrypto.unlockWithRecoveryKey(
            vault.value!,
            recoveryInput.text,
          );
        } else {
          key = await FederCrypto.unlockWithPassword(vault.value!, pw1.text);
        }
        await finishWith(key);
      } on FederCryptoException catch (e) {
        error.value = e.message;
      } catch (e, st) {
        log.severe('Entsperren fehlgeschlagen: $e', e, st);
        error.value = 'Fehler: $e';
      } finally {
        busy.value = false;
      }
    }

    Future<void> create() async {
      error.value = '';
      if (pw1.text.length < minPasswordLength) {
        error.value =
            'Das Passwort braucht mindestens $minPasswordLength Zeichen.';
        return;
      }
      if (pw1.text != pw2.text) {
        error.value = 'Die beiden Passwörter sind nicht gleich.';
        return;
      }
      busy.value = true;
      try {
        pending.value = await FederCrypto.createVault(pw1.text);
        mode.value = _Mode.showRecovery;
      } catch (e, st) {
        log.severe('Tresor erstellen fehlgeschlagen: $e', e, st);
        error.value = 'Fehler: $e';
      } finally {
        busy.value = false;
      }
    }

    Future<void> confirmRecovery() async {
      busy.value = true;
      error.value = '';
      try {
        final client = NextcloudClientExtension.fromNextcloudCredentials()!;
        // Falls inzwischen ein anderes Gerät einen Tresor angelegt hat:
        final existing = await client.getVault();
        if (existing != null) {
          vault.value = existing;
          pending.value = null;
          mode.value = _Mode.unlock;
          error.value =
              'Auf dem Server gibt es inzwischen schon einen Tresor. '
              'Bitte mit dessen Passwort entsperren.';
          return;
        }
        await client.putVault(pending.value!.vault);
        await finishWith(pending.value!.masterKey);
      } catch (e, st) {
        log.severe('Tresor hochladen fehlgeschlagen: $e', e, st);
        error.value = 'Hochladen fehlgeschlagen:\n$e';
      } finally {
        busy.value = false;
      }
    }

    final colorScheme = ColorScheme.of(context);
    final textTheme = TextTheme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final horizontalPadding = screenWidth > width
        ? (screenWidth - width) / 2
        : 16.0;

    Widget errorText() => error.value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const .only(top: 8, bottom: 8),
            child: Text(
              error.value,
              style: TextStyle(color: colorScheme.error),
            ),
          );

    Widget passwordField(TextEditingController c, String label) => TextField(
      controller: c,
      obscureText: hidePw.value,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(hidePw.value ? Icons.visibility : Icons.visibility_off),
          onPressed: () => hidePw.value = !hidePw.value,
        ),
      ),
    );

    final children = <Widget>[
      const SizedBox(height: 16),
      Text('Hallo ${stows.username.value}', style: textTheme.headlineSmall),
      Text.rich(
        TextSpan(
          text: 'Nicht du? ',
          children: [
            TextSpan(
              text: 'Abmelden',
              style: const TextStyle(decoration: TextDecoration.underline),
              recognizer: _tap(() {
                stows.url.value = '';
                stows.username.value = '';
                stows.ncPassword.value = '';
                recheckCurrentStep();
              }),
            ),
          ],
        ),
      ),
      const SizedBox(height: 32),
    ];

    switch (mode.value) {
      case _Mode.loading:
        children.add(const Center(child: CircularProgressIndicator()));
      case _Mode.loadFailed:
        children
          ..add(errorText())
          ..add(
            ElevatedButton(
              onPressed: loadVault,
              child: const Text('Erneut versuchen'),
            ),
          );
      case _Mode.unlock:
        children
          ..add(Text('Feder entsperren', style: textTheme.headlineSmall))
          ..add(const SizedBox(height: 4))
          ..add(
            const Text(
              'Gib das Verschlüsselungspasswort ein, das du beim Einrichten '
              'festgelegt hast.',
            ),
          )
          ..add(const SizedBox(height: 16))
          ..add(
            useRecovery.value
                ? TextField(
                    controller: recoveryInput,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Wiederherstellungsschlüssel',
                    ),
                  )
                : passwordField(pw1, 'Verschlüsselungspasswort'),
          )
          ..add(errorText())
          ..add(
            ElevatedButton(
              onPressed: busy.value ? null : unlock,
              child: busy.value
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Entsperren'),
            ),
          )
          ..add(
            TextButton(
              onPressed: () {
                useRecovery.value = !useRecovery.value;
                error.value = '';
              },
              child: Text(
                useRecovery.value
                    ? 'Stattdessen Passwort eingeben'
                    : 'Passwort vergessen? Wiederherstellungsschlüssel verwenden',
              ),
            ),
          );
      case _Mode.create:
        children
          ..add(
            Text('Verschlüsselung einrichten', style: textTheme.headlineSmall),
          )
          ..add(const SizedBox(height: 4))
          ..add(
            const Text(
              'Deine Notizen werden verschlüsselt, bevor sie dein Gerät '
              'verlassen. Der Server sieht nur unlesbare Daten. '
              'Wähle eine lange Passphrase (mehrere Wörter), mindestens '
              '$minPasswordLength Zeichen. Es gibt keinen Weg, das Passwort '
              'zurückzusetzen, außer mit dem Wiederherstellungsschlüssel, '
              'den du im nächsten Schritt bekommst.',
            ),
          )
          ..add(const SizedBox(height: 16))
          ..add(passwordField(pw1, 'Neues Verschlüsselungspasswort'))
          ..add(const SizedBox(height: 8))
          ..add(passwordField(pw2, 'Passwort wiederholen'))
          ..add(errorText())
          ..add(
            ElevatedButton(
              onPressed: busy.value ? null : create,
              child: busy.value
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Weiter'),
            ),
          );
      case _Mode.showRecovery:
        final key = pending.value!.recoveryKey;
        children
          ..add(
            Text('Wiederherstellungsschlüssel', style: textTheme.headlineSmall),
          )
          ..add(const SizedBox(height: 4))
          ..add(
            const Text(
              'Schreib diesen Schlüssel auf oder drucke ihn aus und bewahre '
              'ihn getrennt vom Tablet auf (zum Beispiel im Safe). Wenn du '
              'das Passwort vergisst, kommst du nur mit diesem Schlüssel '
              'wieder an deine Notizen. Er wird nur jetzt angezeigt. '
              'Mach kein Foto davon in einer Cloud, die mit diesem Konto '
              'verbunden ist.',
            ),
          )
          ..add(const SizedBox(height: 16))
          ..add(
            Container(
              padding: const .all(12),
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                key,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  height: 1.5,
                ),
              ),
            ),
          )
          ..add(
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('In die Zwischenablage kopieren'),
              onPressed: () => Clipboard.setData(ClipboardData(text: key)),
            ),
          )
          ..add(
            CheckboxListTile(
              value: saved.value,
              onChanged: (v) => saved.value = v ?? false,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Ich habe den Schlüssel sicher aufgeschrieben.',
              ),
            ),
          )
          ..add(errorText())
          ..add(
            ElevatedButton(
              onPressed: (saved.value && !busy.value) ? confirmRecovery : null,
              child: busy.value
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Verschlüsselung aktivieren'),
            ),
          );
    }

    return MediaQuery.removeViewPadding(
      context: context,
      child: ListView(
        padding: .only(
          top: max(16, viewPadding.top),
          bottom: max(16, viewPadding.bottom),
          left: max(horizontalPadding, viewPadding.left),
          right: max(horizontalPadding, viewPadding.right),
        ),
        children: children,
      ),
    );
  }

  static TapGestureRecognizer _tap(void Function() onTap) =>
      TapGestureRecognizer()..onTap = onTap;
}
