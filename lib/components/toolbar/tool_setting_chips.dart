import 'package:material_ui/material_ui.dart';
import 'package:stow/stow.dart';

/// Kleine Auswahl-Chips direkt in der Stift-Leiste, gebunden an eine
/// Einstellung (z. B. Federwinkel). Änderungen wirken sofort.
class ToolSettingChips<T extends Object> extends StatelessWidget {
  const ToolSettingChips({
    super.key,
    required this.label,
    required this.pref,
    required this.options,
  });

  final String label;
  final Stow<dynamic, T, dynamic> pref;
  final List<(T, String)> options;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return ListenableBuilder(
      listenable: pref,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 6),
            for (final (value, text) in options)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(text),
                  selected: pref.value == value,
                  onSelected: (_) => pref.value = value,
                  visualDensity: VisualDensity.compact,
                  labelStyle: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}
