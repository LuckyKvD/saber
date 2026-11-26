import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tasks/due_date_parser.dart';
import 'package:saber/data/tasks/nextcloud_tasks.dart';

/// Feder: Bestätigungsfenster "Als Aufgabe": erkannten Text korrigieren,
/// Liste wählen, Fälligkeit festlegen, Bild anhängen, an Nextcloud senden.
/// Gibt `true` zurück, wenn die Aufgabe angelegt wurde.
Future<bool?> showCreateTaskDialog(
  BuildContext context, {
  required List<String> candidates,
  required Uint8List? image,
  String? problem,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _CreateTaskDialog(candidates: candidates, image: image, problem: problem),
  );
}

class _CreateTaskDialog extends StatefulWidget {
  const _CreateTaskDialog({
    required this.candidates,
    required this.image,
    required this.problem,
  });

  final List<String> candidates;
  final Uint8List? image;
  final String? problem;

  @override
  State<_CreateTaskDialog> createState() => _CreateTaskDialogState();
}

class _CreateTaskDialogState extends State<_CreateTaskDialog> {
  late final TextEditingController _text;
  List<TaskList>? _lists;
  String? _listError;
  TaskList? _list;

  DateTime? _due;
  bool _hasTime = false;
  bool _dueFromText = false;
  bool _attachImage = true;

  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: widget.candidates.isEmpty ? '' : widget.candidates.first,
    );
    _text.addListener(_onTextChanged);
    _guessDue();
    _loadLists();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Fälligkeit aus dem Text ableiten, solange Kay sie nicht selbst gewählt hat.
  void _guessDue() {
    final guess = DueDateParser.parse(_text.text, DateTime.now());
    if (guess == null) return;
    if (_due != null && !_dueFromText) return;
    _due = DateTime(
      guess.date.year,
      guess.date.month,
      guess.date.day,
      guess.hour ?? 0,
      guess.minute ?? 0,
    );
    _hasTime = guess.hasTime;
    _dueFromText = true;
  }

  void _onTextChanged() {
    setState(_guessDue);
  }

  Future<void> _loadLists() async {
    try {
      final lists = await NextcloudTasks.fetchLists();
      if (!mounted) return;
      setState(() {
        _lists = lists;
        final last = stows.taskLastList.value;
        _list = lists.cast<TaskList?>().firstWhere(
          (l) => l!.url.toString() == last,
          orElse: () => lists.length == 1 ? lists.first : null,
        );
        if (lists.isEmpty) {
          _listError = 'Keine Aufgabenliste gefunden. Lege in Nextcloud Tasks '
              'zuerst eine Liste an.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _listError = 'Listen nicht ladbar: $e');
    }
  }

  void _setDue(DateTime day) {
    setState(() {
      _due = DateTime(day.year, day.month, day.day, _due?.hour ?? 0,
          _due?.minute ?? 0);
      _dueFromText = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) _setDue(picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _due?.hour ?? 9, minute: _due?.minute ?? 0),
    );
    if (picked == null || _due == null) return;
    setState(() {
      _due = DateTime(_due!.year, _due!.month, _due!.day, picked.hour, picked.minute);
      _hasTime = true;
      _dueFromText = false;
    });
  }

  bool get _canSend =>
      !_sending &&
      _list != null &&
      _due != null &&
      _text.text.trim().isNotEmpty;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await NextcloudTasks.createTask(
        list: _list!,
        summary: _text.text.trim(),
        due: _due!,
        dueHasTime: _hasTime,
        image: _attachImage ? widget.image : null,
      );
      stows.taskLastList.value = _list!.url.toString();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '$e';
      });
    }
  }

  String _dueLabel() {
    final d = _due;
    if (d == null) return 'Fälligkeit wählen';
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${two(d.day)}.${two(d.month)}.${d.year}';
    return _hasTime ? '$date, ${two(d.hour)}:${two(d.minute)} Uhr' : date;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final alternatives = widget.candidates.skip(1).take(4).toList();
    final today = DateTime.now();

    return AlertDialog(
      title: const Text('Als Aufgabe an Nextcloud'),
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
                decoration: const InputDecoration(
                  labelText: 'Aufgabe (bitte prüfen und korrigieren)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (alternatives.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Andere Lesarten:',
                    style: Theme.of(context).textTheme.labelMedium),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final alt in alternatives)
                      ActionChip(
                        label: Text(alt),
                        onPressed: () => _text.text = alt,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (_lists == null && _listError == null)
                const LinearProgressIndicator()
              else if (_listError != null)
                Text(_listError!, style: TextStyle(color: colorScheme.error))
              else
                DropdownButtonFormField<TaskList>(
                  initialValue: _list,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Aufgabenliste',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Liste wählen'),
                  items: [
                    for (final l in _lists!)
                      DropdownMenuItem(value: l, child: Text(l.name)),
                  ],
                  onChanged: (l) => setState(() => _list = l),
                ),
              const SizedBox(height: 16),
              Text('Fällig', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ActionChip(
                    label: const Text('Heute'),
                    onPressed: () => _setDue(today),
                  ),
                  ActionChip(
                    label: const Text('Morgen'),
                    onPressed: () =>
                        _setDue(today.add(const Duration(days: 1))),
                  ),
                  ActionChip(
                    label: const Text('In einer Woche'),
                    onPressed: () =>
                        _setDue(today.add(const Duration(days: 7))),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(_dueLabel()),
              ),
              if (_due != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.schedule),
                      label: Text(_hasTime ? 'Uhrzeit ändern' : 'Uhrzeit hinzufügen'),
                    ),
                    if (_hasTime)
                      IconButton(
                        tooltip: 'Uhrzeit entfernen',
                        onPressed: () => setState(() {
                          _hasTime = false;
                          _dueFromText = false;
                        }),
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                if (_dueFromText)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Aus dem Text erkannt – bitte prüfen.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
              if (widget.image != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _attachImage,
                  onChanged: (v) => setState(() => _attachImage = v ?? true),
                  title: const Text('Handschrift als Bild anhängen'),
                  subtitle: const Text(
                    'Das Bild liegt unverschlüsselt in deiner Nextcloud '
                    '(Ordner „Feder-Aufgaben“).',
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
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
              : const Text('Aufgabe anlegen'),
        ),
      ],
    );
  }
}
