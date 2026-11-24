import 'package:material_ui/material_ui.dart';

/// Namenszeile auf der Startseite von Feder.
///
/// Der zweite Satz nennt das Originalprojekt und ist wegen der GPL-3.0
/// (Urheberhinweise) nicht entfernbar.
class CreditsLine extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Idee & Veränderung: LuckyKvD · Ausführung: Claude',
            style: style?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Basiert auf Saber von Adil Hanney und Mitwirkenden (GPL-3.0)',
            style: style,
          ),
          const SizedBox(height: 2),
          Text(
            const String.fromEnvironment('FEDER_BUILD', defaultValue: 'lokaler Build'),
            style: style,
          ),
        ],
      ),
    );
  }
}
