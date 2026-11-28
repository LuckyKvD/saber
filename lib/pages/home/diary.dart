import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/diary.dart';
import 'package:saber/data/file_manager/decrypted_file_image.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/pages/editor/editor.dart';
import 'package:saber/pages/home/diary_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Feder-Tagebuch: Kalender mit einem handschriftlichen Notizbuch pro Tag.
class DiaryPage extends StatefulWidget {
  const new({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  static const _months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];
  static const _weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];

  late DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  List<String> entries = []; // Pfade ohne Endung
  List<String> strays = [];
  Map<String, DiaryLocation?> locations = {};
  StreamSubscription<FileOperation>? _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = FileManager.fileWriteStream.stream.listen((event) {
      if (event.filePath.startsWith(Diary.root)) _reload();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Set<int> get days => {
    for (final e in entries) ?Diary.dayFromName(Diary.baseName(e))?.day,
  };

  Future<void> _reload() async {
    final shown = month;
    final found = await Diary.entriesInMonth(shown.year, shown.month);
    final locs = <String, DiaryLocation?>{};
    for (final e in found) {
      locs[e] = await Diary.readLocation(e);
    }
    final stray = await Diary.strayEntries();
    if (!mounted || shown != month) return;
    setState(() {
      strays = stray;
      entries = found;
      locations = locs;
    });
  }

  void _shift(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
      entries = [];
      locations = {};
    });
    _reload();
  }

  Future<void> _jump() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: month,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
      helpText: 'Monat wählen',
    );
    if (picked == null) return;
    setState(() {
      month = DateTime(picked.year, picked.month);
      entries = [];
      locations = {};
    });
    _reload();
  }

  List<String> _entriesOf(DateTime day) => [
    for (final e in entries)
      if (Diary.dayFromName(Diary.baseName(e)) == day) e,
  ];

  /// Tag antippen: kein Eintrag = neuer Eintrag, einer = öffnen, mehrere =
  /// Auswahl.
  Future<void> _openDay(DateTime day) async {
    final list = _entriesOf(day);
    if (list.isEmpty) return _openNew(day);
    if (list.length == 1) return _openEntry(list.first);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in list)
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: Text(Diary.baseName(e)),
                onTap: () => Navigator.of(sheetContext).pop(e),
              ),
          ],
        ),
      ),
    );
    if (choice != null) await _openEntry(choice);
  }

  Future<void> _openEntry(String path) async {
    await context.push(RoutePaths.editFilePath(path));
    if (mounted) _reload();
  }

  Future<void> _openNew(DateTime day) async {
    final path = Diary.pathFor(day);
    // Ort nur für heute: beim Nachtragen wäre er falsch.
    final Future<DiaryLocation?>? location = Diary.isToday(day)
        ? Diary.captureLocation()
        : null;
    await context.push(RoutePaths.editFilePath(path));
    if (location != null &&
        FileManager.doesFileExist('$path${Editor.extension}')) {
      final loc = await location;
      if (loc != null) await Diary.saveLocation(path, loc);
    }
    if (mounted) _reload();
  }

  Future<void> _entryMenu(String path) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                Diary.baseName(path),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Beschriftung ändern'),
              onTap: () => Navigator.of(sheetContext).pop('label'),
            ),
            ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Auf anderes Datum verschieben'),
              onTap: () => Navigator.of(sheetContext).pop('date'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever),
              title: const Text('Eintrag löschen'),
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final parsed = Diary.parseName(Diary.baseName(path));
    switch (choice) {
      case 'label':
        final text = await _askText(
          'Beschriftung',
          (parsed?.rest ?? '').trim(),
        );
        if (text == null || parsed == null) return;
        final rest = text.trim().isEmpty ? '' : ' ${text.trim()}';
        if (FileManager.validateFilename(Diary.baseName(Diary.pathForNamed(parsed.day, rest))) != null) {
          _snack('Diese Beschriftung enthält ungültige Zeichen.');
          return;
        }
        await Diary.moveEntry(path, parsed.day, rest);
      case 'date':
        final picked = await showDatePicker(
          context: context,
          initialDate: parsed?.day ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(DateTime.now().year + 5),
          helpText: 'Neues Datum',
        );
        if (picked == null) return;
        await Diary.moveEntry(
          path,
          DateTime(picked.year, picked.month, picked.day),
          parsed?.rest ?? '',
        );
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Eintrag löschen?'),
            content: Text(
              '„${Diary.baseName(path)}“ wird samt Bildern und Ort gelöscht. '
              'Das lässt sich nicht rückgängig machen (außer über eine '
              'Sicherung).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Abbrechen'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Löschen'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await Diary.deleteEntry(path);
    }
    if (mounted) _reload();
  }

  Future<String?> _askText(String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _snack(String text) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = DateTime.now();
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mo
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = firstWeekday - 1 + daysInMonth;
    final rows = (cells / 7).ceil();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            _openDay(DateTime(today.year, today.month, today.day)),
        icon: const Icon(Icons.edit),
        label: const Text('Heute schreiben'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.public),
                label: const Text('Karte'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const DiaryMapPage()),
                ),
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Vorheriger Monat',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _jump,
                    child: Text(
                      '${_months[month.month - 1]} ${month.year}',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Nächster Monat',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shift(1),
                ),
              ],
            ),
            Row(
              children: [
                for (final w in _weekdays)
                  Expanded(
                    child: Center(
                      child: Text(w, style: theme.textTheme.labelMedium),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var r = 0; r < rows; r++)
              Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(
                      child: _cell(
                        r * 7 + c - (firstWeekday - 1) + 1,
                        daysInMonth,
                        today,
                        cs,
                      ),
                    ),
                ],
              ),
            const Divider(height: 24),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Keine Einträge in diesem Monat')),
              ),
            for (final e in entries.reversed) _entryTile(e),
            if (strays.isNotEmpty) ...[
              const Divider(height: 24),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Einträge ohne Datum im Namen (Titel auf TT.MM.JJJJ setzen, '
                  'dann landen sie im Kalender)',
                ),
              ),
              for (final path in strays)
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: Text(path.substring(path.lastIndexOf('/') + 1)),
                  subtitle: Text(path.substring(1)),
                  onTap: () => _openEntry(path),
                  onLongPress: () => _entryMenu(path),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(int day, int daysInMonth, DateTime today, ColorScheme cs) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 52);
    final date = DateTime(month.year, month.month, day);
    final has = days.contains(day);
    final isToday = Diary.isToday(date);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _openDay(date),
      child: Container(
        height: 52,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: has ? cs.primaryContainer : null,
          border: isToday
              ? Border.all(color: cs.primary, width: 2)
              : Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontWeight: has || isToday ? FontWeight.w700 : FontWeight.w400,
                color: has ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
            if (has)
              Icon(Icons.circle, size: 6, color: cs.onPrimaryContainer),
          ],
        ),
      ),
    );
  }

  Widget _entryTile(String path) {
    const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final parsed = Diary.parseName(Diary.baseName(path));
    if (parsed == null) return const SizedBox.shrink();
    final day = parsed.day;
    final loc = locations[path];
    final file = FileManager.getFile('$path${Editor.extension}.p');
    String two(int n) => n.toString().padLeft(2, '0');
    return ListTile(
      leading: SizedBox(
        width: 48,
        height: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: file.existsSync()
                ? Image(
                    image: DecryptedFileImage(file),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.menu_book, color: Colors.black45),
                  )
                : const Icon(Icons.menu_book, color: Colors.black45),
          ),
        ),
      ),
      title: Text(
        '${wd[day.weekday - 1]}, ${two(day.day)}.${two(day.month)}.${day.year}'
        '${parsed.rest}',
      ),
      subtitle: loc == null ? null : Text('Ort: ${loc.label}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loc != null)
            IconButton(
              tooltip: 'Auf Karte zeigen',
              icon: const Icon(Icons.place),
              onPressed: () => launchUrl(loc.mapUri),
            ),
          IconButton(
            tooltip: 'Verwalten',
            icon: const Icon(Icons.more_vert),
            onPressed: () => _entryMenu(path),
          ),
        ],
      ),
      onTap: () => _openEntry(path),
      onLongPress: () => _entryMenu(path),
    );
  }
}
