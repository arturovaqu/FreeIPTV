import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import '../widgets/tv_focus_manager.dart';
import '../widgets/tv_text_field.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SeriesCategoryDetail
// ─────────────────────────────────────────────────────────────────────────────

/// Muestra el grid de series para una categoría concreta.
///
/// [onSeriesTap] se invoca al pulsar una tarjeta y recibe el BuildContext
/// de esta pantalla + la series seleccionada.  El caller (SeriesListScreen)
/// muestra el detail sheet, evitando una importación circular.
class SeriesCategoryDetail extends StatefulWidget {
  final String category;
  final List<Series> series;
  final void Function(BuildContext ctx, Series series) onSeriesTap;

  const SeriesCategoryDetail({
    super.key,
    required this.category,
    required this.series,
    required this.onSeriesTap,
  });

  @override
  State<SeriesCategoryDetail> createState() => _SeriesCategoryDetailState();
}

class _SeriesCategoryDetailState extends State<SeriesCategoryDetail> {
  final _searchCtrl   = TextEditingController();
  final _focusManager = TvFocusManager();
  String _query       = '';
  List<Series> _filtered = [];
  bool _hasFocusedOnce   = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
    _applyFilter();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _focusManager.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (_searchCtrl.text != _query) {
      setState(() {
        _query = _searchCtrl.text;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    final q = _query.trim().toLowerCase();
    _filtered = q.isEmpty
        ? List<Series>.from(widget.series)
        : widget.series
            .where((s) => s.name.toLowerCase().contains(q))
            .toList();

    if (!_hasFocusedOnce && _filtered.isNotEmpty) {
      _hasFocusedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusManager.focusFirst();
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.category, style: AppTextStyles.headlineSmall),
            Text('${widget.series.length} series',
                style: AppTextStyles.bodySmall),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
            child: TvTextField(
              controller: _searchCtrl,
              hintText: 'Buscar en ${widget.category}...',
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textSecondary, size: 20),
            ),
          ),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off, size: 64,
              color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.base),
          Text(
            _query.isNotEmpty
                ? 'Sin resultados para "$_query"'
                : 'Sin series en esta categoría',
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ]),
      );
    }

    return Consumer<StorageService>(
      builder: (context, storage, __) {
        final device  = getDeviceInfo(context);
        final cols    = ResponsiveGrid.getGridColumns(device);
        final spacing = ResponsiveSpacing.getItemSpacing(device);

        _focusManager.columnCount = cols;
        _focusManager.resize(_filtered.length);

        return Focus(
          onKeyEvent: (_, e) =>
              _focusManager.handleKey(_filtered.length, e),
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(
                spacing, AppSpacing.sm, spacing, AppSpacing.xxl),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: 0.62,
            ),
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final s     = _filtered[i];
              final isFav = storage.isFavorite(s.id, ContentType.SERIES);
              return _SeriesTile(
                key: ValueKey(s.id),
                series: s,
                isFavorite: isFav,
                focusNode: _focusManager.nodeAt(i),
                onFocused: () => _focusManager.onItemFocused(i),
                onTap: () => widget.onSeriesTap(context, s),
                onFavoriteToggle: () {
                  if (isFav) {
                    storage.removeFavorite(s.id, ContentType.SERIES);
                  } else {
                    storage.saveFavorite(s.id, ContentType.SERIES);
                  }
                },
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SeriesTile
// ─────────────────────────────────────────────────────────────────────────────

class _SeriesTile extends StatefulWidget {
  final Series       series;
  final bool         isFavorite;
  final FocusNode    focusNode;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onFocused;

  const _SeriesTile({
    super.key,
    required this.series,
    required this.isFavorite,
    required this.focusNode,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onFocused,
  });

  @override
  State<_SeriesTile> createState() => _SeriesTileState();
}

class _SeriesTileState extends State<_SeriesTile> {
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    _hasFocus = widget.focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(_SeriesTile old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      old.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
      _hasFocus = widget.focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _hasFocus = widget.focusNode.hasFocus);
    if (widget.focusNode.hasFocus) {
      widget.onFocused();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Scrollable.ensureVisible(context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.select)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              color:
                  _hasFocus ? AppColors.focusBorder : Colors.transparent,
              width: 2,
            ),
            boxShadow: _hasFocus
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
              // Poster
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AppRadius.md)),
                      child: _Poster(
                          url: widget.series.poster,
                          name: widget.series.name),
                    ),
                    Positioned(
                      top: 6, right: 6,
                      child: GestureDetector(
                        onTap: widget.onFavoriteToggle,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppColors.overlay,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            widget.isFavorite
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: widget.isFavorite
                                ? AppColors.error
                                : Colors.white70,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.series.name,
                        style: AppTextStyles.labelLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      if (widget.series.year != null) ...[
                        Text(widget.series.year.toString(),
                            style: AppTextStyles.bodySmall),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      if (widget.series.rating != null) ...[
                        const Icon(Icons.star,
                            size: 12, color: AppColors.warning),
                        const SizedBox(width: 2),
                        Text(widget.series.rating!.toStringAsFixed(1),
                            style: AppTextStyles.bodySmall),
                      ],
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Poster / _PosterFallback
// ─────────────────────────────────────────────────────────────────────────────

class _Poster extends StatelessWidget {
  final String? url;
  final String  name;

  const _Poster({this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _PosterFallback(name: name),
      );
    }
    return _PosterFallback(name: name);
  }
}

class _PosterFallback extends StatelessWidget {
  final String name;
  const _PosterFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surfaceVariant,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library,
              color: AppColors.textDisabled, size: 40),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(name,
                style: AppTextStyles.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
