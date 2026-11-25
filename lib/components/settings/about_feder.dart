import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/settings/app_info.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hinweiskarte in den Einstellungen: Danksagung an Saber, Lizenz (GPL-3.0)
/// und Urheber der Veränderungen. Darf wegen der GPL-3.0 nicht entfernt werden.
class AboutFeder extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showAbout(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SvgPicture.asset('assets/icon/icon.svg', width: 48, height: 48),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Feder', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      const Text(
                        'Ein Fork von Saber. Vielen Dank an Adil Hanney und alle Mitwirkenden von Saber.',
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Idee & Veränderung: LuckyKvD · Ausführung: Claude',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Lizenz: GPL-3.0 · Tippen für Details',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAbout(BuildContext context) => showAboutDialog(
    context: context,
    applicationName: 'Feder',
    applicationIcon: SvgPicture.asset(
      'assets/icon/icon.svg',
      width: 50,
      height: 50,
    ),
    applicationLegalese:
        'Feder ist ein Fork von Saber.\n'
        'Saber  Copyright © 2022-${DateTime.now().year}  Adil Hanney und Mitwirkende.\n'
        'Idee & Veränderung: LuckyKvD, Ausführung: Claude.\n\n'
        'Dieses Programm kommt ohne jegliche Gewährleistung. Es ist freie '
        'Software unter der GNU General Public License Version 3 und darf '
        'unter deren Bedingungen weitergegeben werden.',
    children: [
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => launchUrl(AppInfo.licenseUrl),
        child: const SizedBox(
          width: double.infinity,
          child: Text('Lizenztext (GPL-3.0) und Quellcode von Saber'),
        ),
      ),
      TextButton(
        onPressed: () => launchUrl(AppInfo.sponsorUrl),
        child: const SizedBox(
          width: double.infinity,
          child: Text('Den Saber-Entwickler unterstützen'),
        ),
      ),
    ],
  );
}
