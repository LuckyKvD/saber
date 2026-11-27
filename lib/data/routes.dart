import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_to_regexp/path_to_regexp.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/i18n/strings.g.dart';
import 'package:saber/pages/home/home.dart';

// workaround to assign strings as enum values
abstract class RoutePaths {
  static const home = '$prefixOfHome/:subpage';
  static const edit = '/edit';
  static const login = '/login';
  static const logs = '/logs';
  static const search = '/search';

  static const prefixOfHome = '/home';

  static String editFilePath(String filePath) {
    return '$edit?path=${Uri.encodeQueryComponent(filePath)}';
  }

  /// Feder: Notiz öffnen und direkt zu Seite [pageIndex] (ab 0) springen.
  static String editFilePathPage(String filePath, int pageIndex) {
    return '$edit'
        '?path=${Uri.encodeQueryComponent(filePath)}'
        '&page=$pageIndex';
  }

  static String editImportPdf(String filePath, String pdfPath) {
    return '$edit'
        '?path=${Uri.encodeQueryComponent(filePath)}'
        '&pdfPath=${Uri.encodeQueryComponent(pdfPath)}';
  }
}

abstract class HomeRoutes {
  static String browseFilePath(String? filePath) {
    var path = routes[0].path;
    if (filePath != '/' && filePath != '' && filePath != null) {
      path += '?path=${Uri.encodeQueryComponent(filePath)}';
    }
    return path;
  }

  static final PathFunction _homeFunction = pathToFunction(RoutePaths.home);

  static List<HomeRoute> get routes => <HomeRoute>[
    HomeRoute._(
      _homeFunction({'subpage': HomePage.browseSubpage}),
      destination: NavigationDestination(
        label: t.home.tabs.home,
        icon: const AdaptiveIcon(
          icon: Icons.home,
          cupertinoIcon: CupertinoIcons.house_fill,
        ),
      ),
    ),
    HomeRoute._(
      _homeFunction({'subpage': HomePage.settingsSubpage}),
      destination: NavigationDestination(
        label: t.home.tabs.settings,
        icon: const AdaptiveIcon(
          icon: Icons.settings,
          cupertinoIcon: CupertinoIcons.settings_solid,
        ),
      ),
    ),
  ];
}

class const HomeRoute._(
  final String path, {
  required final NavigationDestination destination,
});
