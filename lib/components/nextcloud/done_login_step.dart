import 'dart:math';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/components/home/local_migration_status.dart';
import 'package:saber/components/misc/faq.dart';
import 'package:saber/data/crypto/local_migration.dart';
import 'package:saber/components/settings/nextcloud_profile.dart';
import 'package:saber/data/extensions/string_extensions.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:saber/data/nextcloud/saber_syncer.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/quota.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:url_launcher/url_launcher.dart';

class DoneLoginStep extends HookWidget {
  const new({super.key, required this.recheckCurrentStep});

  final void Function() recheckCurrentStep;

  static const width = 400.0;

  static final log = Logger('DoneLoginStep');

  Future<void> _logout(BuildContext context) async {
    // Lokale Dateien zuerst wieder entschlüsseln (zwei Durchläufe, falls der
    // Sync währenddessen noch etwas geschrieben hat). Nur wenn alles geklappt
    // hat, wird der Schlüssel entfernt.
    var failed = await LocalMigration.decryptAll();
    failed += await LocalMigration.decryptAll();
    if (failed > 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Abmelden abgebrochen: $failed Dateien konnten nicht '
              'entschlüsselt werden.',
            ),
          ),
        );
      }
      return;
    }
    stows.url.value = '';
    stows.username.value = '';
    stows.ncPassword.value = '';
    stows.encPassword.value = '';
    stows.pfp.value = null;
    stows.lastStorageQuota.value = null;
    stows.key.value = '';
    stows.iv.value = '';
    SaberSyncInterface.clearPathCaches();
    recheckCurrentStep();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = TextTheme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final horizontalPadding = screenWidth > width
        ? (screenWidth - width) / 2
        : 16.0;
    // Speicherplatz sofort laden (sonst steht dort nur der Platzhalter).
    useEffect(() {
      NextcloudProfile.getStorageQuota().catchError((_) => null);
      return null;
    }, const []);
    final quota = useValueListenable(stows.lastStorageQuota);
    final serverName =
        stows.url.value.ifNotEmpty ?? t.login.ncLoginStep.saberNcServer;
    late final serverUri = stows.url.value.isEmpty
        ? NextcloudClientExtension.defaultNextcloudUri
        : Uri.parse(stows.url.value);
    return MediaQuery.removeViewPadding(
      context: context,
      child: ListView(
        padding: .only(
          top: max(16, viewPadding.top),
          bottom: max(16, viewPadding.bottom),
          left: max(horizontalPadding, viewPadding.left),
          right: max(horizontalPadding, viewPadding.right),
        ),
        children: [
          const SizedBox(height: 16),
          if (screenHeight > 500) ...[
            SvgPicture.asset(
              'assets/images/undraw_my_files_swob.svg',
              width: width,
              height: min(width * 576 / 844.6693, screenHeight * 0.25),
              excludeFromSemantics: true,
            ),
            SizedBox(height: min(64, screenHeight * 0.05)),
          ],
          Row(
            children: [
              if (stows.pfp.value == null)
                if (stows.url.value.isEmpty)
                  SvgPicture.asset(
                    'assets/icon/icon.svg',
                    width: 32,
                    height: 32,
                  )
                else
                  const Icon(Icons.account_circle, size: 32)
              else
                Image.memory(stows.pfp.value!, width: 32, height: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  t.login.status.hi(u: stows.username.value),
                  style: textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(quota?.describe() ?? Quota.describePlaceholder()),
          const SizedBox(height: 2),
          LinearProgressIndicator(
            value: quota?.progressIndicatorValue,
            minHeight: 32,
            borderRadius: _elevatedButtonBorderRadiusOf(context),
          ),
          const SizedBox(height: 4),
          const LocalMigrationStatus(),
          ElevatedButton(
            onPressed: () => _logout(context),
            child: Text(t.profile.logout),
          ),
          const SizedBox(height: 32),
          Text(t.profile.connectedTo, style: const TextStyle(height: 0.8)),
          Text(serverName, style: textTheme.headlineSmall),
          const SizedBox(height: 4),
          Row(
            children: [
              Flexible(
                fit: FlexFit.tight,
                child: ElevatedButton(
                  onPressed: () {
                    log.info('Opening URL: $serverUri');
                    launchUrl(serverUri);
                  },
                  child: Text(t.profile.quickLinks.serverHomepage),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.tight,
                child: ElevatedButton(
                  onPressed: () {
                    final url =
                        '$serverUri/index.php/settings/user/drop_account';
                    log.info('Opening URL: $url');
                    launchUrl(Uri.parse(url));
                  },
                  child: Text(t.profile.quickLinks.deleteAccount),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Text(t.profile.faqTitle, style: textTheme.headlineSmall),
          FaqListView(
            shrinkWrap: true,
            items: [for (final item in t.profile.faq) FaqItem(item.q, item.a)],
          ),
        ],
      ),
    );
  }
}

BorderRadius _elevatedButtonBorderRadiusOf(BuildContext context) {
  final shape = ElevatedButtonTheme.of(context).style?.shape?.resolve({});
  if (shape is RoundedRectangleBorder) {
    return shape.borderRadius.resolve(TextDirection.ltr);
  } else {
    return const .all(.circular(8));
  }
}
