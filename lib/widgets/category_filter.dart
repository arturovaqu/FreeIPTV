import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Horizontal chip-row + optional dropdown for selecting a content category.
///
/// Shows chips when [categories] ≤ [_chipThreshold], otherwise falls back to
/// a compact [DropdownButton] for large category sets (common with IPTV lists).
class CategoryFilter extends StatelessWidget {
  /// Full category list (should include an "all" option as the first entry).
  final List<String> categories;

  /// Currently selected category; null means nothing selected.
  final String? selected;

  /// Called with the newly selected category string.
  final ValueChanged<String> onChanged;

  /// Maximum number of items to render as chips before switching to dropdown.
  static const int _chipThreshold = 8;

  const CategoryFilter({
    super.key,
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (categories.length > _chipThreshold) {
      return _DropdownFilter(
        categories: categories,
        selected: selected,
        onChanged: onChanged,
      );
    }
    return _ChipFilter(
      categories: categories,
      selected: selected,
      onChanged: onChanged,
    );
  }
}

// ─── Chip variant ────────────────────────────────────────────────────────────

class _ChipFilter extends StatelessWidget {
  final List<String> categories;
  final String?      selected;
  final ValueChanged<String> onChanged;

  const _ChipFilter({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final cat      = categories[i];
          final isActive = cat == selected;

          return Focus(
            child: Builder(builder: (ctx) {
              final hasFocus = Focus.of(ctx).hasFocus;
              return GestureDetector(
                onTap: () => onChanged(cat),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.base, vertical: AppSpacing.xs + 2),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.accent
                        : hasFocus
                            ? AppColors.cardHover
                            : AppColors.surfaceVariant,
                    borderRadius: AppRadius.chipRadius,
                    border: Border.all(
                      color: isActive
                          ? AppColors.accent
                          : hasFocus
                              ? AppColors.focusBorder
                              : AppColors.border,
                    ),
                  ),
                  child: Text(
                    cat,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: isActive
                          ? AppColors.textInverse
                          : AppColors.textSecondary,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ─── Dropdown variant ─────────────────────────────────────────────────────────

class _DropdownFilter extends StatelessWidget {
  final List<String> categories;
  final String?      selected;
  final ValueChanged<String> onChanged;

  const _DropdownFilter({
    required this.categories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final value = (selected != null && categories.contains(selected))
        ? selected!
        : categories.first;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.base, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.buttonRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: AppColors.card,
          style: AppTextStyles.bodyMedium,
          icon: const Icon(Icons.arrow_drop_down,
              color: AppColors.textSecondary),
          items: categories
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: AppTextStyles.bodyMedium),
                  ))
              .toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
        ),
      ),
    );
  }
}
