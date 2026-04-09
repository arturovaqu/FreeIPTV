import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/models.dart';
import '../utils/constants.dart';
import 'favorite_button.dart';

/// Generic card for Series / Movie posters.
///
/// Shows poster image, title, year, rating, and a favourite toggle.
/// Supports TV D-Pad focus (Enter key triggers [onTap]).
class ContentItemCard extends StatelessWidget {
  final String?  poster;
  final String   title;
  final int?     year;
  final double?  rating;
  final bool     isFavorite;
  final ContentType contentType;
  final VoidCallback onTap;
  final VoidCallback onFavoriteTap;

  /// Optional badge text rendered over the top-left of the poster
  /// (e.g. "VISTO", "HD").
  final String? badge;

  const ContentItemCard({
    super.key,
    required this.title,
    required this.isFavorite,
    required this.contentType,
    required this.onTap,
    required this.onFavoriteTap,
    this.poster,
    this.year,
    this.rating,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: AppRadius.cardRadius,
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
                        blurRadius: 12,
                        spreadRadius: 2,
                      )
                    ]
                  : [],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Poster ────────────────────────────────────────────
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Poster image
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadius.md)),
                        child: _PosterImage(
                            url: poster, name: title),
                      ),
                      // Top-left badge
                      if (badge != null)
                        Positioned(
                          top: 6, left: 6,
                          child: _Badge(label: badge!),
                        ),
                      // Favorite button (top-right)
                      Positioned(
                        top: 4, right: 4,
                        child: FavoriteButton(
                          isFavorite: isFavorite,
                          onPressed: onFavoriteTap,
                          contentType: contentType,
                          size: FavoriteButtonSize.small,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Info ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.sm, AppSpacing.sm,
                      AppSpacing.sm, AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.labelLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(children: [
                        if (year != null) ...[
                          Text(year.toString(),
                              style: AppTextStyles.bodySmall),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (rating != null) ...[
                          const Icon(Icons.star,
                              size: 12, color: AppColors.warning),
                          const SizedBox(width: 2),
                          Text(rating!.toStringAsFixed(1),
                              style: AppTextStyles.bodySmall),
                        ],
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ─── Poster image ─────────────────────────────────────────────────────────────

class _PosterImage extends StatelessWidget {
  final String? url;
  final String  name;

  const _PosterImage({this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _Fallback(name: name),
      );
    }
    return _Fallback(name: name);
  }
}

class _Fallback extends StatelessWidget {
  final String name;
  const _Fallback({required this.name});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported,
                color: AppColors.textDisabled, size: 36),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(name,
                  style: AppTextStyles.bodySmall,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ),
          ],
        ),
      );
}

// ─── Badge ────────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.9),
          borderRadius: AppRadius.chipRadius,
        ),
        child: Text(label, style: AppTextStyles.badge),
      );
}

