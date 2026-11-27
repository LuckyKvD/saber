import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/math/math_solver.dart';

/// Feder: Fenster "Matheaufgabe lösen": erkannte Aufgabe korrigieren,
/// Ergebnis und Rechenweg sehen. Rechnet live beim Tippen, alles auf dem Gerät.
/// Gibt den Text zurück, der in die Notiz geschrieben werden soll (oder null).
Future<String?> showMathSolveDialog(
  BuildContext context, {
  required List<String> candidates,
  String? problem,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _MathDialog(candidates: candidates, problem: problem),
  );
}

class _MathDialog extends StatefulWidget {
  const _MathDialog({required this.candidates, required this.problem});

  final List<String> candidates;
  final String? problem;

  @override
  State<_MathDialog> createState() => _MathDialogState();
}

class _MathDialogState extends State<_MathDialog> {
  late final TextEditingController _text;
  MathSolution? _solution;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Erste Lesart nehmen, die sich auch lösen lässt.
    var start = widget.candidates.isEmpty ? '' : widget.candidates.first;
    for (final c in widget.candidates) {
      try {
        MathSolver.solve(c);
        start = c;
        break;
      } on MathError {
        // nächste Lesart
      }
    }
    _text = TextEditingController(text: start);
    _recalc();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _recalc() {
    try {
      _solution = MathSolver.solve(_text.text);
      _error = null;
    } on MathError catch (e) {
      _solution = null;
      _error = e.message;
    } catch (e) {
      _solution = null;
      _error = 'Das konnte ich nicht rechnen.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final alternatives = widget.candidates.skip(1).take(4).toList();
    final solution = _solution;

    return AlertDialog(
      title: const Text('Matheaufgabe lösen'),
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
                autofocus: widget.candidates.isEmpty,
                minLines: 1,
                maxLines: 3,
                onChanged: (_) => setState(_recalc),
                decoration: const InputDecoration(
                  labelText: 'Aufgabe (bitte prüfen, z. B. 3x+5=20)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (alternatives.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Andere Lesarten:', style: textTheme.labelMedium),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final alt in alternatives)
                      ActionChip(
                        label: Text(alt),
                        onPressed: () => setState(() {
                          _text.text = alt;
                          _recalc();
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              if (solution != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    solution.result,
                    style: textTheme.titleLarge?.copyWith(
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Rechenweg', style: textTheme.labelLarge),
                const SizedBox(height: 4),
                for (final step in solution.steps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SelectableText(step),
                  ),
                if (solution.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(solution.note!, style: textTheme.bodySmall),
                  ),
              ] else if (_text.text.trim().isNotEmpty)
                Text(
                  _error ?? '',
                  style: TextStyle(color: colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (solution != null)
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: solution.result));
              messenger.showSnackBar(
                const SnackBar(content: Text('Ergebnis kopiert.')),
              );
            },
            child: const Text('Ergebnis kopieren'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen'),
        ),
        if (solution != null)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(solution.writeText),
            child: const Text('In Notiz schreiben'),
          ),
      ],
    );
  }
}
