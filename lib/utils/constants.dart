import 'package:flutter/material.dart';

// ─────────────────────────────────────────────
// Colors — Dark Theme
// ─────────────────────────────────────────────
class AppColors {
  AppColors._();

  // Backgrounds
  static const Color background     = Color(0xFF07070B);
  static const Color surface        = Color(0xFF0F0F16);
  static const Color surfaceVariant = Color(0xFF161621);
  static const Color card           = Color(0xFF191926);
  static const Color cardHover      = Color(0xFF202030);

  // Glassmorphism tokens
  static const Color glassBase      = Color(0x1AFFFFFF);
  static const Color glassStroke    = Color(0x33FFFFFF);
  static const Color glassFill      = Color(0x0DFFFFFF);

  // Text
  static const Color textPrimary    = Color(0xFFFFFFFF);
  static const Color textSecondary  = Color(0xFFA0A0B0);
  static const Color textDisabled   = Color(0xFF5A5A70);
  static const Color textInverse    = Color(0xFF000000);

  // Accents - Curated vibrant palette
  static const Color accentLive     = Color(0xFFFF3366); // Neon coral/red
  static const Color accentSeries   = Color(0xFF6366F1); // Modern Indigo
  static const Color accentMovies   = Color(0xFFFACC15); // Vibrant Yellow

  // Global accent - Electric Purple
  static const Color accent         = Color(0xFF8B5CF6);
  static const Color accentDim      = Color(0xFF5B21B6);
  static const Color accentGlow     = Color(0x4D8B5CF6);

  // Borders / dividers
  static const Color border         = Color(0xFF252535);
  static const Color divider        = Color(0xFF1A1A28);

  // Status
  static const Color success        = Color(0xFF10B981);
  static const Color warning        = Color(0xFFF59E0B);
  static const Color error          = Color(0xFFEF4444);
  static const Color info           = Color(0xFF3B82F6);

  // Overlays
  static const Color overlay        = Color(0xE6000000);
  static const Color shadowColor    = Color(0x33000000);

  // Focused item (TV remote nav)
  static const Color focusBorder    = Color(0xFF8B5CF6);
  static const Color focusGlow      = Color(0x338B5CF6);
}

// ─────────────────────────────────────────────
// Typography — TV-optimised (larger baseline)
// ─────────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  static const String _fontFamily = 'Roboto';

  // Display
  static const TextStyle displayLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 48,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
  );

  static const TextStyle displayMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
    height: 1.15,
  );

  // Headlines
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  // Body
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // Labels / captions
  static const TextStyle labelLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 10,
    fontWeight: FontWeight.w500,
    color: AppColors.textDisabled,
    letterSpacing: 0.5,
    height: 1.3,
  );

  // Content-type badge labels
  static const TextStyle badge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
  );

  // Channel number / EPG time
  static const TextStyle channelNumber = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
    letterSpacing: 0.5,
  );

  // Search input
  static const TextStyle searchInput = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
  );

  // Player overlay title
  static const TextStyle playerTitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    shadows: [Shadow(blurRadius: 8, color: Colors.black87)],
  );

  static const TextStyle playerSubtitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
  );
}

// ─────────────────────────────────────────────
// Spacing
// ─────────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double base = 16.0;
  static const double lg   = 24.0;
  static const double xl   = 32.0;
  static const double xxl  = 48.0;
  static const double xxxl = 64.0;

  // Padding helpers
  static const EdgeInsets paddingXS   = EdgeInsets.all(xs);
  static const EdgeInsets paddingSM   = EdgeInsets.all(sm);
  static const EdgeInsets paddingMD   = EdgeInsets.all(md);
  static const EdgeInsets paddingBase = EdgeInsets.all(base);
  static const EdgeInsets paddingLG   = EdgeInsets.all(lg);
  static const EdgeInsets paddingXL   = EdgeInsets.all(xl);

  // Horizontal padding (common for page content)
  static const EdgeInsets horizontalBase = EdgeInsets.symmetric(horizontal: base);
  static const EdgeInsets horizontalLG   = EdgeInsets.symmetric(horizontal: lg);
  static const EdgeInsets horizontalXL   = EdgeInsets.symmetric(horizontal: xl);

  // Card / tile inner padding
  static const EdgeInsets cardPadding = EdgeInsets.symmetric(
    horizontal: base,
    vertical: md,
  );

  // Screen edge inset (TV-safe area approximation)
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(
    horizontal: xl,
    vertical: lg,
  );
}

// ─────────────────────────────────────────────
// Border Radii
// ─────────────────────────────────────────────
class AppRadius {
  AppRadius._();

  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 16.0;
  static const double xl   = 24.0;
  static const double full = 999.0;

  static const BorderRadius cardRadius     = BorderRadius.all(Radius.circular(md));
  static const BorderRadius thumbnailRadius = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius chipRadius     = BorderRadius.all(Radius.circular(full));
  static const BorderRadius buttonRadius   = BorderRadius.all(Radius.circular(sm));
}

// ─────────────────────────────────────────────
// Durations
// ─────────────────────────────────────────────
class AppDurations {
  AppDurations._();

  static const Duration fast    = Duration(milliseconds: 150);
  static const Duration normal  = Duration(milliseconds: 250);
  static const Duration slow    = Duration(milliseconds: 400);
  static const Duration splash  = Duration(milliseconds: 600);

  // Player controls auto-hide
  static const Duration playerHide = Duration(seconds: 4);
  // EPG refresh
  static const Duration epgRefresh = Duration(minutes: 5);
}

// ─────────────────────────────────────────────
// Content-type card sizes (width × height)
// ─────────────────────────────────────────────
class AppCardSizes {
  AppCardSizes._();

  // Live TV channel tile
  static const Size liveCard      = Size(200, 112); // 16:9
  static const Size liveCardLarge = Size(280, 158);

  // Series / Movie poster
  static const Size posterCard      = Size(130, 195); // 2:3
  static const Size posterCardLarge = Size(180, 270);

  // Search result row thumbnail
  static const Size searchThumb = Size(96, 54); // 16:9
}
