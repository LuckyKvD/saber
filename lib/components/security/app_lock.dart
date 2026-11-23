import 'dart:async';

import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/prefs.dart';

/// Sperrt Feder per Biometrie oder Geräte-PIN.
///
/// - Kaltstart: gesperrt, wenn die Sperre aktiviert ist.
/// - Hintergrund: gesperrt, wenn die App länger als [gracePeriod] im
///   Hintergrund war.
/// - Solange gesperrt, wird der Inhalt nicht gezeichnet ([Offstage]).
/// - Android: `FLAG_SECURE` verbirgt den Inhalt in der App-Übersicht und
///   sperrt Bildschirmfotos (solange die Sperre aktiv ist).
///
/// Ist auf dem Gerät keine Bildschirmsperre eingerichtet, kann nicht
/// authentifiziert werden. Dann wird nicht gesperrt (sonst wäre man
/// ausgesperrt) und das Aktivieren der Sperre wird abgelehnt.
class AppLock extends StatefulWidget {
  const new({super.key, required this.child});

  final Widget child;

  static const gracePeriod = Duration(seconds: 30);

  static final _log = Logger('AppLock');
  static final _auth = LocalAuthentication();
  static const _secureChannel = MethodChannel('de.luckykvd.feder/secure');

  /// Ob das Gerät Biometrie oder eine Geräte-PIN/-Muster/-Passwort hat.
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (e) {
      _log.warning('isDeviceSupported failed', e);
      return false;
    }
  }

  /// Fragt den Nutzer. Gibt `false` bei Abbruch oder Fehler zurück.
  static Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      _log.info('authenticate failed or cancelled', e);
      return false;
    }
  }

  static Future<void> _setSecure(bool secure) async {
    try {
      await _secureChannel.invokeMethod<void>('setSecure', secure);
    } catch (e) {
      _log.warning('setSecure failed', e);
    }
  }

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  var _locked = false;
  var _authenticating = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    stows.appLockEnabled.addListener(_onPrefChanged);
    unawaited(AppLock._setSecure(stows.appLockEnabled.value));
    if (stows.appLockEnabled.value) {
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _prompt());
    }
  }

  @override
  void dispose() {
    stows.appLockEnabled.removeListener(_onPrefChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onPrefChanged() {
    final enabled = stows.appLockEnabled.value;
    unawaited(AppLock._setSecure(enabled));
    if (!enabled && _locked) {
      setState(() => _locked = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!stows.appLockEnabled.value) return;
    // Der Dialog der Biometrie selbst löst Lifecycle-Wechsel aus.
    if (_authenticating) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null &&
            DateTime.now().difference(since) > AppLock.gracePeriod) {
          unawaited(_lockAndPrompt());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _lockAndPrompt() async {
    // Ohne Bildschirmsperre kann niemand entsperren: nicht aussperren.
    if (!await AppLock.isAvailable()) return;
    if (!mounted) return;
    setState(() => _locked = true);
    await _prompt();
  }

  Future<void> _prompt() async {
    if (_authenticating || !mounted) return;
    if (!await AppLock.isAvailable()) {
      if (mounted) setState(() => _locked = false);
      return;
    }
    _authenticating = true;
    try {
      final ok = await AppLock.authenticate('Feder entsperren');
      if (ok && mounted) setState(() => _locked = false);
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Offstage(offstage: _locked, child: widget.child),
        if (_locked) Positioned.fill(child: _LockScreen(onUnlock: _prompt)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const new({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Feder ist gesperrt', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Entsperren'),
            ),
          ],
        ),
      ),
    );
  }
}
