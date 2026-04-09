import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TV detection helper
// ─────────────────────────────────────────────────────────────────────────────

/// Returns true if the current screen is likely a TV / large-screen device.
///
/// Heuristic: logical short-edge ≥ 600 dp AND device pixel ratio < 3
/// (TVs typically have 1080p+ but low DPR because they are viewed from a
/// distance, while phones have very high DPR).
bool isTV(BuildContext context) {
  final mq  = MediaQuery.of(context);
  final min = mq.size.shortestSide;
  return min >= 600 && mq.devicePixelRatio < 3;
}

// ─────────────────────────────────────────────────────────────────────────────
// TVOptimizedButton
// ─────────────────────────────────────────────────────────────────────────────

/// Large, focus-aware button designed for D-Pad / remote navigation.
///
/// On TV screens the minimum height is 56 dp; on smaller screens it reduces to
/// the standard 44 dp. The focus glow matches [AppColors.focusBorder].
class TVOptimizedButton extends StatelessWidget {
  final String   label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Background colour; defaults to [AppColors.accent].
  final Color?   backgroundColor;

  /// Foreground (text + icon) colour; defaults to [AppColors.textInverse].
  final Color?   foregroundColor;

  const TVOptimizedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final tv      = isTV(context);
    final minH    = tv ? 56.0 : 44.0;
    final hPad    = tv ? AppSpacing.xl  : AppSpacing.lg;
    final vPad    = tv ? AppSpacing.md  : AppSpacing.sm;
    final bgColor = backgroundColor ?? AppColors.accent;
    final fgColor = foregroundColor ?? AppColors.textInverse;

    return Focus(
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return AnimatedContainer(
          duration: AppDurations.fast,
          decoration: BoxDecoration(
            borderRadius: AppRadius.buttonRadius,
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: AppColors.focusGlow,
                      blurRadius: 16,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: focused
                  ? bgColor.withValues(alpha: 0.85)
                  : bgColor,
              foregroundColor: fgColor,
              minimumSize: Size(double.infinity, minH),
              padding: EdgeInsets.symmetric(
                  horizontal: hPad, vertical: vPad),
              shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonRadius),
              side: focused
                  ? const BorderSide(
                      color: AppColors.focusBorder, width: 2)
                  : BorderSide.none,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: tv ? 26 : 20, color: fgColor),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Text(
                  label,
                  style: (tv
                          ? AppTextStyles.headlineSmall
                          : AppTextStyles.labelLarge)
                      .copyWith(color: fgColor),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TVFocusable
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps [child] in a [Focus] node that routes D-Pad arrow keys and Enter to
/// caller-supplied callbacks.
///
/// All callbacks are optional. When a callback is null the corresponding key
/// event is ignored (propagates to parent).
class TVFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onEnter;
  final bool autofocus;

  const TVFocusable({
    super.key,
    required this.child,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
    this.onEnter,
    this.autofocus = false,
  });

  @override
  State<TVFocusable> createState() => _TVFocusableState();
}

class _TVFocusableState extends State<TVFocusable> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (widget.onLeft != null) {
          widget.onLeft!();
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.arrowRight:
        if (widget.onRight != null) {
          widget.onRight!();
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.arrowUp:
        if (widget.onUp != null) {
          widget.onUp!();
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.arrowDown:
        if (widget.onDown != null) {
          widget.onDown!();
          return KeyEventResult.handled;
        }
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.select:
        if (widget.onEnter != null) {
          widget.onEnter!();
          return KeyEventResult.handled;
        }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKey,
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        // Provide a subtle highlight so the user knows what's focused
        return AnimatedContainer(
          duration: AppDurations.fast,
          decoration: BoxDecoration(
            borderRadius: AppRadius.thumbnailRadius,
            border: Border.all(
              color: focused
                  ? AppColors.focusBorder
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: AppColors.focusGlow,
                      blurRadius: 10,
                    )
                  ]
                : [],
          ),
          child: widget.child,
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TVTheme
// ─────────────────────────────────────────────────────────────────────────────

/// Pre-configured [ThemeData] for TV / large-screen surfaces.
///
/// Scales up font sizes, increases touch targets, and applies the app's dark
/// colour palette. Merge with [MaterialApp.theme] or use directly.
final ThemeData TVTheme = ThemeData(
  brightness: Brightness.dark,
  useMaterial3: true,
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: const ColorScheme.dark(
    primary:   AppColors.accent,
    secondary: AppColors.accentSeries,
    surface:   AppColors.surface,
    error:     AppColors.error,
    onPrimary: AppColors.textInverse,
    onSurface: AppColors.textPrimary,
  ),
  textTheme: const TextTheme(
    displayLarge:   AppTextStyles.displayLarge,
    displayMedium:  AppTextStyles.displayMedium,
    headlineLarge:  AppTextStyles.headlineLarge,
    headlineMedium: AppTextStyles.headlineMedium,
    headlineSmall:  AppTextStyles.headlineSmall,
    bodyLarge:      AppTextStyles.bodyLarge,
    bodyMedium:     AppTextStyles.bodyMedium,
    bodySmall:      AppTextStyles.bodySmall,
    labelLarge:     AppTextStyles.labelLarge,
    labelMedium:    AppTextStyles.labelMedium,
    labelSmall:     AppTextStyles.labelSmall,
  ),
  iconTheme: const IconThemeData(
    color: AppColors.textPrimary,
    size:  28, // larger for TV
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      minimumSize:    const Size(120, 56),
      padding:        const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.md),
      shape:          const RoundedRectangleBorder(
          borderRadius: AppRadius.buttonRadius),
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.textInverse,
      textStyle:       AppTextStyles.headlineSmall,
    ),
  ),
  listTileTheme: const ListTileThemeData(
    minVerticalPadding: AppSpacing.md,
    contentPadding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
    titleTextStyle:    AppTextStyles.bodyLarge,
    subtitleTextStyle: AppTextStyles.bodyMedium,
  ),
  dividerColor: AppColors.border,
  focusColor:   AppColors.focusGlow,
);
