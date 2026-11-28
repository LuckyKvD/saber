import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/diary.dart';
import 'package:saber/data/file_manager/decrypted_file_image.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/routes.dart';
import 'package:saber/pages/editor/editor.dart';
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
  Set<int> days = {};
  Map<int, DiaryLocation?> locations = {};
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

  Future<void> _reload() async {
    final shown = month;
    final found = await Diary.daysWithEntries(shown.year, shown.month);
    final locs = <int, DiaryLocation?>{};
    for (final d in found) {
      locs[d] = await Diary.readLocation(DateTime(shown.year, shown.month, d));
    }
    if (!mounted || shown != month) return;
    setState(() {
      days = found;
      locations = locs;
    });
  }

  void _shift(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
      days = {};
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
      days = {};
      locations = {};
    });
    _reload();
  }

  Future<void> _open(DateTime day) async {
    final isNew = !Diary.exists(day);
    // Ort nur für heute: beim Nachtragen wäre er falsch.
    final Future<DiaryLocation?>? location = isNew && Diary.isToday(day)
        ? Diary.captureLocation()
        : null;
    await context.push(RoutePaths.editFilePath(Diary.pathFor(day)));
    if (isNew && location != null && Diary.exists(day)) {
      final loc = await location;
      if (loc != null) await Diary.saveLocation(day, loc);
    }
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = DateTime.now();
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // 1=Mo
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = firstWeekday - 1 + daysInMonth;
    final rows = (cells / 7).ceil();
    final entryDays = days.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(DateTime(today.year, today.month, today.day)),
        icon: const Icon(Icons.edit),
        label: const Text('Heute schreiben'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
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
            if (entryDays.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Keine Einträge in diesem Monat')),
              ),
            for (final d in entryDays) _entryTile(DateTime(month.year, month.month, d)),
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
      onTap: () => _open(date),
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

  Widget _entryTile(DateTime day) {
    const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final loc = locations[day.day];
    final file = FileManager.getFile(
      '${Diary.pathFor(day)}${Editor.extension}.p',
    );
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
        '${wd[day.weekday - 1]}, ${two(day.day)}.${two(day.month)}.${day.year}',
      ),
      subtitle: loc == null ? null : Text('Ort: ${loc.label}'),
      trailing: loc == null
          ? null
          : IconButton(
              tooltip: 'Auf Karte zeigen',
              icon: const Icon(Icons.place),
              onPressed: () => launchUrl(loc.mapUri),
            ),
      onTap: () => _open(day),
    );
  }
}
