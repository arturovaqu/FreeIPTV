import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/progress_service.dart';
import '../services/search_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import 'player_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SeriesListScreen
// ─────────────────────────────────────────────────────────────────────────────

class SeriesListScreen extends StatefulWidget {
  final Playlist? playlist;
  const SeriesListScreen({super.key, this.playlist});

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl  = TextEditingController();
  String _query           = '';
  String _selectedCat     = 'Todas';
  int?   _selectedYear;
  List<Series> _filtered  = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
    _applyFilter();
  }

  @override
  void didUpdateWidget(SeriesListScreen old) {
    super.didUpdateWidget(old);
    if (old.playlist?.id != widget.playlist?.id) {
      _selectedCat  = 'Todas';
      _selectedYear = null;
      _query        = '';
      _searchCtrl.clear();
      _applyFilter();
    }
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<Series> get _all => widget.playlist?.series ?? [];

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

    // 1. Base list: all series or search results
    List<Series> result = _query.trim().isEmpty
        ? List<Series>.from(_all)
        : SearchService.instance
            .searchByType(_query, playlist, ContentType.SERIES)
            .cast<Series>();

    // 2. Category filter (trim both sides so whitespace differences don't break it)
    if (_selectedCat != 'Todas') {
      final cat = _selectedCat.trim();
      result = result
          .where((s) => s.category.trim() == cat)
          .toList();

      // If the selected category produced no results (e.g. because the search
      // already narrowed the list), reset to "Todas" automatically so the user
      // is not left staring at an empty screen.
      if (result.isEmpty) {
        _selectedCat = 'Todas';
        result = _query.trim().isEmpty
            ? List<Series>.from(_all)
            : SearchService.instance
                .searchByType(_query, playlist, ContentType.SERIES)
                .cast<Series>();
      }
    }

    // 3. Year filter
    if (_selectedYear != null) {
      result = result.where((s) => s.year == _selectedYear).toList();
    }

    _filtered = result;
  }

  List<String> get _categories {
    if (widget.playlist == null) return [];
    return [
      'Todas',
      ...SearchService.instance.getCategories(ContentType.SERIES, widget.playlist!),
    ];
  }

  List<int> get _years {
    final years = _all.map((s) => s.year).whereType<int>().toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    return years;
  }

  // ── Detail sheet ───────────────────────────────────────────────────────────

  void _showDetail(BuildContext context, Series series) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SeriesDetailSheet(series: series),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.playlist == null) {
      return _EmptyState(
          icon: Icons.video_library,
          message: 'Agrega una playlist para ver series');
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.play_circle_outline, size: 18),
                  text: 'Continuar'),
              Tab(icon: Icon(Icons.video_library_outlined, size: 18),
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
          filterType: ContentType.SERIES,
        );
        if (entries.isEmpty) {
          return _EmptyState(
            icon: Icons.play_circle_outline,
            message: 'Aún no has empezado ninguna serie',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.sm, horizontal: AppSpacing.base),
          itemCount: entries.length,
          itemBuilder: (_, i) => _ContinueCard(
            entry:  entries[i],
            onTap:  () => _resumeEpisode(entries[i]),
          ),
        );
      },
    );
  }

  void _resumeEpisode(WatchEntry entry) {
    final series  = entry.series;
    final season  = entry.season;
    final episode = entry.episode;
    if (series == null || season == null || episode == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen.series(
          series:        series,
          season:        season,
          episode:       episode,
          startPosition: entry.progress.position,
        ),
      ),
    );
  }

  // ── Filter row ─────────────────────────────────────────────────────────────

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
      child: Row(
        children: [
          // Category dropdown
          _FilterDropdown<String>(
            value: _selectedCat,
            items: _categories,
            labelFor: (c) => c,
            onChanged: (v) => setState(() { _selectedCat = v; _applyFilter(); }),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Search field (flexible)
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppTextStyles.bodyLarge,
              decoration: InputDecoration(
                hintText: 'Buscar serie...',
                hintStyle: AppTextStyles.bodyMedium,
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppColors.textSecondary, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: AppColors.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.sm, horizontal: AppSpacing.base),
                border: _inputBorder(),
                enabledBorder: _inputBorder(),
                focusedBorder: _inputBorder(color: AppColors.accent, width: 2),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Year dropdown
          _FilterDropdown<int?>(
            value: _selectedYear,
            items: [null, ..._years],
            labelFor: (y) => y == null ? 'Año' : y.toString(),
            onChanged: (v) => setState(() { _selectedYear = v; _applyFilter(); }),
          ),
        ],
      ),
    );
  }

  // ── Grid ───────────────────────────────────────────────────────────────────

  Widget _buildGrid() {
    if (_filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off,
        message: _query.isNotEmpty
            ? 'Sin resultados para "$_query"'
            : 'Sin series en esta categoría',
      );
    }

    return Consumer<StorageService>(
      builder: (context, storage, __) {
        final device  = getDeviceInfo(context);
        final cols    = ResponsiveGrid.getGridColumns(device);
        final spacing = ResponsiveSpacing.getItemSpacing(device);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(spacing, AppSpacing.sm, spacing, AppSpacing.xxl),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: 0.62,
          ),
          itemCount: _filtered.length,
          itemBuilder: (_, i) {
            final s = _filtered[i];
            return _SeriesCard(
              series: s,
              isFavorite: storage.isFavorite(s.id, ContentType.SERIES),
              onTap: () => _showDetail(context, s),
              onFavoriteToggle: () {
                if (storage.isFavorite(s.id, ContentType.SERIES)) {
                  storage.removeFavorite(s.id, ContentType.SERIES);
                } else {
                  storage.saveFavorite(s.id, ContentType.SERIES);
                }
              },
            );
          },
        );
      },
    );
  }

  static OutlineInputBorder _inputBorder({
    Color color = AppColors.border,
    double width = 1,
  }) =>
      OutlineInputBorder(
        borderRadius: AppRadius.buttonRadius,
        borderSide: BorderSide(color: color, width: width),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SeriesCard
// ─────────────────────────────────────────────────────────────────────────────

class _SeriesCard extends StatelessWidget {
  final Series series;
  final bool   isFavorite;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const _SeriesCard({
    required this.series,
    required this.isFavorite,
    required this.onTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            e.logicalKey == LogicalKeyboardKey.enter) {
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
                color: focused ? AppColors.focusBorder : Colors.transparent,
                width: 2,
              ),
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
                        child: _Poster(url: series.poster, name: series.name),
                      ),
                      // Favorite button overlay
                      Positioned(
                        top: 6, right: 6,
                        child: GestureDetector(
                          onTap: onFavoriteToggle,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: AppColors.overlay,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isFavorite
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
                      Text(series.name,
                          style: AppTextStyles.labelLarge,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(children: [
                        if (series.year != null) ...[
                          Text(series.year.toString(),
                              style: AppTextStyles.bodySmall),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (series.rating != null) ...[
                          const Icon(Icons.star,
                              size: 12, color: AppColors.warning),
                          const SizedBox(width: 2),
                          Text(series.rating!.toStringAsFixed(1),
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

// ─────────────────────────────────────────────────────────────────────────────
// SeriesDetailSheet  (public — also used by SearchScreen)
// ─────────────────────────────────────────────────────────────────────────────

class SeriesDetailSheet extends StatefulWidget {
  final Series series;
  const SeriesDetailSheet({super.key, required this.series});

  @override
  State<SeriesDetailSheet> createState() => _SeriesDetailSheetState();
}

class _SeriesDetailSheetState extends State<SeriesDetailSheet> {
  late final Set<int> _expanded; // season numbers expanded by default

  @override
  void initState() {
    super.initState();
    // Auto-expand season 1 (or the only season)
    _expanded = widget.series.seasons.isNotEmpty
        ? {widget.series.seasons.first.seasonNumber}
        : {};
  }

  void _playEpisode(Season season, Episode episode) {
    Navigator.pop(context); // close sheet first

    final episodeId =
        '${widget.series.id}_S${season.seasonNumber}E${episode.episodeNumber}';
    final savedPos = StorageService.instance
        .getLastPosition(episodeId, ContentType.SERIES);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen.series(
          series:        widget.series,
          season:        season,
          episode:       episode,
          startPosition: (savedPos != null && savedPos.inSeconds > 5)
              ? savedPos
              : null,
        ),
      ),
    );
  }

  bool _isWatched(Season season, Episode episode) {
    final id =
        '${widget.series.id}_S${season.seasonNumber}E${episode.episodeNumber}';
    return StorageService.instance
        .getHistory(ContentType.SERIES)
        .any((e) => e.id == id);
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: CustomScrollView(
          controller: scrollCtrl,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context, series)),
            SliverToBoxAdapter(child: _buildMeta(series)),
            SliverToBoxAdapter(child: _buildSeasonList(series)),
            const SliverPadding(
                padding: EdgeInsets.only(bottom: AppSpacing.xxl)),
          ],
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, Series series) {
    return Stack(
      children: [
        // Blurred backdrop
        SizedBox(
          height: 200,
          width: double.infinity,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: _Poster(
              url: series.poster,
              name: series.name,
              fit: BoxFit.cover,
            ),
          ),
        ),
        // Gradient overlay
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                AppColors.surface,
              ],
              stops: const [0.3, 1.0],
            ),
          ),
        ),
        // Drag handle
        Positioned(
          top: 10,
          left: 0, right: 0,
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
            style: IconButton.styleFrom(
              backgroundColor: AppColors.overlay,
            ),
          ),
        ),
        // Favorite (bottom-right of header)
        Positioned(
          bottom: 12, right: 16,
          child: Consumer<StorageService>(
            builder: (_, storage, __) {
              final isFav =
                  storage.isFavorite(series.id, ContentType.SERIES);
              return IconButton.filled(
                onPressed: () {
                  if (isFav) {
                    storage.removeFavorite(series.id, ContentType.SERIES);
                  } else {
                    storage.saveFavorite(series.id, ContentType.SERIES);
                  }
                },
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? AppColors.error : Colors.white,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: isFav
                      ? Colors.red.withValues(alpha: 0.2)
                      : AppColors.card,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Meta ───────────────────────────────────────────────────────────────────

  Widget _buildMeta(Series series) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.sm,
          AppSpacing.base, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(series.name, style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (series.year != null)
                _MetaChip(label: series.year.toString(),
                    icon: Icons.calendar_today),
              if (series.rating != null)
                _MetaChip(
                    label: series.rating!.toStringAsFixed(1),
                    icon: Icons.star,
                    color: AppColors.warning),
              _MetaChip(label: series.category,
                  icon: Icons.category_outlined),
              _MetaChip(
                  label: '${series.seasons.length} temp. · '
                      '${series.totalEpisodes} ep.',
                  icon: Icons.layers_outlined),
            ],
          ),
          if (series.description != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(series.description!,
                style: AppTextStyles.bodyMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
          ],
          // Watch progress
          if (series.totalEpisodes > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.chipRadius,
                  child: LinearProgressIndicator(
                    value: series.watchProgress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(AppColors.accentSeries),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${series.watchedEpisodes}/${series.totalEpisodes}',
                style: AppTextStyles.bodySmall,
              ),
            ]),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Divider(color: AppColors.border),
        ],
      ),
    );
  }

  // ── Season list ────────────────────────────────────────────────────────────

  Widget _buildSeasonList(Series series) {
    if (series.seasons.isEmpty) {
      return const Padding(
        padding: AppSpacing.paddingBase,
        child: Text('Sin temporadas disponibles',
            style: AppTextStyles.bodyMedium),
      );
    }

    return Column(
      children: series.seasons
          .map((season) => _buildSeasonTile(season))
          .toList(),
    );
  }

  Widget _buildSeasonTile(Season season) {
    final isExpanded = _expanded.contains(season.seasonNumber);

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: AppColors.border,
      ),
      child: ExpansionTile(
        initiallyExpanded: isExpanded,
        onExpansionChanged: (open) {
          setState(() {
            if (open) {
              _expanded.add(season.seasonNumber);
            } else {
              _expanded.remove(season.seasonNumber);
            }
          });
        },
        tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.xs),
        leading: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.accentSeries.withValues(alpha: 0.15),
            borderRadius: AppRadius.thumbnailRadius,
          ),
          alignment: Alignment.center,
          child: Text(
            'T${season.seasonNumber}',
            style: AppTextStyles.labelLarge
                .copyWith(color: AppColors.accentSeries),
          ),
        ),
        title: Text(
          'Temporada ${season.seasonNumber}',
          style: AppTextStyles.bodyLarge,
        ),
        subtitle: Text(
          '${season.episodes.length} episodios · '
          '${season.watchedCount} vistos',
          style: AppTextStyles.bodySmall,
        ),
        iconColor: AppColors.textSecondary,
        collapsedIconColor: AppColors.textDisabled,
        children: season.episodes
            .map((ep) => _buildEpisodeTile(season, ep))
            .toList(),
      ),
    );
  }

  Widget _buildEpisodeTile(Season season, Episode episode) {
    final watched = _isWatched(season, episode);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.sm),
        shape: RoundedRectangleBorder(
            borderRadius: AppRadius.thumbnailRadius),
        tileColor: AppColors.card,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: watched
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.surfaceVariant,
          child: watched
              ? const Icon(Icons.check,
                  color: AppColors.success, size: 18)
              : Text(
                  episode.episodeNumber.toString(),
                  style: AppTextStyles.labelLarge,
                ),
        ),
        title: Text(
          episode.title,
          style: AppTextStyles.bodyLarge,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: episode.duration != null
            ? Text(_formatDuration(episode.duration!),
                style: AppTextStyles.bodySmall)
            : null,
        trailing: SizedBox(
          width: 56,
          child: ElevatedButton(
            onPressed: () => _playEpisode(season, episode),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentSeries,
              foregroundColor: Colors.white,
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 44),
              shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.buttonRadius),
            ),
            child: const Icon(Icons.play_arrow, size: 20),
          ),
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Poster extends StatelessWidget {
  final String?  url;
  final String   name;
  final BoxFit   fit;

  const _Poster({this.url, required this.name, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (url != null && url!.isNotEmpty) {
      return Image.network(
        url!,
        fit: fit,
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              name,
              style: AppTextStyles.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: AppTextStyles.labelSmall.copyWith(color: color)),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: 4),
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
          items: items.map((item) => DropdownMenuItem<T>(
            value: item,
            child: Text(labelFor(item), style: AppTextStyles.bodyMedium),
          )).toList(),
          onChanged: (v) { if (v != null || null is T) onChanged(v as T); },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContinueCard  — "Continuar viendo" row card for series episodes
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
                                _PosterPlaceholder(icon: Icons.video_library))
                      : _PosterPlaceholder(icon: Icons.video_library),
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
                            AppColors.accentSeries),
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
                  color: AppColors.accentSeries, size: 40),
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
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 64, color: AppColors.textDisabled),
        const SizedBox(height: AppSpacing.base),
        Text(message,
            style: AppTextStyles.bodyMedium,
            textAlign: TextAlign.center),
      ]),
    );
  }
}
