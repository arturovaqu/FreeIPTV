import 'package:flutter/material.dart';
import '../models/content_type.dart';
import '../utils/constants.dart';

/// Size variants for [FavoriteButton].
enum FavoriteButtonSize { small, medium, large }

/// Animated heart button for toggling favourite state.
///
/// Uses [AnimatedScale] + [AnimatedSwitcher] for a tactile bounce effect.
/// [contentType] controls the accent colour of the active (filled) heart.
class FavoriteButton extends StatefulWidget {
  final bool         isFavorite;
  final VoidCallback onPressed;
  final ContentType  contentType;
  final FavoriteButtonSize size;

  const FavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onPressed,
    required this.contentType,
    this.size = FavoriteButtonSize.medium,
  });

  @override
  State<FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<FavoriteButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    _ctrl.forward().then((_) => _ctrl.reverse());
    widget.onPressed();
  }

  // ── Sizing ────────────────────────────────────────────────────────────────

  double get _iconSize => switch (widget.size) {
        FavoriteButtonSize.small  => 18,
        FavoriteButtonSize.medium => 24,
        FavoriteButtonSize.large  => 32,
      };

  double get _containerSize => switch (widget.size) {
        FavoriteButtonSize.small  => 32,
        FavoriteButtonSize.medium => 42,
        FavoriteButtonSize.large  => 52,
      };

  Color get _activeColor => switch (widget.contentType) {
        ContentType.TV     => AppColors.accentLive,
        ContentType.SERIES => AppColors.accentSeries,
        ContentType.MOVIES => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width:  _containerSize,
          height: _containerSize,
          decoration: BoxDecoration(
            color: AppColors.overlay,
            shape: BoxShape.circle,
          ),
          child: AnimatedSwitcher(
            duration: AppDurations.fast,
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: Icon(
              widget.isFavorite ? Icons.favorite : Icons.favorite_border,
              key: ValueKey(widget.isFavorite),
              size: _iconSize,
              color: widget.isFavorite ? _activeColor : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
