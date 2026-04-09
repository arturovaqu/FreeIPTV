import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/constants.dart';

/// A labelled horizontal-scroll section used in [SearchScreen].
///
/// Shows a header with title + item count, followed by a horizontally
/// scrollable row of items built by [itemBuilder].
class SearchResultSection extends StatelessWidget {
  /// Section heading (e.g. "Canales", "Series", "Películas").
  final String title;

  /// Raw list of items to render.
  final List<dynamic> items;

  /// The content type — used to pick accent colour for the header badge.
  final ContentType type;

  /// Called when the user taps an item.
  final void Function(dynamic item) onItemTap;

  /// Builds the card / tile widget for each item.
  final Widget Function(dynamic item) itemBuilder;

  /// Height of the horizontal scroll area.
  final double rowHeight;

  /// Item width inside the scroll area.
  final double itemWidth;

  const SearchResultSection({
    super.key,
    required this.title,
    required this.items,
    required this.type,
    required this.onItemTap,
    required this.itemBuilder,
    this.rowHeight = 200,
    this.itemWidth = 130,
  });

  Color get _accentColor => switch (type) {
        ContentType.TV     => AppColors.accentLive,
        ContentType.SERIES => AppColors.accentSeries,
        ContentType.MOVIES => AppColors.accentMovies,
      };

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.base, AppSpacing.lg,
              AppSpacing.base, AppSpacing.sm),
          child: Row(
            children: [
              // Coloured accent strip
              Container(
                width: 4, height: 20,
                decoration: BoxDecoration(
                  color: _accentColor,
                  borderRadius: AppRadius.chipRadius,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(title, style: AppTextStyles.headlineSmall),
              const SizedBox(width: AppSpacing.sm),
              // Item count badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.15),
                  borderRadius: AppRadius.chipRadius,
                ),
                child: Text(
                  '${items.length}',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: _accentColor),
                ),
              ),
            ],
          ),
        ),

        // ── Horizontal scroll row ─────────────────────────────────────
        SizedBox(
          height: rowHeight,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base),
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) {
              final item = items[i];
              return SizedBox(
                width: itemWidth,
                child: GestureDetector(
                  onTap: () => onItemTap(item),
                  child: itemBuilder(item),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
