import 'dart:developer' as dev;

import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';
import 'storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sort options
// ─────────────────────────────────────────────────────────────────────────────

enum SortBy { name, rating, year, recent }

extension SortByLabel on SortBy {
  String get value => name; // matches the string keys used in sortContent()
}

// ─────────────────────────────────────────────────────────────────────────────
// SearchService
// ─────────────────────────────────────────────────────────────────────────────

class SearchService {
  SearchService._();
  static final SearchService instance = SearchService._();

  static const _boxName       = 'searches';
  static const _recentKey     = 'recent_queries';
  static const _maxRecent     = 10;
  static const _fuzzyThreshold = 60; // 0–100 score

  Box? _box;

  // ── Init ─────────────────────────────────────────────────────────────────────

  /// Call after [StorageService.initializeHive()] — Hive must already be inited.
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    dev.log('[SearchService] Ready', name: 'SearchService');
  }

  // ── Global search ────────────────────────────────────────────────────────────

  /// Fuzzy-searches [query] across all content in [playlist].
  ///
  /// Returns an empty map if [query] is blank.
  /// Results are sorted by fuzzy score descending.
  Map<String, List<dynamic>> searchGlobal(String query, Playlist playlist) {
    final q = query.trim();
    if (q.isEmpty) {
      return {'TV': const [], 'SERIES': const [], 'MOVIES': const []};
    }

    dev.log('[SearchService] Global search: "$q"', name: 'SearchService');

    // Use pre-normalized StorageService indices when available (avoids per-item
    // regex normalization — O(n) scan but no regex cost per item per keystroke).
    final storage = StorageService.instance;
    late List<Channel> tv;
    late List<Series>  series;
    late List<Movie>   movies;

    if (storage.hasSearchIndices) {
      tv     = storage.searchChannelsFast(q);
      series = storage.searchSeriesFast(q);
      movies = storage.searchMoviesFast(q);
    } else {
      tv     = _fuzzyFilter<Channel>(q, playlist.channels, _channelName);
      series = _fuzzyFilter<Series>(q, playlist.series, _seriesName);
      movies = _fuzzyFilter<Movie>(q, playlist.movies, _movieTitle);
    }

    dev.log(
      '[SearchService] Results — TV: ${tv.length} | '
      'Series: ${series.length} | Movies: ${movies.length}',
      name: 'SearchService',
    );

    return {'TV': tv, 'SERIES': series, 'MOVIES': movies};
  }

  // ── Search by type ───────────────────────────────────────────────────────────

  /// Fuzzy-searches [query] in a single [type] from [playlist].
  List<dynamic> searchByType(
      String query, Playlist playlist, ContentType type) {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final storage = StorageService.instance;
    if (storage.hasSearchIndices) {
      return switch (type) {
        ContentType.TV     => storage.searchChannelsFast(q),
        ContentType.SERIES => storage.searchSeriesFast(q),
        ContentType.MOVIES => storage.searchMoviesFast(q),
      };
    }

    return switch (type) {
      ContentType.TV     => _fuzzyFilter<Channel>(q, playlist.channels, _channelName),
      ContentType.SERIES => _fuzzyFilter<Series>(q, playlist.series, _seriesName),
      ContentType.MOVIES => _fuzzyFilter<Movie>(q, playlist.movies, _movieTitle),
    };
  }

  // ── Categories ───────────────────────────────────────────────────────────────

  /// Returns unique, sorted, non-empty category strings for [type] from [playlist].
  List<String> getCategories(ContentType type, Playlist playlist) {
    Iterable<String> raw;
    switch (type) {
      case ContentType.TV:
        raw = playlist.channels.map((c) => c.group);
      case ContentType.SERIES:
        raw = playlist.series.map((s) => s.category);
      case ContentType.MOVIES:
        raw = playlist.movies.map((m) => m.category);
    }
    // Trim each value, discard blanks, then deduplicate and sort.
    final cats = raw
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return cats;
  }

  // ── Filter helpers ────────────────────────────────────────────────────────────

  /// Filters [content] to items whose category matches [category].
  List<dynamic> filterByCategory(List<dynamic> content, String category) {
    return content.where((item) {
      if (item is Channel) return item.group == category;
      if (item is Series)  return item.category == category;
      if (item is Movie)   return item.category == category;
      return false;
    }).toList();
  }

  /// Filters [content] to items released in [year].
  /// Only applies to [Series] and [Movie] — channels are returned unchanged.
  List<dynamic> filterByYear(List<dynamic> content, int year) {
    return content.where((item) {
      if (item is Series) return item.year == year;
      if (item is Movie)  return item.year == year;
      return true; // channels have no year — include them
    }).toList();
  }

  // ── Sort ─────────────────────────────────────────────────────────────────────

  /// Sorts [content] by [sortBy].
  ///
  /// Accepted values: `'name'`, `'rating'`, `'year'`, `'recent'`.
  /// Returns a new sorted list (does not mutate [content]).
  List<dynamic> sortContent(List<dynamic> content, String sortBy) {
    final copy = List<dynamic>.from(content);

    switch (sortBy) {
      case 'name':
        copy.sort((a, b) => _itemName(a).compareTo(_itemName(b)));

      case 'rating':
        copy.sort((a, b) {
          final ra = _itemRating(a) ?? -1.0;
          final rb = _itemRating(b) ?? -1.0;
          return rb.compareTo(ra); // descending
        });

      case 'year':
        copy.sort((a, b) {
          final ya = _itemYear(a) ?? 0;
          final yb = _itemYear(b) ?? 0;
          return yb.compareTo(ya); // newest first
        });

      case 'recent':
        // No-op: assumes caller provides already time-ordered list.
        // Override in caller if needed (e.g. sorted by history timestamp).
        break;

      default:
        dev.log('[SearchService] Unknown sortBy: "$sortBy"',
            name: 'SearchService');
    }

    return copy;
  }

  // ── Recent searches ───────────────────────────────────────────────────────────

  /// Returns up to [_maxRecent] recent search queries (most recent first).
  List<String> getRecentSearches() {
    final raw = _box?.get(_recentKey);
    if (raw == null) return [];
    return List<String>.from(raw as List);
  }

  /// Saves [query] to recent searches (deduplicates, trims to [_maxRecent]).
  void addRecentSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;

    final searches = getRecentSearches();
    searches.remove(q);           // remove old occurrence
    searches.insert(0, q);        // prepend most recent
    if (searches.length > _maxRecent) {
      searches.removeRange(_maxRecent, searches.length);
    }

    _box?.put(_recentKey, searches);
    dev.log('[SearchService] Recent search saved: "$q"', name: 'SearchService');
  }

  /// Clears all saved recent searches.
  void clearRecentSearches() {
    _box?.delete(_recentKey);
    dev.log('[SearchService] Recent searches cleared', name: 'SearchService');
  }

  // ── Private helpers ───────────────────────────────────────────────────────────

  /// Simple string-based filter: scores items by how well [query] matches
  /// [nameExtractor(item)]. Returns sorted by score descending.
  List<T> _fuzzyFilter<T>(
    String query,
    List<T> items,
    String Function(T) nameExtractor,
  ) {
    final qLower = _normalize(query);

    final scored = <({T item, int score})>[];
    for (final item in items) {
      final name = _normalize(nameExtractor(item));
      final score = _simpleScore(qLower, name);
      if (score >= _fuzzyThreshold) {
        scored.add((item: item, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.item).toList();
  }

  /// Scores [query] against [target] without external dependencies.
  ///
  /// - 100 if [target] contains [query] as a substring.
  /// - Proportional score based on how many space-split words of [query]
  ///   appear in [target] (max 80).
  static int _simpleScore(String query, String target) {
    if (target.contains(query)) return 100;
    final words = query.split(RegExp(r'\s+'));
    if (words.isEmpty) return 0;
    final matched = words.where((w) => w.isNotEmpty && target.contains(w)).length;
    return (matched / words.length * 80).round();
  }

  /// Lowercases and strips diacritics so that "pelicula" matches "Película",
  /// "accion" matches "Acción", etc.
  static String _normalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c');

  // Name extractors per type
  static String _channelName(Channel c) => c.name;
  static String _seriesName(Series s)   => s.name;
  static String _movieTitle(Movie m)    => m.title;

  // Generic accessors for sort
  static String _itemName(dynamic item) {
    if (item is Channel) return item.name;
    if (item is Series)  return item.name;
    if (item is Movie)   return item.title;
    return '';
  }

  static double? _itemRating(dynamic item) {
    if (item is Series) return item.rating;
    if (item is Movie)  return item.rating;
    return null;
  }

  static int? _itemYear(dynamic item) {
    if (item is Series) return item.year;
    if (item is Movie)  return item.year;
    return null;
  }
}
