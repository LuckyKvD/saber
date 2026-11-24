import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/crypto/local_migration.dart';

/// Zeigt den Fortschritt der lokalen Ver-/Entschlüsselung an (sonst leer).
class LocalMigrationStatus extends StatelessWidget {
  const LocalMigrationStatus({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LocalMigration.progress,
      builder: (context, progress, _) {
        if (progress == null) return const SizedBox.shrink();
        final text = progress.encrypting
            ? 'Notizen werden verschlüsselt'
            : 'Notizen werden entschlüsselt';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$text: ${progress.done} / ${progress.total}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress.total == 0
                    ? null
                    : progress.done / progress.total,
              ),
            ],
          ),
        );
      },
    );
  }
}
