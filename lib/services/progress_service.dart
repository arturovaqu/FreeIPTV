import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WatchEntry — a resolved progress entry for the "Continuar viendo" list.
// ─────────────────────────────────────────────────────────────────────────────

class WatchEntry {
  final WatchProgress progress;

  // Movies
  final Movie? movie;

  // Series
  final Series?  series;
  final Season?  season;
  final Episode? episode;

  const WatchEntry({
    required this.progress,
    this.movie,
    this.series,
    this.season,
    this.episode,
  });

  bool get isMovie => movie != null;

  String get title {
    if (movie  != null) return movie!.title;
    if (episode != null) {
      return 'T${season?.seasonNumber} E${episode!.episodeNumber} — ${episode!.title}';
    }
    return '';
  }

  String get subtitle => series?.name ?? '';

  String? get poster {
    if (movie != null) return movie!.poster;
    return series?.poster;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProgressService
// ─────────────────────────────────────────────────────────────────────────────

class ProgressService extends ChangeNotifier {
  ProgressService._();
  static final ProgressService instance = ProgressService._();

  static const _boxName = 'watch_progress';
  late final Box _box;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    // Hive is already initialized by StorageService; just open the box.
    _box = await Hive.openBox(_boxName);
    _initialized = true;
    dev.log('[ProgressService] Initialized — ${_box.length} entries',
        name: 'ProgressService');
  }

  void _assertInit() {
    assert(_initialized,
        'ProgressService.initialize() must be called before use.');
  }

  // ── Write ──────────────────────────────────────────────────────────────────

  void saveProgress({
    required String      contentId,
    required ContentType contentType,
    required Duration    position,
    Duration? duration,
    String? seriesId,
    int?    seasonNumber,
    int?    episodeNumber,
  }) {
    _assertInit();
    if (position <= Duration.zero) return;

    final isCompleted = duration != null &&
        duration.inSeconds > 0 &&
        position.inSeconds >= duration.inSeconds - 10;

    _box.put(
      contentId,
      WatchProgress(
        contentId:     contentId,
        contentType:   contentType,
        position:      position,
        duration:      duration,
        lastWatched:   DateTime.now(),
        isCompleted:   isCompleted,
        seriesId:      seriesId,
        seasonNumber:  seasonNumber,
        episodeNumber: episodeNumber,
      ).toJson(),
    );
    notifyListeners();
  }

  void markAsCompleted(String contentId) {
    _assertInit();
    final raw = _box.get(contentId);
    if (raw == null) return;
    final p =
        WatchProgress.fromJson(Map<String, dynamic>.from(raw as Map));
    _box.put(contentId, p.copyWith(isCompleted: true).toJson());
    dev.log('[ProgressService] Marked completed: $contentId',
        name: 'ProgressService');
    notifyListeners();
  }

  void deleteProgress(String contentId) {
    _assertInit();
    _box.delete(contentId);
    notifyListeners();
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  WatchProgress? getProgress(String contentId) {
    _assertInit();
    final raw = _box.get(contentId);
    if (raw == null) return null;
    try {
      return WatchProgress.fromJson(
          Map<String, dynamic>.from(raw as Map));
    } catch (e) {
      dev.log('[ProgressService] Parse error for $contentId: $e',
          name: 'ProgressService');
      return null;
    }
  }

  /// Returns in-progress entries (not completed), resolved against [playlist],
  /// sorted by most-recently-watched first.
  List<WatchEntry> getRecentlyWatched(
    Playlist? playlist, {
    int          limit      = 20,
    ContentType? filterType,
  }) {
    _assertInit();
    if (playlist == null) return [];

    final entries = <WatchEntry>[];

    for (final raw in _box.values) {
      try {
        final p = WatchProgress.fromJson(
            Map<String, dynamic>.from(raw as Map));

        if (p.contentType == ContentType.TV) continue;
        if (p.isCompleted) continue;
        if (p.position.inSeconds <= 5) continue;
        if (filterType != null && p.contentType != filterType) continue;

        WatchEntry? entry;

        if (p.contentType == ContentType.MOVIES) {
          final movie = playlist.movies
              .where((m) => m.id == p.contentId)
              .firstOrNull;
          if (movie != null) {
            entry = WatchEntry(progress: p, movie: movie);
          }
        } else if (p.contentType == ContentType.SERIES &&
                   p.seriesId != null) {
          final series = playlist.series
              .where((s) => s.id == p.seriesId)
              .firstOrNull;
          if (series != null) {
            final season = series.seasons
                .where((s) => s.seasonNumber == p.seasonNumber)
                .firstOrNull;
            if (season != null) {
              final episode = season.episodes
                  .where((e) => e.episodeNumber == p.episodeNumber)
                  .firstOrNull;
              if (episode != null) {
                entry = WatchEntry(
                  progress: p,
                  series:   series,
                  season:   season,
                  episode:  episode,
                );
              }
            }
          }
        }

        if (entry != null) entries.add(entry);
      } catch (_) {}
    }

    entries.sort(
        (a, b) => b.progress.lastWatched.compareTo(a.progress.lastWatched));
    return entries.take(limit).toList();
  }
}
