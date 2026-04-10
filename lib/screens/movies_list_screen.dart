import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/progress_service.dart';
import '../services/search_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import '../widgets/tv_focus_manager.dart';
import '../widgets/tv_text_field.dart';
import 'player_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MoviesListScreen
// ─────────────────────────────────────────────────────────────────────────────

class MoviesListScreen extends StatefulWidget {
  final Playlist? playlist;
  const MoviesListScreen({super.key, this.playlist});

  @override
  State<MoviesListScreen> createState() => _MoviesListScreenState();
}

class _MoviesListScreenState extends State<MoviesListScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl  = TextEditingController();
  final _focusManager = TvFocusManager();
  String _query          = '';
  String _selectedCat    = 'Todas';
  int?   _selectedYear;
  List<Movie> _filtered  = [];
  bool _hasFocusedOnce   = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
    _applyFilter();
  }

  @override
  void didUpdateWidget(MoviesListScreen old) {
    super.didUpdateWidget(old);
    // Full reset only when switching to a different playlist
    if (old.playlist?.id != widget.playlist?.id) {
      _selectedCat  = 'Todas';
      _selectedYear = null;
      _query        = '';
      _searchCtrl.clear();
    }
    // Always re-apply: picks up new content after a refresh of the same playlist
    // (same ID but new movies/categories).
    _applyFilter();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _focusManager.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<Movie> get _all => widget.playlist?.movies ?? [];

  void _onQueryChanged() {
    if (_searchCtrl.text != _query) {
      setState(() {
        _query = _searchCtrl.text;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    final playlist = widget.playlist;
    if (playlist == null) { _filtered = []; return; }

    List<Movie> result = _query.trim().isEmpty
        ? List<Movie>.from(_all)
        : SearchService.instance
            .searchByType(_query, playlist, ContentType.MOVIES)
            .cast<Movie>();

    dev.log(
      '[MoviesListScreen] total=${_all.length} '
      'query="$_query" cat="$_selectedCat" year=$_selectedYear',
      name: 'MoviesListScreen',
    );

    if (_selectedCat != 'Todas') {
      final byCat = result.where((m) => m.category == _selectedCat).toList();
      if (byCat.isEmpty && result.isNotEmpty) {
        // Category no longer exists after a playlist refresh — reset silently.
        dev.log(
          '[MoviesListScreen] Category "$_selectedCat" returned 0 results '
          '(${result.length} movies available) — resetting to Todas',
          name: 'MoviesListScreen',
        );
        _selectedCat = 'Todas';
      } else {
        result = byCat;
      }
    }

    if (_selectedYear != null) {
      result = result.where((m) => m.year == _selectedYear).toList();
    }
    _filtered = result;

    dev.log(
      '[MoviesListScreen] _filtered=${_filtered.length}',
      name: 'MoviesListScreen',
    );

    if (!_hasFocusedOnce && _filtered.isNotEmpty) {
      _hasFocusedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusManager.focusFirst();
      });
    }
  }

  List<String> get _categories {
    final cats = widget.playlist != null
        ? SearchService.instance
            .getCategories(ContentType.MOVIES, widget.playlist!)
        : const <String>[];
    // Guard: if _selectedCat is stale (no longer in the list), snap back to Todas.
    if (_selectedCat != 'Todas' && !cats.contains(_selectedCat)) {
      // Schedule reset after the current build frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedCat != 'Todas') {
          setState(() { _selectedCat = 'Todas'; _applyFilter(); });
        }
      });
    }
    return ['Todas', ...cats];
  }

  List<int> get _years {
    final years = _all.map((m) => m.year).whereType<int>().toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  // ── Detail sheet ───────────────────────────────────────────────────────────

  void _showDetail(Movie movie) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MovieDetailSheet(movie: movie),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.playlist == null) {
      return const _EmptyState(
          icon: Icons.movie, message: 'Agrega una playlist para ver películas');
    }
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.play_circle_outline, size: 18),
                  text: 'Continuar'),
              Tab(icon: Icon(Icons.movie_outlined, size: 18),
                  text: 'Todas'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildContinueWatching(),
                Column(children: [
                  _buildFilterRow(),
                  Expanded(child: _buildGrid()),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueWatching() {
    return Consumer<ProgressService>(
      builder: (context, progress, _) {
        final entries = progress.getRecentlyWatched(
          widget.playlist,
          filterType: ContentType.MOVIES,
        );
        if (entries.isEmpty) {
          return const _EmptyState(
            icon: Icons.play_circle_outline,
            message: 'Aún no has empezado ninguna película',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm, horizontal: AppSpacing.base),
          itemCount: entries.length,
          itemBuilder: (_, i) => _ContinueCard(
            entry: entries[i],
            onTap: () => _resumeMovie(entries[i]),
          ),
        );
      },
    );
  }

  void _resumeMovie(WatchEntry entry) {
    final movie = entry.movie;
    if (movie == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen.movie(
          movie:         movie,
          startPosition: entry.progress.position,
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
      child: Row(children: [
        _FilterDropdown<String>(
          value: _selectedCat,
          items: _categories,
          labelFor: (c) => c,
          onChanged: (v) => setState(() { _selectedCat = v; _applyFilter(); }),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TvTextField(
            controller: _searchCtrl,
            hintText: 'Buscar película...',
            prefixIcon: const Icon(Icons.search,
                color: AppColors.textSecondary, size: 20),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _FilterDropdown<int?>(
          value: _selectedYear,
          items: [null, ..._years],
          labelFor: (y) => y == null ? 'Año' : y.toString(),
          onChanged: (v) => setState(() { _selectedYear = v; _applyFilter(); }),
        ),
      ]),
    );
  }

  Widget _buildGrid() {
    if (_filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off,
        message: _query.isNotEmpty
            ? 'Sin resultados para "$_query"'
            : 'Sin películas en esta categoría',
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
          onKeyEvent: (_, e) => _focusManager.handleKey(_filtered.length, e),
          child: GridView.builder(
            padding: EdgeInsets.fromLTRB(spacing, AppSpacing.sm, spacing, AppSpacing.xxl),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: 0.62,
            ),
            itemCount: _filtered.length,
            itemBuilder: (_, i) {
              final m = _filtered[i];
              final isFav = storage.isFavorite(m.id, ContentType.MOVIES);
              return _MovieTile(
                key: ValueKey(m.id),
                movie: m,
                isFavorite: isFav,
                focusNode: _focusManager.nodeAt(i),
                onFocused: () => _focusManager.onItemFocused(i),
                onTap: () => _showDetail(m),
                onFavoriteToggle: () => isFav
                    ? storage.removeFavorite(m.id, ContentType.MOVIES)
                    : storage.saveFavorite(m.id, ContentType.MOVIES),
              );
            },
          ),
        );
      },
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// _MovieTile — tarjeta con foco gestionado por TvFocusManager
// ─────────────────────────────────────────────────────────────────────────────

class _MovieTile extends StatefulWidget {
  final Movie        movie;
  final bool         isFavorite;
  final FocusNode    focusNode;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;
  final VoidCallback onFocused;

  const _MovieTile({
    super.key,
    required this.movie,
    required this.isFavorite,
    required this.focusNode,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onFocused,
  });

  @override
  State<_MovieTile> createState() => _MovieTileState();
}

class _MovieTileState extends State<_MovieTile> {
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    _hasFocus = widget.focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(_MovieTile old) {
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
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
          );
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
              color: _hasFocus ? AppColors.focusBorder : Colors.transparent,
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
              Expanded(
                child: Stack(fit: StackFit.expand, children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(AppRadius.md)),
                    child: _Poster(url: widget.movie.poster, name: widget.movie.title),
                  ),
                  // Watched badge
                  if (StorageService.instance
                      .getHistory(ContentType.MOVIES)
                      .any((e) => e.id == widget.movie.id))
                    Positioned(
                      top: 6, left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.85),
                          borderRadius: AppRadius.chipRadius,
                        ),
                        child: const Text('VISTO',
                            style: AppTextStyles.badge),
                      ),
                    ),
                  // Favorite button
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
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.movie.title,
                        style: AppTextStyles.labelLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      if (widget.movie.year != null) ...[
                        Text(widget.movie.year.toString(),
                            style: AppTextStyles.bodySmall),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                      if (widget.movie.rating != null) ...[
                        const Icon(Icons.star,
                            size: 12, color: AppColors.warning),
                        const SizedBox(width: 2),
                        Text(widget.movie.rating!.toStringAsFixed(1),
                            style: AppTextStyles.bodySmall),
                      ],
                      if (widget.movie.durationLabel != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(Icons.access_time,
                            size: 12, color: AppColors.textDisabled),
                        const SizedBox(width: 2),
                        Text(widget.movie.durationLabel!,
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
// MovieDetailSheet  (public — also used by SearchScreen)
// ─────────────────────────────────────────────────────────────────────────────

class MovieDetailSheet extends StatelessWidget {
  final Movie movie;
  const MovieDetailSheet({super.key, required this.movie});

  Duration? get _savedPosition =>
      StorageService.instance.getLastPosition(movie.id, ContentType.MOVIES);

  bool get _hasProgress {
    final pos = _savedPosition;
    return pos != null && pos.inSeconds > 5;
  }

  double get _progressValue {
    final pos = _savedPosition;
    final dur = movie.duration;
    if (pos == null || dur == null || dur.inMilliseconds == 0) return 0;
    return (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
  }

  void _play(BuildContext context, {bool fromStart = false}) {
    final pos = fromStart ? null : _savedPosition;
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen.movie(
          movie:         movie,
          startPosition: (pos != null && pos.inSeconds > 5) ? pos : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildBody(context)),
            const SliverPadding(
                padding: EdgeInsets.only(bottom: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Stack(children: [
      // Backdrop
      SizedBox(
        height: 220,
        width: double.infinity,
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          child: _Poster(url: movie.poster, name: movie.title,
              fit: BoxFit.cover),
        ),
      ),
      // Gradient
      Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, AppColors.surface],
            stops: const [0.25, 1.0],
          ),
        ),
      ),
      // Drag handle
      Positioned(
        top: 10, left: 0, right: 0,
        child: Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: AppRadius.chipRadius,
            ),
          ),
        ),
      ),
      // Close
      Positioned(
        top: 8, right: 8,
        child: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, color: Colors.white70),
          style: IconButton.styleFrom(backgroundColor: AppColors.overlay),
        ),
      ),
    ]);
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.sm,
          AppSpacing.base, AppSpacing.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + favorite
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(movie.title,
                    style: AppTextStyles.headlineMedium),
              ),
              Consumer<StorageService>(
                builder: (_, storage, __) {
                  final isFav =
                      storage.isFavorite(movie.id, ContentType.MOVIES);
                  return IconButton(
                    onPressed: () => isFav
                        ? storage.removeFavorite(movie.id, ContentType.MOVIES)
                        : storage.saveFavorite(movie.id, ContentType.MOVIES),
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? AppColors.error : AppColors.textSecondary,
                    ),
                    tooltip: isFav ? 'Quitar favorito' : 'Agregar favorito',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Meta chips
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (movie.year != null)
                _MetaChip(
                    label: movie.year.toString(),
                    icon: Icons.calendar_today),
              if (movie.rating != null)
                _MetaChip(
                    label: movie.rating!.toStringAsFixed(1),
                    icon: Icons.star,
                    color: AppColors.warning),
              if (movie.durationLabel != null)
                _MetaChip(
                    label: movie.durationLabel!,
                    icon: Icons.access_time),
              _MetaChip(
                  label: movie.category,
                  icon: Icons.category_outlined),
              if (movie.watched)
                _MetaChip(
                    label: 'Vista',
                    icon: Icons.check_circle_outline,
                    color: AppColors.success),
            ],
          ),

          // Progress bar (if partially watched)
          if (_hasProgress) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.chipRadius,
                  child: LinearProgressIndicator(
                    value: _progressValue,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(
                        AppColors.accentMovies),
                    minHeight: 5,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${_fmtDur(_savedPosition!)} / '
                '${movie.durationLabel ?? "?"}',
                style: AppTextStyles.bodySmall,
              ),
            ]),
          ],

          if (movie.description != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(movie.description!,
                style: AppTextStyles.bodyMedium,
                maxLines: 5,
                overflow: TextOverflow.ellipsis),
          ],

          const SizedBox(height: AppSpacing.lg),
          const Divider(color: AppColors.border),
          const SizedBox(height: AppSpacing.md),

          // ── Play buttons ─────────────────────────────────────────────
          if (_hasProgress) ...[
            // CONTINUAR button (primary)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _play(context),
                icon: const Icon(Icons.play_arrow, size: 24),
                label: Text(
                  'Continuar desde ${_fmtDur(_savedPosition!)}',
                  style: AppTextStyles.labelLarge,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentMovies,
                  foregroundColor: AppColors.textInverse,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonRadius),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // DESDE EL INICIO (secondary)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _play(context, fromStart: true),
                icon: const Icon(Icons.replay, size: 20),
                label: Text('Desde el inicio',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: AppColors.textSecondary)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonRadius),
                ),
              ),
            ),
          ] else ...[
            // PLAY button (no prior position)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _play(context, fromStart: true),
                icon: const Icon(Icons.play_arrow, size: 26),
                label: const Text('Reproducir',
                    style: AppTextStyles.labelLarge),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentMovies,
                  foregroundColor: AppColors.textInverse,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.buttonRadius),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private reusable widgets (local to this file)
// ─────────────────────────────────────────────────────────────────────────────

class _Poster extends StatelessWidget {
  final String? url;
  final String  name;
  final BoxFit  fit;

  const _Poster({this.url, required this.name, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        fit: fit,
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie, color: AppColors.textDisabled, size: 40),
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
        ]),
      );
}

class _MetaChip extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;

  const _MetaChip({
    required this.label,
    required this.icon,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.chipRadius,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: AppTextStyles.labelSmall.copyWith(color: color)),
      ]),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final T           value;
  final List<T>     items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.buttonRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: AppColors.card,
          style: AppTextStyles.bodyMedium,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down,
              color: AppColors.textSecondary),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelFor(item),
                        style: AppTextStyles.bodyMedium),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null || null is T) onChanged(v as T);
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContinueCard  — shared "Continuar viendo" row card
// ─────────────────────────────────────────────────────────────────────────────

class _ContinueCard extends StatelessWidget {
  final WatchEntry   entry;
  final VoidCallback onTap;

  const _ContinueCard({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progress = entry.progress;
    final pct      = (progress.progressFraction * 100).round();

    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              // Poster
              ClipRRect(
                borderRadius: AppRadius.thumbnailRadius,
                child: SizedBox(
                  width: 60, height: 88,
                  child: entry.poster != null && entry.poster!.isNotEmpty
                      ? Image.network(entry.poster!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _PosterPlaceholder(icon: Icons.movie))
                      : _PosterPlaceholder(icon: Icons.movie),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title,
                        style: AppTextStyles.labelLarge,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(entry.subtitle,
                          style: AppTextStyles.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: AppRadius.chipRadius,
                      child: LinearProgressIndicator(
                        value: progress.progressFraction,
                        backgroundColor: AppColors.border,
                        valueColor: const AlwaysStoppedAnimation(
                            AppColors.accentMovies),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text('$pct% completado',
                          style: AppTextStyles.bodySmall),
                      const Spacer(),
                      Text(_timeAgo(progress.lastWatched),
                          style: AppTextStyles.bodySmall),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Play button
              Icon(Icons.play_circle_fill,
                  color: AppColors.accentMovies, size: 40),
            ],
          ),
        ),
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24)   return 'Hace ${diff.inHours} h';
    return 'Hace ${diff.inDays} d';
  }
}

class _PosterPlaceholder extends StatelessWidget {
  final IconData icon;
  const _PosterPlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.textDisabled, size: 32),
      );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: AppColors.textDisabled),
          const SizedBox(height: AppSpacing.base),
          Text(message,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center),
        ]),
      );
}
