import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/io_client.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:nextcloud/webdav.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/version.dart';

extension NextcloudClientExtension on NextcloudClient {
  /// Nur noch als Platzhalter für alte Code-Pfade. Feder hat KEINEN
  /// voreingestellten Server (der Saber-Server gehört dem Saber-Projekt).
  static final Uri defaultNextcloudUri = Uri.parse(
    'https://nc.saber.adil.hanney.org',
  );

  static final userAgent =
      'Feder/$buildName '
      '(${Platform.operatingSystem}) '
      'Dart/${Platform.version.split(' ').first}';
  static IOClient newHttpClient() =>
      IOClient(HttpClient()..userAgent = userAgent);

  /// Eigener Ordner von Feder auf dem Server. Der Saber-Ordner (`Saber`)
  /// wird von Feder nie gelesen oder geschrieben.
  static const String appRootDirectoryPrefix = 'Feder';

  static const vaultFileName = 'feder-vault.json';
  static final vaultFileUri = PathUri.parse(
    '$appRootDirectoryPrefix/$vaultFileName',
  );

  static const _utf8Decoder = Utf8Decoder(allowMalformed: true);

  static NextcloudClient? withSavedDetails() {
    if (!stows.loggedIn) return null;
    return _fromSavedCredentials();
  }

  /// Wie [withSavedDetails], aber auch während der Anmeldung (noch ohne
  /// Hauptschlüssel) nutzbar.
  static NextcloudClient? fromNextcloudCredentials() {
    if (stows.username.value.isEmpty || stows.ncPassword.value.isEmpty) {
      return null;
    }
    return _fromSavedCredentials();
  }

  static NextcloudClient _fromSavedCredentials() {
    final url = stows.url.value;
    final username = stows.username.value;
    final ncPassword = stows.ncPassword.value;

    final client = NextcloudClient(
      url.isNotEmpty ? Uri.parse(url) : defaultNextcloudUri,
      loginName: username,
      password: ncPassword,
      appPassword: ncPassword,
      httpClient: NextcloudClientExtension.newHttpClient(),
    );

    void deAuth() {
      // Logout if the username changes
      if (stows.username.value == username) return;
      stows.username.removeListener(deAuth);
      client.authentications?.clear();
    }

    stows.username.addListener(deAuth);

    return client;
  }

  /// Lädt den Tresor (eingepackter Hauptschlüssel) vom Server.
  /// `null`, wenn es noch keinen gibt.
  Future<Map<String, dynamic>?> getVault() async {
    try {
      final bytes = await webdav.get(vaultFileUri);
      return jsonDecode(_utf8Decoder.convert(bytes)) as Map<String, dynamic>;
    } on DynamiteStatusCodeException catch (e) {
      if (e.statusCode == HttpStatus.notFound) return null;
      rethrow;
    }
  }

  /// Legt den Feder-Ordner an (falls nötig) und speichert den Tresor.
  Future<void> putVault(Map<String, dynamic> vault) async {
    try {
      await webdav.mkcol(PathUri.parse(appRootDirectoryPrefix));
    } on DynamiteStatusCodeException catch (e) {
      if (e.statusCode != HttpStatus.methodNotAllowed) rethrow;
    }
    await webdav.put(
      Uint8List.fromList(utf8.encode(jsonEncode(vault))),
      vaultFileUri,
    );
  }
}
