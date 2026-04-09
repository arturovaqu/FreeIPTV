import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Generic responsive grid for Series / Movie cards.
///
/// [crossAxisCount] is the *default* column count; the grid also auto-adapts
/// when [responsive] is true (default) based on available width:
///   < 600 px  → 2 columns
///   < 900 px  → [crossAxisCount] columns
///   ≥ 900 px  → [crossAxisCount] + 1 columns (TV / large screens)
class ContentGrid<T> extends StatelessWidget {
  final List<T>         items;
  final Widget Function(T item, int index) itemBuilder;
  final void Function(T item) onTap;

  /// Base column count (used as-is when [responsive] is false).
  final int crossAxisCount;

  /// Whether to auto-adjust columns based on screen width.
  final bool responsive;

  /// Aspect ratio of each cell (width / height). Poster ratio ≈ 0.62.
  final double childAspectRatio;

  /// Padding around the entire grid.
  final EdgeInsetsGeometry padding;

  const ContentGrid({
    super.key,
    required this.items,
    required this.itemBuilder,
    required this.onTap,
    this.crossAxisCount    = 3,
    this.responsive        = true,
    this.childAspectRatio  = 0.62,
    this.padding           = const EdgeInsets.fromLTRB(
        AppSpacing.base, AppSpacing.sm, AppSpacing.base, AppSpacing.xxl),
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyGrid();
    }

    return LayoutBuilder(
      builder: (_, constraints) {
        final cols = _computeCols(constraints.maxWidth);
        return GridView.builder(
          padding: padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   cols,
            mainAxisSpacing:  AppSpacing.base,
            crossAxisSpacing: AppSpacing.base,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => onTap(items[i]),
            child: itemBuilder(items[i], i),
          ),
        );
      },
    );
  }

  int _computeCols(double width) {
    if (!responsive) return crossAxisCount;
    if (width < 600) return 2;
    if (width < 900) return crossAxisCount;
    return crossAxisCount + 1;
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyGrid extends StatelessWidget {
  const _EmptyGrid();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_off, size: 56, color: AppColors.textDisabled),
          SizedBox(height: AppSpacing.md),
          Text('Sin contenido disponible',
              style: AppTextStyles.bodyMedium),
        ],
      ),
    );
  }
}
