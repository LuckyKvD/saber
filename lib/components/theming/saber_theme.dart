import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:saber/data/constants.dart';
import 'package:saber/data/prefs.dart';
import 'package:sbn/font_fallbacks.dart';
import 'package:yaru/yaru.dart';

abstract class SaberTheme {
  /// Feder: Nachtblau und Gold.
  static final ColorScheme federDark =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF14284B),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFFE3B84B),
        onPrimary: const Color(0xFF1A1405),
        primaryContainer: const Color(0xFF5A4410),
        onPrimaryContainer: const Color(0xFFF7E1A0),
        secondary: const Color(0xFFC9972B),
        onSecondary: const Color(0xFF1A1405),
        surface: const Color(0xFF0B1A33),
        surfaceContainerLowest: const Color(0xFF071225),
        surfaceContainerLow: const Color(0xFF0E2040),
        surfaceContainer: const Color(0xFF112549),
        surfaceContainerHigh: const Color(0xFF162C54),
        surfaceContainerHighest: const Color(0xFF1B345F),
        onSurface: const Color(0xFFEDE6D3),
      );

  static final ColorScheme federLight =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF14284B),
        brightness: Brightness.light,
      ).copyWith(
        primary: const Color(0xFF14284B),
        onPrimary: const Color(0xFFFFFFFF),
        primaryContainer: const Color(0xFFF3E3B0),
        onPrimaryContainer: const Color(0xFF3A2A05),
        secondary: const Color(0xFFB8841F),
        onSecondary: const Color(0xFFFFFFFF),
        surface: const Color(0xFFFBF8F1),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF6F1E4),
        surfaceContainer: const Color(0xFFF0EAD8),
        surfaceContainerHigh: const Color(0xFFEAE3CE),
        surfaceContainerHighest: const Color(0xFFE4DCC4),
        onSurface: const Color(0xFF0B1A33),
      );

  static ThemeData createTheme(
    ColorScheme colorScheme,
    TargetPlatform platform,
  ) {
    final isFeder = colorScheme == federLight || colorScheme == federDark;
    colorScheme = _adjustColorScheme(colorScheme, platform);
    const navy = Color(0xFF0B1A33);
    const gold = Color(0xFFE3B84B);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: _Components.textTheme(platform, colorScheme),
      platform: platform,
      progressIndicatorTheme: _Components.progressIndicatorTheme,
      cardColor: colorScheme.surface,
      cardTheme: _Components.cardTheme(colorScheme),
      cupertinoOverrideTheme: _Components.cupertinoOverrideTheme,
      appBarTheme: _Components.appBarTheme,
      navigationBarTheme: isFeder
          ? const NavigationBarThemeData(
              backgroundColor: navy,
              indicatorColor: Color(0xFF5A4410),
            )
          : null,
      floatingActionButtonTheme: isFeder
          ? const FloatingActionButtonThemeData(
              backgroundColor: gold,
              foregroundColor: navy,
            )
          : null,
    );
  }

  static ThemeData createThemeFromSeed(
    Color seedColor,
    Brightness brightness,
    TargetPlatform platform, {
    @Deprecated(
      'High contrast is not implemented here. '
      'Use ColorScheme.withHighContrast() instead',
    )
    bool highContrast = false,
  }) {
    if (platform == .linux) {
      return getThemeFromYaru(seedColor, brightness, platform, highContrast);
    }

    final ColorScheme colorScheme;
    if (platform.isCupertino) {
      final bg = brightness == .light
          ? CupertinoColors.systemBackground.color
          : CupertinoColors.systemBackground.darkColor;
      colorScheme = ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: seedColor,
        surface: bg,
        surfaceTint: bg,
        dynamicSchemeVariant: .neutral,
      );
    } else {
      colorScheme = ColorScheme.fromSeed(
        brightness: brightness,
        seedColor: seedColor,
      );
    }
    return createTheme(colorScheme, platform);
  }

  /// Adjusts certain colors in the [ColorScheme].
  static ColorScheme _adjustColorScheme(
    ColorScheme colorScheme,
    TargetPlatform platform,
  ) {
    return colorScheme.copyWith(
      surface: platform.isCupertino
          ? (colorScheme.brightness == .light
                ? CupertinoColors.white
                : CupertinoColors.darkBackgroundGray)
          : null,
      // Hack: Mimic Material 3 Expressive color schemes by making
      // surfaceContainer much closer to surface.
      // Remove this when Flutter supports M3E natively.
      surfaceContainer: Color.lerp(
        colorScheme.surface,
        colorScheme.surfaceTint,
        0.02,
      )!,
    );
  }

  static ThemeData getThemeFromYaru(
    Color primaryColor,
    Brightness brightness,
    TargetPlatform platform,
    bool highContrast,
  ) {
    var base = brightness == .light
        ? createYaruLightTheme(
            primaryColor: primaryColor,
            fontFamily: stows.hyperlegibleFont.value
                ? 'AtkinsonHyperlegibleNext'
                : 'Adwaita Sans',
            fontFamilyFallback: saberSansSerifFontFallbacks,
          )
        : createYaruDarkTheme(
            primaryColor: primaryColor,
            fontFamily: stows.hyperlegibleFont.value
                ? 'AtkinsonHyperlegibleNext'
                : 'Adwaita Sans',
            fontFamilyFallback: saberSansSerifFontFallbacks,
          );
    base = base.copyWith(visualDensity: .defaultDensityForPlatform(platform));
    return getThemeFromYaruFixed(base, platform);
  }

  static ThemeData getThemeFromYaruFixed(
    ThemeData base,
    TargetPlatform platform,
  ) {
    final textTheme = _Components.textTheme(platform, base.colorScheme);
    final fontFamily = textTheme.bodyMedium!.fontFamily;
    final fontFamilyFallback = textTheme.bodyMedium!.fontFamilyFallback;
    final scaffoldBackgroundColor = base.colorScheme.isDark
        ? const Color(0xFF232323)
        : const Color(0xFFfafafa);
    return base.copyWith(
      platform: platform,
      textTheme: textTheme,
      progressIndicatorTheme: _Components.progressIndicatorTheme,
      cardTheme: _Components.cardTheme(base.colorScheme),
      cupertinoOverrideTheme: _Components.cupertinoOverrideTheme,
      listTileTheme: base.listTileTheme.copyWith(
        // Yaru forces list tiles to use Ubuntu font, fix that
        titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        leadingAndTrailingTextStyle: base
            .listTileTheme
            .leadingAndTrailingTextStyle
            ?.copyWith(
              fontFamily: fontFamily,
              fontFamilyFallback: fontFamilyFallback,
            ),
      ),
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      appBarTheme: _Components.appBarTheme.copyWith(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBackgroundColor,
      ),
    );
  }
}

abstract class _Components {
  static TextTheme textTheme(TargetPlatform platform, ColorScheme colorScheme) {
    final typography = Typography.material2021(
      platform: platform,
      colorScheme: colorScheme,
    );
    final textTheme = colorScheme.brightness == .dark
        ? typography.white
        : typography.black;

    if (stows.hyperlegibleFont.value) {
      return textTheme.withFont(
        fontFamily: 'AtkinsonHyperlegibleNext',
        fontFamilyFallback: saberSansSerifFontFallbacks,
      );
    } else if (platform == .linux) {
      // Flutter picks Roboto but Adwaita Sans is a better default
      return textTheme.withFont(fontFamily: 'Adwaita Sans');
    } else {
      return textTheme;
    }
  }

  static const progressIndicatorTheme = ProgressIndicatorThemeData(
    // ignore: deprecated_member_use
    year2023: false,
    stopIndicatorColor: Colors.transparent,
  );

  static CardThemeData cardTheme(ColorScheme colorScheme) {
    return CardThemeData(
      elevation: 0,
      color: colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: const .all(.circular(kSaberCardRadius)),
        side: BorderSide(
          color: colorScheme.onSurface.withValues(alpha: 0.12),
          width: colorScheme.isHighContrast
              ? kSaberBorderWidthAccessible
              : kSaberBorderWidthInaccessible,
        ),
      ),
    );
  }

  static const cupertinoOverrideTheme = NoDefaultCupertinoThemeData(
    applyThemeToAll: true,
  );

  static const appBarTheme = AppBarTheme(centerTitle: false);
}

extension SaberThemePlatform on TargetPlatform {
  bool get isCupertino => switch (this) {
    .iOS => true,
    .macOS => true,
    _ => false,
  };

  bool get isMaterialNative => switch (this) {
    .android => true,
    .fuchsia => true,
    _ => false,
  };
}
