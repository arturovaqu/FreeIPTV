import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/models.dart';
import '../services/search_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import 'movies_list_screen.dart' show MovieDetailSheet;
import 'player_screen.dart';
import 'series_list_screen.dart' show SeriesDetailSheet;

// ─────────────────────────────────────────────────────────────────────────────
// SearchScreen
// ────────────────────────────────────────────────────────────────────────���────

class SearchScreen extends StatefulWidget {
  final Playlist? playlist;
  const SearchScreen({super.key, this.playlist});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  // ── Filter state ───────��─────────────────────────────────────────────────
  String  _query       = '';
  String  _typeFilter  = 'Todos'; // 'Todos' | 'TV' | 'SERIES' | 'MOVIES'
  String  _categoryFilter = 'Todas';
  int?    _yearFilter;
  String  _sortBy      = 'relevance'; // 'relevance' | 'name' | 'rating' | 'year'
  bool    _filtersOpen = false;

  // ── Results ───────────────────────────────────────────────────────────────
  List<Channel> _tvResults    = [];
  List<Series>  _seriesResults = [];
  List<Movie>   _movieResults  = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onQueryChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Search logic ───────────────────────────��──────────────────────────────

  void _onQueryChanged() {
    final q = _searchCtrl.text;
    if (q == _query) return;
    setState(() {
      _query = q;
      _runSearch();
    });
  }

  void _setQuery(String q) {
    _searchCtrl.text = q;
    _searchCtrl.selection =
        TextSelection.collapsed(offset: q.length);
    _query = q;
    _runSearch();
    setState(() {});
  }

  void _runSearch() {
    final playlist = widget.playlist;
    if (playlist == null || _query.trim().isEmpty) {
      _tvResults = [];
      _seriesResults = [];
      _movieResults = [];
      return;
    }

    final ss = SearchService.instance;

    // 1. Raw fuzzy search per active type filter
    List<Channel> tv     = [];
    List<Series>  series = [];
    List<Movie>   movies = [];

    if (_typeFilter == 'Todos' || _typeFilter == 'TV') {
      tv = ss.searchByType(_query, playlist, ContentType.TV).cast();
    }
    if (_typeFilter == 'Todos' || _typeFilter == 'SERIES') {
      series = ss.searchByType(_query, playlist, ContentType.SERIES).cast();
    }
    if (_typeFilter == 'Todos' || _typeFilter == 'MOVIES') {
      movies = ss.searchByType(_query, playlist, ContentType.MOVIES).cast();
    }

    // 2. Category filter
    if (_categoryFilter != 'Todas') {
      tv     = tv.where((c) => c.group == _categoryFilter).toList();
      series = series.where((s) => s.category == _categoryFilter).toList();
      movies = movies.where((m) => m.category == _categoryFilter).toList();
    }

    // 3. Year filter
    if (_yearFilter != null) {
      series = series.where((s) => s.year == _yearFilter).toList();
      movies = movies.where((m) => m.year == _yearFilter).toList();
    }

    // 4. Sort (skip for relevance — already sorted by fuzzy score)
    if (_sortBy != 'relevance') {
      tv     = ss.sortContent(tv,     _sortBy).cast();
      series = ss.sortContent(series, _sortBy).cast();
      movies = ss.sortContent(movies, _sortBy).cast();
    }

    _tvResults     = tv;
    _seriesResults = series;
    _movieResults  = movies;
  }

  bool get _hasResults =>
      _tvResults.isNotEmpty ||
      _seriesResults.isNotEmpty ||
      _movieResults.isNotEmpty;

  // ── Categories for filter dropdown ───────────────────────────────────────

  List<String> _categoriesFor(String type) {
    final playlist = widget.playlist;
    if (playlist == null) return ['Todas'];
    final ss = SearchService.instance;
    switch (type) {
      case 'TV':
        return ['Todas', ...ss.getCategories(ContentType.TV, playlist)];
      case 'SERIES':
        return ['Todas', ...ss.getCategories(ContentType.SERIES, playlist)];
      case 'MOVIES':
        return ['Todas', ...ss.getCategories(ContentType.MOVIES, playlist)];
      default:
        // Todos — union of all categories
        final all = {
          ...ss.getCategories(ContentType.TV, playlist),
          ...ss.getCategories(ContentType.SERIES, playlist),
          ...ss.getCategories(ContentType.MOVIES, playlist),
        }.toList()..sort();
        return ['Todas', ...all];
    }
  }

  List<int> get _availableYears {
    final playlist = widget.playlist;
    if (playlist == null) return [];
    final years = {
      ...playlist.series.map((s) => s.year).whereType<int>(),
      ...playlist.movies.map((m) => m.year).whereType<int>(),
    }.toList()..sort((a, b) => b.compareTo(a));
    return years;
  }

  // ── Navigation ─────────────────────────────────���──────────────────────────

  void _openChannel(Channel ch) {
    SearchService.instance.addRecentSearch(_query);
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PlayerScreen.channel(channel: ch)));
  }

  void _openSeries(Series s) {
    SearchService.instance.addRecentSearch(_query);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SeriesDetailSheet(series: s),
    );
  }

  void _openMovie(Movie m) {
    SearchService.instance.addRecentSearch(_query);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MovieDetailSheet(movie: m),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────��──────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      _buildSearchBar(),
      _buildAdvancedFilters(),
      Expanded(child: _buildBody()),
    ]);
  }

  // ── Search bar ────────────────────────────────���───────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.xs),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            style: AppTextStyles.searchInput,
            autofocus: false,
            decoration: InputDecoration(
              hintText: 'Buscar canales, series, películas...',
              hintStyle: AppTextStyles.bodyMedium,
              prefixIcon: const Icon(Icons.search,
                  color: AppColors.textSecondary, size: 22),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear,
                          color: AppColors.textSecondary),
                      onPressed: () {
                        _searchCtrl.clear();
                        _searchFocus.unfocus();
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md, horizontal: AppSpacing.base),
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: _border(color: AppColors.accent, width: 2),
            ),
            onSubmitted: (q) {
              if (q.trim().isNotEmpty) {
                SearchService.instance.addRecentSearch(q.trim());
              }
              _searchFocus.unfocus();
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        // Filter toggle button
        AnimatedContainer(
          duration: AppDurations.fast,
          decoration: BoxDecoration(
            color: _filtersOpen ? AppColors.accent : AppColors.surfaceVariant,
            borderRadius: AppRadius.buttonRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: IconButton(
            icon: Icon(Icons.tune,
                color: _filtersOpen
                    ? AppColors.textInverse
                    : AppColors.textSecondary),
            tooltip: 'Filtros avanzados',
            onPressed: () =>
                setState(() => _filtersOpen = !_filtersOpen),
          ),
        ),
      ]),
    );
  }

  // ── Advanced filters ─────────────────────────────���────────────────────────

  Widget _buildAdvancedFilters() {
    if (!_filtersOpen) return const SizedBox.shrink();

    final cats = _categoriesFor(_typeFilter);
    final years = _availableYears;

    return AnimatedSize(
      duration: AppDurations.normal,
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.base, vertical: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filtros', style: AppTextStyles.labelLarge),
            const SizedBox(height: AppSpacing.md),
            // Row 1: type + category
            Row(children: [
              Expanded(
                child: _LabeledDropdown<String>(
                  label: 'Tipo',
                  value: _typeFilter,
                  items: const ['Todos', 'TV', 'SERIES', 'MOVIES'],
                  labelFor: (v) => v,
                  onChanged: (v) => setState(() {
                    _typeFilter = v;
                    _categoryFilter = 'Todas'; // reset on type change
                    _runSearch();
                  }),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _LabeledDropdown<String>(
                  label: 'Categoría',
                  value: cats.contains(_categoryFilter)
                      ? _categoryFilter
                      : 'Todas',
                  items: cats,
                  labelFor: (v) => v,
                  onChanged: (v) => setState(() {
                    _categoryFilter = v;
                    _runSearch();
                  }),
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            // Row 2: year + sort
            Row(children: [
              Expanded(
                child: _LabeledDropdown<int?>(
                  label: 'Año',
                  value: _yearFilter,
                  items: [null, ...years],
                  labelFor: (y) => y == null ? 'Todos' : y.toString(),
                  onChanged: (v) => setState(() {
                    _yearFilter = v;
                    _runSearch();
                  }),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _LabeledDropdown<String>(
                  label: 'Ordenar por',
                  value: _sortBy,
                  items: const ['relevance', 'name', 'rating', 'year'],
                  labelFor: (v) => switch (v) {
                    'relevance' => 'Relevancia',
                    'name'      => 'Nombre',
                    'rating'    => 'Rating',
                    'year'      => 'Año',
                    _           => v,
                  },
                  onChanged: (v) => setState(() {
                    _sortBy = v;
                    _runSearch();
                  }),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Body ───────────────────────────���─────────────────────────────────��────

  Widget _buildBody() {
    if (widget.playlist == null) {
      return const _EmptyState(
          icon: Icons.search,
          message: 'Agrega una playlist para buscar contenido');
    }

    if (_query.trim().isEmpty) {
      return _buildRecentSearches();
    }

    if (!_hasResults) {
      return _buildNoResults();
    }

    return _buildResults();
  }

  // ── Recent searches ────────────────────────────��──────────────────────────

  Widget _buildRecentSearches() {
    final recents = SearchService.instance.getRecentSearches();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.md,
          AppSpacing.base, AppSpacing.xxl),
      children: [
        if (recents.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xl),
            child: _EmptyState(
              icon: Icons.history,
              message: 'Aún no hay búsquedas recientes',
            ),
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Búsquedas recientes',
                  style: AppTextStyles.headlineSmall),
              TextButton(
                onPressed: () => setState(() {
                  SearchService.instance.clearRecentSearches();
                }),
                child: const Text('Borrar',
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...recents.map((q) => ListTile(
                leading: const Icon(Icons.history,
                    color: AppColors.textDisabled, size: 20),
                title: Text(q, style: AppTextStyles.bodyLarge),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.thumbnailRadius),
                trailing: const Icon(Icons.north_west,
                    color: AppColors.textDisabled, size: 16),
                onTap: () => _setQuery(q),
              )),
        ],
      ],
    );
  }

  // ── No results ────────────��───────────────────────────────────────────────

  Widget _buildNoResults() {
    final playlist = widget.playlist!;
    final topSeries = (List<Series>.from(playlist.series)
          ..sort((a, b) =>
              (b.rating ?? 0).compareTo(a.rating ?? 0)))
        .take(6)
        .toList();
    final topMovies = (List<Movie>.from(playlist.movies)
          ..sort((a, b) =>
              (b.rating ?? 0).compareTo(a.rating ?? 0)))
        .take(6)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.base, AppSpacing.lg,
          AppSpacing.base, AppSpacing.xxl),
      children: [
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off,
                size: 56, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text('No se encontró nada para',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 4),
            Text('"$_query"',
                style: AppTextStyles.headlineSmall,
                textAlign: TextAlign.center),
          ]),
        ),
        if (topSeries.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          _SectionHeader(label: 'Top Series'),
          const SizedBox(height: AppSpacing.sm),
          _HorizontalPosterRow(
            items: topSeries,
            nameOf: (s) => s.name,
            yearOf: (s) => s.year,
            posterOf: (s) => s.poster,
            onTap: (s) => _openSeries(s as Series),
          ),
        ],
        if (topMovies.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _SectionHeader(label: 'Top Películas'),
          const SizedBox(height: AppSpacing.sm),
          _HorizontalPosterRow(
            items: topMovies,
            nameOf: (m) => (m as Movie).title,
            yearOf: (m) => m.year,
            posterOf: (m) => m.poster,
            onTap: (m) => _openMovie(m as Movie),
          ),
        ],
      ],
    );
  }

  // ── Results ─────────────────────────────��─────────────────────────────────

  Widget _buildResults() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, AppSpacing.xxl),
      children: [
        if (_tvResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.md, AppSpacing.base, AppSpacing.sm),
            child: _SectionHeader(
                label: 'Canales',
                count: _tvResults.length),
          ),
          _HorizontalChannelRow(
            channels: _tvResults,
            onTap: _openChannel,
          ),
        ],
        if (_seriesResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.sm),
            child: _SectionHeader(
                label: 'Series',
                count: _seriesResults.length),
          ),
          _HorizontalPosterRow(
            items: _seriesResults,
            nameOf: (s) => s.name,
            yearOf: (s) => s.year,
            posterOf: (s) => s.poster,
            onTap: (s) => _openSeries(s as Series),
          ),
        ],
        if (_movieResults.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.base, AppSpacing.lg, AppSpacing.base, AppSpacing.sm),
            child: _SectionHeader(
                label: 'Películas',
                count: _movieResults.length),
          ),
          _HorizontalPosterRow(
            items: _movieResults,
            nameOf: (m) => (m as Movie).title,
            yearOf: (m) => m.year,
            posterOf: (m) => m.poster,
            onTap: (m) => _openMovie(m as Movie),
          ),
        ],
      ],
    );
  }

  static OutlineInputBorder _border(
          {Color color = AppColors.border, double width = 1}) =>
      OutlineInputBorder(
        borderRadius: AppRadius.buttonRadius,
        borderSide: BorderSide(color: color, width: width),
      );
}

// ──────────────────────────────────────────────────────────────��──────────────
// _HorizontalChannelRow
// ───────────────────────────────────��─────────────────────────────��───────────

class _HorizontalChannelRow extends StatelessWidget {
  final List<Channel>       channels;
  final ValueChanged<Channel> onTap;

  const _HorizontalChannelRow(
      {required this.channels, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final device    = getDeviceInfo(context);
    final itemWidth = device.isTV ? 260.0 : device.isDesktop ? 220.0 : 180.0;
    final rowHeight = device.isTV ? 108.0 : 88.0;
    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        scrollDirection: Axis.horizontal,
        itemCount: channels.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final ch = channels[i];
          return Focus(
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.enter) {
                onTap(ch);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(builder: (ctx) {
              final focused = Focus.of(ctx).hasFocus;
              return GestureDetector(
                onTap: () => onTap(ch),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  width: itemWidth,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppRadius.thumbnailRadius,
                    border: Border.all(
                      color: focused
                          ? AppColors.focusBorder
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Row(children: [
                    _MiniLogo(url: ch.logo, name: ch.name),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(ch.name,
                              style: AppTextStyles.labelLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(ch.group,
                              style: AppTextStyles.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ]),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────���────────
// _HorizontalPosterRow  (Series + Movies)
// ────────────────────────────────────���────────────────────────────────────────

class _HorizontalPosterRow extends StatelessWidget {
  final List<dynamic>          items;
  final String Function(dynamic)   nameOf;
  final int?   Function(dynamic)   yearOf;
  final String? Function(dynamic)  posterOf;
  final ValueChanged<dynamic>      onTap;

  const _HorizontalPosterRow({
    required this.items,
    required this.nameOf,
    required this.yearOf,
    required this.posterOf,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final device    = getDeviceInfo(context);
    final itemWidth = device.isTV ? 180.0 : device.isDesktop ? 150.0 : device.isTablet ? 135.0 : 120.0;
    final rowHeight = device.isTV ? 270.0 : device.isDesktop ? 230.0 : 200.0;
    return SizedBox(
      height: rowHeight,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) {
          final item  = items[i];
          final url   = posterOf(item);
          final name  = nameOf(item);
          final year  = yearOf(item);

          return Focus(
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent &&
                  e.logicalKey == LogicalKeyboardKey.enter) {
                onTap(item);
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Builder(builder: (ctx) {
              final focused = Focus.of(ctx).hasFocus;
              return GestureDetector(
                onTap: () => onTap(item),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  width: itemWidth,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: AppRadius.thumbnailRadius,
                    border: Border.all(
                      color: focused
                          ? AppColors.focusBorder
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadius.sm)),
                          child: url != null && url.isNotEmpty
                              ? Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) =>
                                      _PosterFallback(name: name),
                                )
                              : _PosterFallback(name: name),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs + 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textPrimary),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                            if (year != null)
                              Text(year.toString(),
                                  style: AppTextStyles.labelSmall),
                          ],
                        ),
                      ),
                    ],
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

// ──────────────────────────────────────────────────���──────────────────────────
// Small widgets
// ───────────────────────────────────────────────────────────────────────���─────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int?   count;
  const _SectionHeader({required this.label, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: AppTextStyles.headlineSmall),
      if (count != null) ...[
        const SizedBox(width: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.chipRadius,
          ),
          child: Text('$count',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondary)),
        ),
      ],
    ]);
  }
}

class _MiniLogo extends StatelessWidget {
  final String? url;
  final String  name;
  const _MiniLogo({this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.thumbnailRadius,
      child: SizedBox(
        width: 42, height: 42,
        child: url != null && url!.isNotEmpty
            ? Image.network(
                url!,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _Initial(name: name),
              )
            : _Initial(name: name),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  const _Initial({required this.name});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: AppTextStyles.headlineSmall
              .copyWith(color: AppColors.textSecondary),
        ),
      );
}

class _PosterFallback extends StatelessWidget {
  final String name;
  const _PosterFallback({required this.name});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceVariant,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(name,
              style: AppTextStyles.labelSmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ),
      );
}

class _LabeledDropdown<T> extends StatelessWidget {
  final String      label;
  final T           value;
  final List<T>     items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelSmall),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.buttonRadius,
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.card,
              style: AppTextStyles.bodyMedium,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down,
                  color: AppColors.textSecondary),
              items: items
                  .map((v) => DropdownMenuItem<T>(
                        value: v,
                        child: Text(labelFor(v),
                            style: AppTextStyles.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null || null is T) onChanged(v as T);
              },
            ),
          ),
        ),
      ],
    );
  }
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
