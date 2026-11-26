import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/prefs.dart';

class TaskList {
  const TaskList({required this.name, required this.url});

  final String name;

  /// Absolute Adresse der Aufgabenliste (CalDAV-Sammlung, endet mit `/`).
  final Uri url;
}

/// Feder: Legt Aufgaben (CalDAV VTODO) direkt auf dem eigenen Nextcloud-Server
/// an. Nichts läuft über Fremddienste.
abstract class NextcloudTasks {
  static final _log = Logger('NextcloudTasks');

  static String? notReadyReason() =>
      stows.loggedIn ? null : 'Du bist nicht bei Nextcloud angemeldet.';

  static Uri get _base => Uri.parse(stows.url.value);

  static Uri _davUri(String path) {
    final base = _base;
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$path', query: null);
  }

  static String get _authHeader =>
      'Basic ${base64Encode(utf8.encode('${stows.username.value}:${stows.ncPassword.value}'))}';

  /// Nutzerkennung für die DAV-Adresse (kann vom Anmeldenamen abweichen).
  static Future<String> _userId() async {
    try {
      final client = NextcloudClientExtension.withSavedDetails();
      if (client != null) return await client.getUsername();
    } catch (e) {
      _log.warning('Nutzerkennung nicht abrufbar, nehme Anmeldenamen: $e');
    }
    return stows.username.value;
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#039;', "'")
      .replaceAll('&amp;', '&');

  /// Alle Aufgabenlisten (Kalender, die Aufgaben erlauben).
  static Future<List<TaskList>> fetchLists() async {
    final reason = notReadyReason();
    if (reason != null) throw StateError(reason);
    final userId = await _userId();
    final uri = _davUri('/remote.php/dav/calendars/$userId/');
    final client = NextcloudClientExtension.newHttpClient();
    try {
      final request = http.Request('PROPFIND', uri)
        ..headers.addAll({
          'Authorization': _authHeader,
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body =
            '<?xml version="1.0" encoding="utf-8"?>'
            '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
            '<d:prop><d:displayname/><d:resourcetype/>'
            '<c:supported-calendar-component-set/></d:prop></d:propfind>';
      final response = await http.Response.fromStream(await client.send(request));
      if (response.statusCode != 207) {
        throw StateError(
          'Aufgabenlisten nicht abrufbar (Status ${response.statusCode}).',
        );
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final lists = <TaskList>[];
      final blocks = RegExp(
        r'<(?:\w+:)?response\b[\s\S]*?</(?:\w+:)?response>',
      ).allMatches(body);
      for (final block in blocks) {
        final xml = block.group(0)!;
        if (!RegExp(r'name="VTODO"').hasMatch(xml)) continue;
        final href = RegExp(
          r'<(?:\w+:)?href>([\s\S]*?)</(?:\w+:)?href>',
        ).firstMatch(xml)?.group(1);
        if (href == null) continue;
        if (href.contains('trashbin')) continue;
        final name = RegExp(
          r'<(?:\w+:)?displayname>([\s\S]*?)</(?:\w+:)?displayname>',
        ).firstMatch(xml)?.group(1);
        final listUri = _base.replace(
          path: href.endsWith('/') ? href : '$href/',
          query: null,
        );
        lists.add(
          TaskList(
            name: _unescape(name?.trim().isNotEmpty == true ? name!.trim() : href),
            url: listUri,
          ),
        );
      }
      return lists;
    } finally {
      client.close();
    }
  }

  static String _icsText(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\r\n', r'\n')
      .replaceAll('\n', r'\n');

  static String _stamp(DateTime utc) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
        'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }

  static String _newUid() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Legt die Aufgabe an.
  static Future<void> createTask({
    required TaskList list,
    required String summary,
    required DateTime due,
    required bool dueHasTime,
  }) async {
    final uid = _newUid();

    String two(int n) => n.toString().padLeft(2, '0');
    final dateStr = '${due.year.toString().padLeft(4, '0')}${two(due.month)}${two(due.day)}';
    final dueLine = dueHasTime
        ? 'DUE:${dateStr}T${two(due.hour)}${two(due.minute)}00'
        : 'DUE;VALUE=DATE:$dateStr';

    final now = _stamp(DateTime.now().toUtc());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Feder//Aufgaben//DE',
      'BEGIN:VTODO',
      'UID:$uid',
      'DTSTAMP:$now',
      'CREATED:$now',
      'LAST-MODIFIED:$now',
      'SUMMARY:${_icsText(summary)}',
      dueLine,
      'STATUS:NEEDS-ACTION',
      'END:VTODO',
      'END:VCALENDAR',
    ];

    final client = NextcloudClientExtension.newHttpClient();
    try {
      final request = http.Request('PUT', list.url.resolve('$uid.ics'))
        ..headers.addAll({
          'Authorization': _authHeader,
          'Content-Type': 'text/calendar; charset=utf-8',
          'If-None-Match': '*',
        })
        ..body = '${lines.join('\r\n')}\r\n';
      final response = await http.Response.fromStream(await client.send(request));
      if (response.statusCode != 201 && response.statusCode != 204) {
        _log.warning('Aufgabe abgelehnt: Status ${response.statusCode}');
        throw StateError(
          'Nextcloud hat die Aufgabe abgelehnt (Status ${response.statusCode}).',
        );
      }
    } finally {
      client.close();
    }
  }
}
