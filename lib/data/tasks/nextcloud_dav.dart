import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/prefs.dart';

/// Was aus einer Handschrift-Auswahl in Nextcloud entstehen kann.
enum NcKind {
  task('Aufgabe', 'Aufgabenliste'),
  event('Termin', 'Kalender'),
  contact('Kontakt', 'Adressbuch');

  const NcKind(this.label, this.collectionLabel);
  final String label;
  final String collectionLabel;
}

/// Eine Sammlung auf dem Server: Aufgabenliste, Kalender oder Adressbuch.
class DavCollection {
  const DavCollection({required this.name, required this.url});

  final String name;

  /// Absolute Adresse (CalDAV-/CardDAV-Sammlung, endet mit `/`).
  final Uri url;
}

/// Feder: Legt Aufgaben (VTODO), Termine (VEVENT) und Kontakte (vCard)
/// direkt auf dem eigenen Nextcloud-Server an. Nichts läuft über Fremddienste.
abstract class NextcloudDav {
  static final _log = Logger('NextcloudDav');

  static String? notReadyReason() =>
      stows.loggedIn ? null : 'Du bist nicht bei Nextcloud angemeldet.';

  static Uri get _base => Uri.parse(stows.url.value);

  static Uri _davUri(String path) {
    final base = _base;
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath$path');
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

  /// Alle Sammlungen der gewünschten Art (Aufgabenlisten, Kalender, Adressbücher).
  static Future<List<DavCollection>> fetchCollections(NcKind kind) async {
    final reason = notReadyReason();
    if (reason != null) throw StateError(reason);
    final userId = await _userId();
    final isBook = kind == NcKind.contact;
    final uri = _davUri(
      isBook
          ? '/remote.php/dav/addressbooks/users/$userId/'
          : '/remote.php/dav/calendars/$userId/',
    );
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
      final response = await http.Response.fromStream(
        await client.send(request),
      );
      if (response.statusCode != 207) {
        throw StateError(
          '${kind.collectionLabel}n nicht abrufbar (Status ${response.statusCode}).',
        );
      }
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final result = <DavCollection>[];
      final blocks = RegExp(
        r'<(?:\w+:)?response\b[\s\S]*?</(?:\w+:)?response>',
      ).allMatches(body);
      for (final block in blocks) {
        final xml = block.group(0)!;
        final bool matches;
        switch (kind) {
          case NcKind.task:
            matches = xml.contains('name="VTODO"');
          case NcKind.event:
            matches = xml.contains('name="VEVENT"');
          case NcKind.contact:
            matches = RegExp(r'<(?:\w+:)?addressbook\s*/>').hasMatch(xml);
        }
        if (!matches) continue;
        final href = RegExp(
          r'<(?:\w+:)?href>([\s\S]*?)</(?:\w+:)?href>',
        ).firstMatch(xml)?.group(1);
        if (href == null) continue;
        // Papierkorb und automatisch erzeugte Sammlungen (Geburtstage,
        // "Zuletzt kontaktiert") sind nicht beschreibbar bzw. nicht gewünscht.
        if (href.contains('trashbin') ||
            href.contains('contact_birthdays') ||
            href.contains('z-app-generated')) {
          continue;
        }
        final name = RegExp(
          r'<(?:\w+:)?displayname>([\s\S]*?)</(?:\w+:)?displayname>',
        ).firstMatch(xml)?.group(1);
        result.add(
          DavCollection(
            name: _unescape(
              name?.trim().isNotEmpty == true ? name!.trim() : href,
            ),
            url: _base.replace(path: href.endsWith('/') ? href : '$href/'),
          ),
        );
      }
      return result;
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

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';

  /// UTC-Zeitstempel `20261203T130000Z`.
  static String _stamp(DateTime utc) =>
      '${_dateStr(utc)}T${_two(utc.hour)}${_two(utc.minute)}${_two(utc.second)}Z';

  static String _newUid() {
    final r = Random.secure();
    return List.generate(
      16,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static Future<void> _put(
    Uri url,
    String contentType,
    String body,
    String what,
  ) async {
    final client = NextcloudClientExtension.newHttpClient();
    try {
      final request = http.Request('PUT', url)
        ..headers.addAll({
          'Authorization': _authHeader,
          'Content-Type': contentType,
          'If-None-Match': '*',
        })
        ..body = body;
      final response = await http.Response.fromStream(
        await client.send(request),
      );
      if (response.statusCode != 201 && response.statusCode != 204) {
        _log.warning('$what abgelehnt: Status ${response.statusCode}');
        throw StateError(
          'Nextcloud hat $what abgelehnt (Status ${response.statusCode}).',
        );
      }
    } finally {
      client.close();
    }
  }

  static String _calendar(List<String> component) => [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Feder//Nextcloud//DE',
    ...component,
    'END:VCALENDAR',
  ].join('\r\n') + '\r\n';

  /// Legt eine Aufgabe an. [due] mit Uhrzeit nur, wenn [dueHasTime].
  static Future<void> createTask({
    required DavCollection list,
    required String summary,
    required DateTime due,
    required bool dueHasTime,
  }) async {
    final uid = _newUid();
    final now = _stamp(DateTime.now().toUtc());
    final dueLine = dueHasTime
        ? 'DUE:${_dateStr(due)}T${_two(due.hour)}${_two(due.minute)}00'
        : 'DUE;VALUE=DATE:${_dateStr(due)}';
    final ics = _calendar([
      'BEGIN:VTODO',
      'UID:$uid',
      'DTSTAMP:$now',
      'CREATED:$now',
      'LAST-MODIFIED:$now',
      'SUMMARY:${_icsText(summary)}',
      dueLine,
      'STATUS:NEEDS-ACTION',
      'END:VTODO',
    ]);
    await _put(
      list.url.resolve('$uid.ics'),
      'text/calendar; charset=utf-8',
      ics,
      'die Aufgabe',
    );
  }

  /// Legt einen Termin an. Ganztägig: nur Datum. Sonst [start] bis [end]
  /// (Ortszeit des Geräts, wird als UTC gespeichert).
  static Future<void> createEvent({
    required DavCollection calendar,
    required String summary,
    required DateTime start,
    required DateTime end,
    required bool allDay,
  }) async {
    final uid = _newUid();
    final now = _stamp(DateTime.now().toUtc());
    final String startLine;
    final String endLine;
    if (allDay) {
      final day = DateTime(start.year, start.month, start.day);
      final next = DateTime(day.year, day.month, day.day + 1);
      startLine = 'DTSTART;VALUE=DATE:${_dateStr(day)}';
      endLine = 'DTEND;VALUE=DATE:${_dateStr(next)}';
    } else {
      startLine = 'DTSTART:${_stamp(start.toUtc())}';
      endLine = 'DTEND:${_stamp(end.toUtc())}';
    }
    final ics = _calendar([
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTAMP:$now',
      'CREATED:$now',
      'LAST-MODIFIED:$now',
      'SUMMARY:${_icsText(summary)}',
      startLine,
      endLine,
      'TRANSP:OPAQUE',
      'STATUS:CONFIRMED',
      'END:VEVENT',
    ]);
    await _put(
      calendar.url.resolve('$uid.ics'),
      'text/calendar; charset=utf-8',
      ics,
      'den Termin',
    );
  }

  static String _vcardText(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');

  /// Legt einen Kontakt (vCard 3.0) an.
  static Future<void> createContact({
    required DavCollection book,
    required String firstName,
    required String lastName,
    String phone = '',
    String email = '',
    String organization = '',
    String note = '',
  }) async {
    final uid = _newUid();
    final fullName = [firstName, lastName]
        .where((s) => s.trim().isNotEmpty)
        .join(' ')
        .trim();
    final display = fullName.isNotEmpty
        ? fullName
        : (organization.trim().isNotEmpty ? organization.trim() : phone.trim());
    final lines = <String>[
      'BEGIN:VCARD',
      'VERSION:3.0',
      'PRODID:-//Feder//Nextcloud//DE',
      'UID:$uid',
      'FN:${_vcardText(display)}',
      'N:${_vcardText(lastName.trim())};${_vcardText(firstName.trim())};;;',
      if (organization.trim().isNotEmpty)
        'ORG:${_vcardText(organization.trim())}',
      if (phone.trim().isNotEmpty) 'TEL;TYPE=CELL:${_vcardText(phone.trim())}',
      if (email.trim().isNotEmpty)
        'EMAIL;TYPE=INTERNET:${_vcardText(email.trim())}',
      if (note.trim().isNotEmpty) 'NOTE:${_vcardText(note.trim())}',
      'REV:${_stamp(DateTime.now().toUtc())}',
      'END:VCARD',
    ];
    await _put(
      book.url.resolve('$uid.vcf'),
      'text/vcard; charset=utf-8',
      '${lines.join('\r\n')}\r\n',
      'den Kontakt',
    );
  }
}
