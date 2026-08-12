import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

abstract final class AppColors {
  // Keep the native client on the same tokens as the mobile web surface.
  static const brand = Color(0xFFFB7299);
  static const brandStrong = Color(0xFFC52F62);
  static const brandStrongDark = Color(0xFFFF759C);
  static const lavender = Color(0xFF5661AE);
  static const lavenderDark = Color(0xFF8FC5FF);
  static const sky = Color(0xFF5AA9FF);
  static const success = Color(0xFF147A59);
  static const successBright = Color(0xFF30B980);
  static const successDark = Color(0xFF45D6A0);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFC13D50);
  static const dangerDark = Color(0xFFFF8A98);
}

@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.backgroundCool,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.lineStrong,
    required this.brandSoft,
    required this.lavenderSoft,
  });

  static const light = AppPalette(
    background: Color(0xFFFFFAFC),
    backgroundCool: Color(0xFFF2F8FF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF7F9FC),
    ink: Color(0xFF20304A),
    inkMuted: Color(0xFF60708C),
    line: Color(0xFFD9E3F2),
    lineStrong: Color(0xFFF1C5D6),
    brandSoft: Color(0xFFFFEAF1),
    lavenderSoft: Color(0xFFEAF4FF),
  );

  // Near-black surfaces avoid OLED smearing while preserving the app's
  // warm-pink / cool-lavender identity in system dark mode.
  static const dark = AppPalette(
    background: Color(0xFF12131A),
    backgroundCool: Color(0xFF191B28),
    surface: Color(0xFF1C1E29),
    surfaceMuted: Color(0xFF252836),
    ink: Color(0xFFF5F3F8),
    inkMuted: Color(0xFFADB2C5),
    line: Color(0xFF303445),
    lineStrong: Color(0xFF454A60),
    brandSoft: Color(0xFF432735),
    lavenderSoft: Color(0xFF2B2E4C),
  );

  final Color background;
  final Color backgroundCool;
  final Color surface;
  final Color surfaceMuted;
  final Color ink;
  final Color inkMuted;
  final Color line;
  final Color lineStrong;
  final Color brandSoft;
  final Color lavenderSoft;

  @override
  AppPalette copyWith({
    Color? background,
    Color? backgroundCool,
    Color? surface,
    Color? surfaceMuted,
    Color? ink,
    Color? inkMuted,
    Color? line,
    Color? lineStrong,
    Color? brandSoft,
    Color? lavenderSoft,
  }) {
    return AppPalette(
      background: background ?? this.background,
      backgroundCool: backgroundCool ?? this.backgroundCool,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      lineStrong: lineStrong ?? this.lineStrong,
      brandSoft: brandSoft ?? this.brandSoft,
      lavenderSoft: lavenderSoft ?? this.lavenderSoft,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      backgroundCool: Color.lerp(backgroundCool, other.backgroundCool, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      lavenderSoft: Color.lerp(lavenderSoft, other.lavenderSoft, t)!,
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get appColors =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  Color get appPositive => Theme.of(this).brightness == Brightness.dark
      ? AppColors.successDark
      : AppColors.success;
}

abstract final class AppRadius {
  static const small = 10.0;
  static const medium = 14.0;
  static const large = 18.0;
  static const hero = 22.0;
}

abstract final class AppGradients {
  static LinearGradient background(BuildContext context) {
    final colors = context.appColors;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [colors.background, colors.backgroundCool],
      stops: const [0, 0.78],
    );
  }

  static LinearGradient brandSoft(BuildContext context, {double opacity = 1}) {
    final colors = context.appColors;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colors.brandSoft.withValues(alpha: opacity),
        colors.lavenderSoft.withValues(alpha: opacity),
      ],
    );
  }
}

abstract final class AppTheme {
  static ThemeData light() =>
      _build(brightness: Brightness.light, palette: AppPalette.light);

  static ThemeData dark() =>
      _build(brightness: Brightness.dark, palette: AppPalette.dark);

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
  }) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? AppColors.brandStrongDark : AppColors.brandStrong;
    final secondary = dark ? AppColors.lavenderDark : AppColors.lavender;
    final error = dark ? AppColors.dangerDark : AppColors.danger;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.brand,
          brightness: brightness,
          surface: palette.surface,
        ).copyWith(
          primary: primary,
          onPrimary: dark ? const Color(0xFF2A1720) : Colors.white,
          primaryContainer: palette.brandSoft,
          onPrimaryContainer: palette.ink,
          secondary: secondary,
          onSecondary: dark ? const Color(0xFF20243A) : Colors.white,
          secondaryContainer: palette.lavenderSoft,
          onSecondaryContainer: palette.ink,
          error: error,
          onError: dark ? const Color(0xFF2A1720) : Colors.white,
          surface: palette.surface,
          onSurface: palette.ink,
          surfaceContainerLowest: palette.surface,
          surfaceContainerLow: palette.surfaceMuted,
          surfaceContainer: dark
              ? const Color(0xFF282B3A)
              : const Color(0xFFF4F5FA),
          surfaceContainerHigh: dark
              ? const Color(0xFF303343)
              : const Color(0xFFEEF0F7),
          surfaceContainerHighest: dark
              ? const Color(0xFF383C4E)
              : const Color(0xFFE9ECF5),
          onSurfaceVariant: palette.inkMuted,
          outline: palette.lineStrong,
          outlineVariant: palette.line,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      splashFactory: InkSparkle.splashFactory,
      extensions: [palette],
      visualDensity: VisualDensity.standard,
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: primary,
        scaffoldBackgroundColor: palette.background,
        barBackgroundColor: palette.surface.withValues(alpha: 0.94),
      ),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          color: palette.ink,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          color: palette.ink,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          color: palette.ink,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          color: palette.ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          color: palette.ink,
          height: 1.5,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          color: palette.ink,
          fontSize: 14,
          height: 1.5,
        ),
        bodySmall: base.textTheme.bodySmall?.copyWith(
          color: palette.inkMuted,
          fontSize: 12.5,
          height: 1.45,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        labelMedium: base.textTheme.labelMedium?.copyWith(
          color: palette.inkMuted,
          fontWeight: FontWeight.w600,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          color: palette.inkMuted,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 52,
        titleSpacing: 16,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: palette.ink,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.large),
          side: BorderSide(color: palette.line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 58,
        elevation: 0,
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected)
                ? primary
                : palette.inkMuted,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? primary
                : palette.inkMuted,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorColor: primary,
        labelColor: primary,
        unselectedLabelColor: palette.inkMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: palette.inkMuted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          side: BorderSide(color: palette.lineStrong),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: palette.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: palette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: palette.inkMuted,
        collapsedIconColor: palette.inkMuted,
        textColor: palette.ink,
        collapsedTextColor: palette.ink,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      dividerTheme: DividerThemeData(
        color: palette.line,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? scheme.surfaceContainerHighest : palette.ink,
        contentTextStyle: TextStyle(color: dark ? palette.ink : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: palette.brandSoft,
      ),
    );
  }
}
