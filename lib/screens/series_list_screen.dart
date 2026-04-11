import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/progress_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import '../widgets/tv_focus_manager.dart';
import '../widgets/tv_text_field.dart';
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
  final _searchCtrl   = TextEditingController();
  final _focusManager = TvFocusManager();
  String   _query          = '';
  String?  _selectedCat;
  List<Series> _filtered   = [];
  List<String> _categories = [];
  bool     _hasFocusedOnce = false;

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
      _query           = '';
      _selectedCat     = null;
      _hasFocusedOnce  = false;
      _searchCtrl.clear();
      _applyFilter();
    }
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _focusManager.dispose();
    super.dispose();
  }

  // ── Filter ─────────────────────────────────────────────────────────────────

  void _onQueryChanged() {
    if (_searchCtrl.text != _query) {
      setState(() {
        _query = _searchCtrl.text;
        _applyFilter();
      });
    }
  }

  void _applyFilter() {
    final all = widget.playlist?.series ?? [];

    // Build sorted category list from real series data.
    _categories = all
        .map((s) => s.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    // Category filter
    var result = _selectedCat == null
        ? List<Series>.from(all)
        : all.where((s) => s.category.trim() == _selectedCat).toList();

    // Text search
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result
          .where((s) => s.name.toLowerCase().contains(q))
          .toList();
    }

    _filtered = result;

    if (!_hasFocusedOnce && _filtered.isNotEmpty) {
      _hasFocusedOnce = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusManager.focusFirst();
      });
    }
  }

  // ── "Continuar viendo" ─────────────────────────────────────────────────────

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
            entry: entries[i],
            onTap: () => _resumeEpisode(entries[i]),
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

  // ── "Todas" tab ────────────────────────────────────────────────────────────

  Widget _buildAllSeries() {
    return Column(
      children: [
        _buildFilterRow(),
        Expanded(child: _buildGrid()),
      ],
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _searchCtrl,
              hintText: 'Buscar serie...',
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textSecondary, size: 20),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _CategoryDropdown(
            selected: _selectedCat,
            categories: _categories,
            onChanged: (cat) => setState(() {
              _selectedCat = cat;
              _applyFilter();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off,
        message: _query.isNotEmpty || _selectedCat != null
            ? 'Sin resultados'
            : 'Sin series disponibles',
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
                onTap: () => _showDetail(s),
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

  void _showDetail(Series s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SeriesDetailSheet(series: s),
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
              Tab(icon: Icon(Icons.grid_view, size: 18),
                  text: 'Todas'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildContinueWatching(),
                _buildAllSeries(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CategoryDropdown
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryDropdown extends StatelessWidget {
  final String?        selected;
  final List<String>   categories;
  final ValueChanged<String?> onChanged;

  const _CategoryDropdown({
    required this.selected,
    required this.categories,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: AppRadius.chipRadius,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selected,
          dropdownColor: AppColors.surface,
          style: AppTextStyles.bodyMedium,
          icon: const Icon(Icons.filter_list,
              color: AppColors.textSecondary, size: 18),
          hint: const Text('Categoría',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          onChanged: onChanged,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Todas', style: AppTextStyles.bodyMedium),
            ),
            ...categories.map(
              (cat) => DropdownMenuItem<String?>(
                value: cat,
                child: Text(cat,
                    style: AppTextStyles.bodyMedium,
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
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
// SeriesDetailSheet  (public — used by other screens via callback)
// ─────────────────────────────────────────────────────────────────────────────

class SeriesDetailSheet extends StatefulWidget {
  final Series series;
  const SeriesDetailSheet({super.key, required this.series});

  @override
  State<SeriesDetailSheet> createState() => _SeriesDetailSheetState();
}

class _SeriesDetailSheetState extends State<SeriesDetailSheet> {
  late final Set<int> _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.series.seasons.isNotEmpty
        ? {widget.series.seasons.first.seasonNumber}
        : {};
  }

  void _playEpisode(Season season, Episode episode) {
    Navigator.pop(context);

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
        SizedBox(
          height: 200,
          width: double.infinity,
          child: ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: _Poster(url: series.poster, name: series.name,
                fit: BoxFit.cover),
          ),
        ),
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, AppColors.surface],
              stops: const [0.3, 1.0],
            ),
          ),
        ),
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
          if (series.totalEpisodes > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: AppRadius.chipRadius,
                  child: LinearProgressIndicator(
                    value: series.watchProgress,
                    backgroundColor: AppColors.border,
                    valueColor: const AlwaysStoppedAnimation(
                        AppColors.accentSeries),
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
      children: series.seasons.map(_buildSeasonTile).toList(),
    );
  }

  Widget _buildSeasonTile(Season season) {
    final isExpanded = _expanded.contains(season.seasonNumber);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: AppColors.border),
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
          child: Text('T${season.seasonNumber}',
              style: AppTextStyles.labelLarge
                  .copyWith(color: AppColors.accentSeries)),
        ),
        title: Text('Temporada ${season.seasonNumber}',
            style: AppTextStyles.bodyLarge),
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
        shape:
            RoundedRectangleBorder(borderRadius: AppRadius.thumbnailRadius),
        tileColor: AppColors.card,
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: watched
              ? AppColors.success.withValues(alpha: 0.15)
              : AppColors.surfaceVariant,
          child: watched
              ? const Icon(Icons.check, color: AppColors.success, size: 18)
              : Text(episode.episodeNumber.toString(),
                  style: AppTextStyles.labelLarge),
        ),
        title: Text(episode.title,
            style: AppTextStyles.bodyLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
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
      return Image.network(url!, fit: fit,
          errorBuilder: (_, __, ___) => _PosterFallback(name: name));
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
              const Icon(Icons.play_circle_fill,
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
