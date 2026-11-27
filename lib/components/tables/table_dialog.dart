import 'package:material_ui/material_ui.dart';

/// Größe einer neuen Tabelle. Zellmaße in Kästchen.
class TableSpec {
  const TableSpec({
    required this.rows,
    required this.cols,
    required this.cellWidth,
    required this.cellHeight,
  });

  final int rows;
  final int cols;
  final double cellWidth;
  final double cellHeight;
}

Future<TableSpec?> showTableDialog(BuildContext context) {
  return showDialog<TableSpec>(
    context: context,
    builder: (_) => const _TableDialog(),
  );
}

class _TableDialog extends StatefulWidget {
  const _TableDialog();

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  int _rows = 3;
  int _cols = 3;
  double _cellW = 4;
  double _cellH = 1.5;

  static const _heights = [1.0, 1.5, 2.0, 3.0];
  static const _widths = [2.0, 3.0, 4.0, 6.0];

  static String _k(double v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v'.replaceAll('.', ',');

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> on) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          onPressed: value > min ? () => on(value - 1) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.center),
        ),
        IconButton(
          onPressed: value < max ? () => on(value + 1) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tabelle einfügen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _stepper('Spalten', _cols, 1, 12, (v) => setState(() => _cols = v)),
            _stepper('Zeilen', _rows, 1, 30, (v) => setState(() => _rows = v)),
            const SizedBox(height: 8),
            const Text('Zellhöhe (Kästchen)'),
            Wrap(
              spacing: 8,
              children: [
                for (final h in _heights)
                  ChoiceChip(
                    label: Text(_k(h)),
                    selected: _cellH == h,
                    onSelected: (_) => setState(() => _cellH = h),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Zellbreite (Kästchen)'),
            Wrap(
              spacing: 8,
              children: [
                for (final w in _widths)
                  ChoiceChip(
                    label: Text(_k(w)),
                    selected: _cellW == w,
                    onSelected: (_) => setState(() => _cellW = w),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Die Linien werden mit dem aktuellen Stift gezogen und wirken '
              'handgemalt. Die Tabelle erscheint in der Bildmitte.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            TableSpec(
              rows: _rows,
              cols: _cols,
              cellWidth: _cellW,
              cellHeight: _cellH,
            ),
          ),
          child: const Text('Einfügen'),
        ),
      ],
    );
  }
}
