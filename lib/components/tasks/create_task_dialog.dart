import 'package:material_ui/material_ui.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tasks/contact_parser.dart';
import 'package:saber/data/tasks/due_date_parser.dart';
import 'package:saber/data/tasks/nextcloud_dav.dart';

/// Feder: Bestätigungsfenster für "An Nextcloud senden" (Aufgabe, Termin
/// oder Kontakt): erkannten Text korrigieren, Ziel wählen, Datum/Uhrzeit
/// festlegen. Gibt `true` zurück, wenn der Eintrag angelegt wurde.
Future<bool?> showSendToNextcloudDialog(
  BuildContext context, {
  required NcKind kind,
  required List<String> candidates,
  String? problem,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SendDialog(
      kind: kind,
      candidates: candidates,
      problem: problem,
    ),
  );
}

class _SendDialog extends StatefulWidget {
  const _SendDialog({
    required this.kind,
    required this.candidates,
    required this.problem,
  });

  final NcKind kind;
  final List<String> candidates;
  final String? problem;

  @override
  State<_SendDialog> createState() => _SendDialogState();
}

class _SendDialogState extends State<_SendDialog> {
  late final TextEditingController _text;
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _mail = TextEditingController();
  final _org = TextEditingController();

  List<DavCollection>? _collections;
  String? _collectionError;
  DavCollection? _target;

  /// Aufgabe: Fälligkeit; Termin: Beginn.
  DateTime? _when;
  bool _hasTime = false;
  bool _fromText = false;

  /// Nur Termin.
  bool _allDay = false;
  DateTime? _end;

  bool _sending = false;
  String? _error;

  NcKind get _kind => widget.kind;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.candidates.isEmpty ? '' : widget.candidates.first,
    );
    _text.addListener(_onTextChanged);
    _guess();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_text, _first, _last, _phone, _mail, _org]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTextChanged() => setState(_guess);

  /// Vorbelegung aus dem Text, solange Kay nichts selbst gewählt hat.
  void _guess() {
    if (_kind == NcKind.contact) {
      if (_contactEdited) return;
      final g = ContactParser.parse(_text.text);
      _first.text = g.firstName;
      _last.text = g.lastName;
      _phone.text = g.phone;
      _mail.text = g.email;
      return;
    }
    final guess = DueDateParser.parse(_text.text, DateTime.now());
    if (guess == null) return;
    if (_when != null && !_fromText) return;
    _when = DateTime(
      guess.date.year,
      guess.date.month,
      guess.date.day,
      guess.hour ?? 0,
      guess.minute ?? 0,
    );
    _hasTime = guess.hasTime;
    _fromText = true;
    if (_kind == NcKind.event) _end = null;
  }

  bool _contactEdited = false;

  String get _lastKey {
    switch (_kind) {
      case NcKind.task:
        return stows.taskLastList.value;
      case NcKind.event:
        return stows.eventLastCalendar.value;
      case NcKind.contact:
        return stows.contactLastBook.value;
    }
  }

  void _rememberTarget(String url) {
    switch (_kind) {
      case NcKind.task:
        stows.taskLastList.value = url;
      case NcKind.event:
        stows.eventLastCalendar.value = url;
      case NcKind.contact:
        stows.contactLastBook.value = url;
    }
  }

  Future<void> _load() async {
    try {
      final all = await NextcloudDav.fetchCollections(_kind);
      if (!mounted) return;
      setState(() {
        _collections = all;
        final last = _lastKey;
        _target = all.cast<DavCollection?>().firstWhere(
          (c) => c!.url.toString() == last,
          orElse: () => all.length == 1 ? all.first : null,
        );
        if (all.isEmpty) {
          _collectionError =
              'Kein(e) ${_kind.collectionLabel} gefunden. Lege in Nextcloud '
              'zuerst eines an.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _collectionError = '${_kind.collectionLabel} nicht ladbar: $e');
    }
  }

  void _setDay(DateTime day) {
    setState(() {
      _when = DateTime(
        day.year,
        day.month,
        day.day,
        _when?.hour ?? 0,
        _when?.minute ?? 0,
      );
      _fromText = false;
      _end = null;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _when ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) _setDay(picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _when?.hour ?? 9, minute: _when?.minute ?? 0),
    );
    if (picked == null || _when == null) return;
    setState(() {
      _when = DateTime(
        _when!.year,
        _when!.month,
        _when!.day,
        picked.hour,
        picked.minute,
      );
      _hasTime = true;
      _fromText = false;
      _end = null;
    });
  }

  DateTime get _effectiveEnd =>
      _end ?? _when!.add(const Duration(hours: 1));

  Future<void> _pickEnd() async {
    final e = _effectiveEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: e.hour, minute: e.minute),
    );
    if (picked == null || _when == null) return;
    var end = DateTime(
      _when!.year,
      _when!.month,
      _when!.day,
      picked.hour,
      picked.minute,
    );
    if (!end.isAfter(_when!)) end = end.add(const Duration(days: 1));
    setState(() => _end = end);
  }

  bool get _canSend {
    if (_sending || _target == null) return false;
    switch (_kind) {
      case NcKind.task:
        return _when != null && _text.text.trim().isNotEmpty;
      case NcKind.event:
        return _when != null &&
            (_allDay || _hasTime) &&
            _text.text.trim().isNotEmpty;
      case NcKind.contact:
        return _first.text.trim().isNotEmpty ||
            _last.text.trim().isNotEmpty ||
            _org.text.trim().isNotEmpty ||
            _phone.text.trim().isNotEmpty;
    }
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      switch (_kind) {
        case NcKind.task:
          await NextcloudDav.createTask(
            list: _target!,
            summary: _text.text.trim(),
            due: _when!,
            dueHasTime: _hasTime,
          );
        case NcKind.event:
          await NextcloudDav.createEvent(
            calendar: _target!,
            summary: _text.text.trim(),
            start: _when!,
            end: _allDay ? _when! : _effectiveEnd,
            allDay: _allDay,
          );
        case NcKind.contact:
          await NextcloudDav.createContact(
            book: _target!,
            firstName: _first.text,
            lastName: _last.text,
            phone: _phone.text,
            email: _mail.text,
            organization: _org.text,
          );
      }
      _rememberTarget(_target!.url.toString());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  String _dateLabel() {
    final d = _when;
    if (d == null) return 'Datum wählen';
    return '${_two(d.day)}.${_two(d.month)}.${d.year}';
  }

  String _timeLabel(DateTime d) => '${_two(d.hour)}:${_two(d.minute)} Uhr';

  Widget _field(TextEditingController c, String label, {TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: type,
        onChanged: (_) => setState(() => _contactEdited = true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  List<Widget> _contactFields() => [
    _field(_first, 'Vorname'),
    _field(_last, 'Nachname'),
    _field(_phone, 'Telefon', type: TextInputType.phone),
    _field(_mail, 'E-Mail', type: TextInputType.emailAddress),
    _field(_org, 'Firma (optional)'),
  ];

  List<Widget> _whenFields(BuildContext context) {
    final today = DateTime.now();
    final isEvent = _kind == NcKind.event;
    return [
      const SizedBox(height: 16),
      Text(
        isEvent ? 'Wann' : 'Fällig',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          ActionChip(label: const Text('Heute'), onPressed: () => _setDay(today)),
          ActionChip(
            label: const Text('Morgen'),
            onPressed: () => _setDay(today.add(const Duration(days: 1))),
          ),
          ActionChip(
            label: const Text('In einer Woche'),
            onPressed: () => _setDay(today.add(const Duration(days: 7))),
          ),
        ],
      ),
      const SizedBox(height: 6),
      OutlinedButton.icon(
        onPressed: _pickDate,
        icon: const Icon(Icons.event),
        label: Text(_dateLabel()),
      ),
      if (isEvent)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Ganztägig'),
          value: _allDay,
          onChanged: (v) => setState(() => _allDay = v),
        ),
      if (_when != null && !(isEvent && _allDay)) ...[
        const SizedBox(height: 6),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule),
              label: Text(
                _hasTime
                    ? (isEvent ? 'Beginn ${_timeLabel(_when!)}' : _timeLabel(_when!))
                    : (isEvent ? 'Beginn wählen' : 'Uhrzeit hinzufügen'),
              ),
            ),
            if (_hasTime && !isEvent)
              IconButton(
                tooltip: 'Uhrzeit entfernen',
                onPressed: () => setState(() {
                  _hasTime = false;
                  _fromText = false;
                }),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        if (isEvent && _hasTime) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _pickEnd,
            icon: const Icon(Icons.schedule_send),
            label: Text('Ende ${_timeLabel(_effectiveEnd)}'),
          ),
        ],
      ],
      if (_when != null && _fromText)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Aus dem Text erkannt – bitte prüfen.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final alternatives = widget.candidates.skip(1).take(4).toList();
    final isContact = _kind == NcKind.contact;

    return AlertDialog(
      title: Text('${_kind.label} an Nextcloud'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.problem != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.problem!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              TextField(
                controller: _text,
                minLines: 1,
                maxLines: 4,
                autofocus: widget.candidates.isEmpty,
                decoration: InputDecoration(
                  labelText: isContact
                      ? 'Erkannter Text (bitte prüfen)'
                      : '${_kind.label} (bitte prüfen und korrigieren)',
                  border: const OutlineInputBorder(),
                ),
              ),
              if (alternatives.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Andere Lesarten:',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final alt in alternatives)
                      ActionChip(
                        label: Text(alt),
                        onPressed: () {
                          _contactEdited = false;
                          _text.text = alt;
                        },
                      ),
                  ],
                ),
              ],
              if (isContact) ...[
                const SizedBox(height: 12),
                ..._contactFields(),
              ],
              const SizedBox(height: 8),
              if (_collections == null && _collectionError == null)
                const LinearProgressIndicator()
              else if (_collectionError != null)
                Text(_collectionError!, style: TextStyle(color: colorScheme.error))
              else
                DropdownButtonFormField<DavCollection>(
                  initialValue: _target,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _kind.collectionLabel,
                    border: const OutlineInputBorder(),
                  ),
                  hint: Text('${_kind.collectionLabel} wählen'),
                  items: [
                    for (final c in _collections!)
                      DropdownMenuItem(value: c, child: Text(c.name)),
                  ],
                  onChanged: (c) => setState(() => _target = c),
                ),
              if (!isContact) ..._whenFields(context),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: TextStyle(color: colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _canSend ? _send : null,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('${_kind.label} anlegen'),
        ),
      ],
    );
  }
}
