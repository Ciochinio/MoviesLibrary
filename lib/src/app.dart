import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'ui/shell.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Colour tokens
// ──────────────────────────────────────────────────────────────────────────────
//
// Seed colour drives the full Material 3 palette generation.
// We use a deep blue-violet seed, then override a handful of surface tokens
// to give dark mode that layered dark-purple background from the reference UI.
// ──────────────────────────────────────────────────────────────────────────────

const _kSeed = Color(0xFF7C3AED); // vivid violet — used as primary accent

// Dark mode surface overrides — layered dark purple backgrounds
const _kDarkBackground   = Color(0xFF0F0D17); // deepest layer
const _kDarkSurface      = Color(0xFF1A1625); // cards / panels
const _kDarkSurfaceVar   = Color(0xFF241D35); // elevated cards
const _kDarkOnSurface    = Color(0xFFE8E0F5); // primary text (light lavender)
const _kDarkOnSurfaceVar = Color(0xFFB0A8C8); // secondary text

ThemeData _buildDark() {
  final base = ColorScheme.fromSeed(
    seedColor: _kSeed,
    brightness: Brightness.dark,
  );

  final cs = base.copyWith(
    background: _kDarkBackground,
    surface: _kDarkSurface,
    surfaceVariant: _kDarkSurfaceVar,
    surfaceContainerHighest: _kDarkSurfaceVar,
    surfaceContainer: _kDarkSurface,
    surfaceContainerLow: _kDarkBackground,
    surfaceContainerHigh: _kDarkSurfaceVar,
    onBackground: _kDarkOnSurface,
    onSurface: _kDarkOnSurface,
    onSurfaceVariant: _kDarkOnSurfaceVar,
  );

  return _buildTheme(cs);
}

ThemeData _buildLight() {
  final cs = ColorScheme.fromSeed(
    seedColor: _kSeed,
    brightness: Brightness.light,
  );
  return _buildTheme(cs);
}

ThemeData _buildTheme(ColorScheme cs) {
  final isDark = cs.brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,

    // ── Scaffold / background ──────────────────────────────────────────────
    scaffoldBackgroundColor: cs.background,

    // ── Typography — slightly tighter than default for desktop density ─────
    textTheme: _textTheme(cs),

    // ── Cards ──────────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark
              ? Colors.white.withOpacity(0.07)
              : Colors.black.withOpacity(0.08),
        ),
      ),
    ),

    // ── NavigationRail ─────────────────────────────────────────────────────
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: isDark ? _kDarkBackground : cs.surface,
      indicatorColor: cs.primary.withOpacity(0.18),
      selectedIconTheme: IconThemeData(color: cs.primary, size: 22),
      unselectedIconTheme: IconThemeData(
        color: isDark ? _kDarkOnSurfaceVar : cs.onSurfaceVariant,
        size: 22,
      ),
      labelType: NavigationRailLabelType.none,
    ),

    // ── ListTile — desktop-appropriate density ─────────────────────────────
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 6,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    ),

    // ── Divider ────────────────────────────────────────────────────────────
    dividerTheme: DividerThemeData(
      color: isDark
          ? Colors.white.withOpacity(0.07)
          : Colors.black.withOpacity(0.08),
      thickness: 1,
      space: 1,
    ),

    // ── PopupMenu (context menu) ───────────────────────────────────────────
    popupMenuTheme: PopupMenuThemeData(
      color: isDark ? _kDarkSurfaceVar : cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.08),
        ),
      ),
      textStyle: TextStyle(
        fontSize: 13,
        color: isDark ? _kDarkOnSurface : cs.onSurface,
        fontWeight: FontWeight.w400,
      ),
    ),

    // ── MenuAnchor / DropdownMenu ──────────────────────────────────────────
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: MaterialStatePropertyAll(
          isDark ? _kDarkSurfaceVar : cs.surface,
        ),
        surfaceTintColor: const MaterialStatePropertyAll(Colors.transparent),
        elevation: const MaterialStatePropertyAll(8),
        shadowColor: MaterialStatePropertyAll(Colors.black.withOpacity(0.4)),
        shape: MaterialStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.08),
            ),
          ),
        ),
        padding: const MaterialStatePropertyAll(
          EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    ),

    // ── Buttons ────────────────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.15),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),

    // ── Input / TextField ──────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withOpacity(0.15)
              : Colors.black.withOpacity(0.2),
        ),
      ),
      filled: true,
      fillColor: isDark
          ? Colors.white.withOpacity(0.04)
          : Colors.black.withOpacity(0.03),
    ),

    // ── Dialogs ────────────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? _kDarkSurface : cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: Colors.black.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),

    // ── Scrollbar ──────────────────────────────────────────────────────────
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: MaterialStatePropertyAll(
        isDark
            ? Colors.white.withOpacity(0.18)
            : Colors.black.withOpacity(0.18),
      ),
      radius: const Radius.circular(4),
      thickness: const MaterialStatePropertyAll(6),
    ),

    // ── Chip ───────────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: isDark
          ? Colors.white.withOpacity(0.07)
          : Colors.black.withOpacity(0.06),
      labelStyle: TextStyle(
        fontSize: 12,
        color: isDark ? _kDarkOnSurface : cs.onSurface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide.none,
    ),

    // ── Tooltip ────────────────────────────────────────────────────────────
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? _kDarkSurfaceVar : const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
      waitDuration: const Duration(milliseconds: 500),
    ),

    // ── SnackBar ───────────────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark ? _kDarkSurfaceVar : const Color(0xFF2D2D2D),
      contentTextStyle: const TextStyle(fontSize: 13, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      behavior: SnackBarBehavior.floating,
    ),

    // ── Switch ─────────────────────────────────────────────────────────────
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) return cs.primary;
        return isDark ? _kDarkOnSurfaceVar : cs.outline;
      }),
      trackColor: MaterialStateProperty.resolveWith((states) {
        if (states.contains(MaterialState.selected)) {
          return cs.primary.withOpacity(0.3);
        }
        return isDark
            ? Colors.white.withOpacity(0.1)
            : Colors.black.withOpacity(0.1);
      }),
    ),
  );
}

TextTheme _textTheme(ColorScheme cs) {
  final base = cs.brightness == Brightness.dark ? _kDarkOnSurface : cs.onBackground;
  return GoogleFonts.interTextTheme(
    TextTheme(
      headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: base),
      titleLarge:    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: base),
      titleMedium:   TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: base),
      titleSmall:    TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: base),
      bodyLarge:     TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: base),
      bodyMedium:    TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: base),
      bodySmall:     TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: base.withOpacity(0.65)),
      labelLarge:    TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: base),
      labelMedium:   TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: base),
      labelSmall:    TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: base.withOpacity(0.65)),
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// App widget
// ──────────────────────────────────────────────────────────────────────────────

class PortableMediaLibraryApp extends StatelessWidget {
  const PortableMediaLibraryApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppState, ThemeMode>(
      (app) => app.settings.themeMode,
    );

    return MaterialApp(
      title: 'Portable Media Library',
      debugShowCheckedModeBanner: false,
      theme: _buildLight(),
      darkTheme: _buildDark(),
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
