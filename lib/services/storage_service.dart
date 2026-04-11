import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

// ─────────────────────────────────────────────────────────────────────────────
class SessionData {
  final String deviceId;
  final DateTime lastActivity;
  final String appVersion;

  const SessionData({
    required this.deviceId,
    required this.lastActivity,
    required this.appVersion,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'lastActivity': lastActivity.toIso8601String(),
        'appVersion': appVersion,
      };

  factory SessionData.fromJson(Map<String, dynamic> j) => SessionData(
        deviceId: j['deviceId'] as String,
        lastActivity: DateTime.parse(j['lastActivity'] as String),
        appVersion: j['appVersion'] as String? ?? '1.0.0',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// History entry
// ─────────────────────────────────────────────────────────────────────────────

class HistoryEntry {
  final String id;
  final ContentType type;
  final DateTime timestamp;
  final Duration? position;

  const HistoryEntry({
    required this.id,
    required this.type,
    required this.timestamp,
    this.position,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'position': position?.inMilliseconds,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        type: ContentType.values.byName(j['type'] as String),
        timestamp: DateTime.parse(j['timestamp'] as String),
        position: j['position'] != null
            ? Duration(milliseconds: j['position'] as int)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// StorageService
// ─────────────────────────────────────────────────────────────────────────────

class StorageService extends ChangeNotifier {
  StorageService._();
  static final StorageService instance = StorageService._();

  // Box names
  static const _boxPlaylists = 'playlists';
  static const _boxFavorites = 'favorites';
  static const _boxHistory   = 'history';
  static const _boxSettings  = 'settings';
  static const _boxSession   = 'session';

  // Box references (populated after initializeHive)
  late final Box _playlists;
  late final Box _favorites;
  late final Box _history;
  late final Box _settings;
  late final Box _session;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  // In-memory cache: avoids re-deserializing the fat playlist blob on every call
  final Map<String, Playlist> _playlistCache = {};

  // ── Search indices ──────────────────────────────────────────────────────────
  // Rebuilt from the active playlist whenever it changes.
  // Normalization (lowercase + diacritics) is done ONCE at build time so
  // searches never pay the regex cost per item per keystroke.

  // (normalizedName, item) pairs — O(n) scan, but regex-free at search time
  final List<(String, Channel)> _channelNameIndex = [];
  final List<(String, Movie)>   _movieNameIndex   = [];
  final List<(String, Series)>  _seriesNameIndex  = [];

  // O(1) lookup by ID
  final Map<String, Channel> _channelById = {};
  final Map<String, Movie>   _movieById   = {};
  final Map<String, Series>  _seriesById  = {};

  // O(1) lookup by category
  final Map<String, List<Channel>> _channelsByCategory = {};
  final Map<String, List<Movie>>   _moviesByCategory   = {};
  final Map<String, List<Series>>  _seriesByCategory   = {};

  // Session management
  String _thisDeviceId = '';
  Timer? _keepAliveTimer;

  // ── Init ────────────────────────────────────────────────────────────────────

  /// Must be called once at app startup before any other method.
  ///
  /// We use JSON serialization inside Hive boxes (no TypeAdapters / code
  /// generation required). All models are stored as Map<String, dynamic>.
  Future<void> initializeHive() async {
    if (_initialized) return;

    final sw = Stopwatch()..start();

    await Hive.initFlutter();

    _playlists = await Hive.openBox(_boxPlaylists);
    _favorites = await Hive.openBox(_boxFavorites);
    _history   = await Hive.openBox(_boxHistory);
    _settings  = await Hive.openBox(_boxSettings);
    _session   = await Hive.openBox(_boxSession);

    _initialized = true;
    dev.log('[StorageService] Hive initialized in ${sw.elapsedMilliseconds}ms — '
        'playlists: ${_playlists.length}, '
        'favorites: ${_favorites.length}, '
        'history: ${_history.length}',
        name: 'StorageService');

    await _startSession();
  }

  // ── Session management ──────────────────────────────────────────────────────

  Future<void> _startSession() async {
    // Get or generate a persistent ID for this device
    _thisDeviceId = _settings.get('deviceId') as String? ?? const Uuid().v4();
    await _settings.put('deviceId', _thisDeviceId);

    // Write initial session record
    await _writeSessionActivity();

    // Refresh every 5 minutes while the app is alive
    _keepAliveTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _writeSessionActivity(),
    );

    dev.log('[StorageService] Session started — deviceId: $_thisDeviceId',
        name: 'StorageService');
  }

  Future<void> _writeSessionActivity() async {
    final data = SessionData(
      deviceId: _thisDeviceId,
      lastActivity: DateTime.now(),
      appVersion: '1.0.0',
    );
    await _session.put('current_session', data.toJson());
  }

  /// Call this whenever playback starts to stamp the current time.
  Future<void> updateActivity() => _writeSessionActivity();

  /// Returns true if there is an active session from a **different** device.
  /// A session is considered active if its lastActivity was within 30 minutes.
  Future<bool> isSessionActive() async {
    _assertInit();
    final raw = _session.get('current_session');
    if (raw == null) return false;

    final session =
        SessionData.fromJson(Map<String, dynamic>.from(raw as Map));

    // Same device → not a concurrent session
    if (session.deviceId == _thisDeviceId) return false;

    final timeSinceLastActivity =
        DateTime.now().difference(session.lastActivity);

    if (timeSinceLastActivity.inMinutes > 30) {
      // Session expired — safe to take over
      return false;
    }

    dev.log(
      '[StorageService] Concurrent session detected — '
      'other device: ${session.deviceId}, '
      'last seen: ${timeSinceLastActivity.inMinutes}m ago',
      name: 'StorageService',
    );
    return true;
  }

  /// Cancel the keep-alive timer (call on app termination if needed).
  void stopSession() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  void _assertInit() {
    assert(_initialized,
        'StorageService.initializeHive() must be called before use.');
  }

  // ── Playlist management ─────────────────────────────────────────────────────

  Future<void> savePlaylist(Playlist playlist) async {
    _assertInit();
    final sw = Stopwatch()..start();
    await _playlists.put(playlist.id, _encodePlaylist(playlist));
    _playlistCache[playlist.id] = playlist; // keep cache in sync
    // Rebuild search indices if this is the currently-active playlist
    final activeId = _settings.get('activePlaylistId') as String?;
    if (activeId == playlist.id) _createSearchIndices(playlist);
    dev.log('[StorageService] savePlaylist() ${sw.elapsedMilliseconds}ms: ${playlist.name}',
        name: 'StorageService');
    notifyListeners();
  }

  List<Playlist> getPlaylists() {
    _assertInit();
    final result = <Playlist>[];
    for (final key in _playlists.keys) {
      final id = key as String;
      if (_playlistCache.containsKey(id)) {
        result.add(_playlistCache[id]!);
      } else {
        final raw = _playlists.get(id);
        if (raw != null) {
          final pl = _decodePlaylist(raw as Map);
          _playlistCache[id] = pl;
          result.add(pl);
        }
      }
    }
    return result;
  }

  Future<void> deletePlaylist(String id) async {
    _assertInit();
    _playlistCache.remove(id);
    await _playlists.delete(id);
    // If the deleted playlist was active, clear the active pointer and indices
    if (_settings.get('activePlaylistId') == id) {
      await _settings.delete('activePlaylistId');
      _clearSearchIndices();
    }
    dev.log('[StorageService] Deleted playlist: $id', name: 'StorageService');
    notifyListeners();
  }

  Playlist? getActivePlaylist() {
    _assertInit();
    final activeId = _settings.get('activePlaylistId') as String?;
    if (activeId == null) return null;
    if (_playlistCache.containsKey(activeId)) return _playlistCache[activeId];
    final sw = Stopwatch()..start();
    final pl = _decodePlaylist(raw as Map);
    _playlistCache[activeId] = pl;
    // Build indices in the background to prevent UI jank
    _buildIndicesAsync(pl);
    dev.log('[StorageService] getActivePlaylist() decoded in ${sw.elapsedMilliseconds}ms — '
        '${pl.channels.length} ch, ${pl.series.length} series, ${pl.movies.length} movies',
        name: 'StorageService');
    return pl;
  }

  /// Load a playlist by [id] on demand — hits cache first, then Hive.
  Playlist? getPlaylistWithContent(String id) {
    _assertInit();
    if (_playlistCache.containsKey(id)) return _playlistCache[id];
    final raw = _playlists.get(id);
    if (raw == null) return null;
    final sw = Stopwatch()..start();
    final pl = _decodePlaylist(raw as Map);
    _playlistCache[id] = pl;
    dev.log('[StorageService] getPlaylistWithContent($id) decoded in ${sw.elapsedMilliseconds}ms',
        name: 'StorageService');
    return pl;
  }

  Future<void> setActivePlaylist(String id) async {
    _assertInit();
    await _settings.put('activePlaylistId', id);
    // Rebuild indices for the newly-active playlist (may already be in cache)
    final pl = _playlistCache[id];
    if (pl != null) _createSearchIndices(pl);
    dev.log('[StorageService] Active playlist set to: $id',
        name: 'StorageService');
    notifyListeners();
  }

  // ── Favorites ───────────────────────────────────────────────────────────────

  /// Key in the favorites box: "<type.name>_ids"
  String _favKey(ContentType type) => '${type.name}_ids';

  Future<void> saveFavorite(String contentId, ContentType type) async {
    _assertInit();
    final ids = getFavorites(type);
    if (!ids.contains(contentId)) {
      ids.add(contentId);
      await _favorites.put(_favKey(type), ids);
      dev.log('[StorageService] Added favorite: $contentId ($type)',
          name: 'StorageService');
      notifyListeners();
    }
  }

  Future<void> removeFavorite(String contentId, ContentType type) async {
    _assertInit();
    final ids = getFavorites(type);
    if (ids.remove(contentId)) {
      await _favorites.put(_favKey(type), ids);
      dev.log('[StorageService] Removed favorite: $contentId ($type)',
          name: 'StorageService');
      notifyListeners();
    }
  }

  List<String> getFavorites(ContentType type) {
    _assertInit();
    final raw = _favorites.get(_favKey(type));
    if (raw == null) return [];
    return List<String>.from(raw as List);
  }

  bool isFavorite(String contentId, ContentType type) {
    return getFavorites(type).contains(contentId);
  }

  Future<void> clearFavorites([ContentType? type]) async {
    _assertInit();
    if (type == null) {
      for (final t in ContentType.values) {
        await _favorites.delete(_favKey(t));
      }
    } else {
      await _favorites.delete(_favKey(type));
    }
    dev.log('[StorageService] Favorites cleared (type: $type)',
        name: 'StorageService');
    notifyListeners();
  }

  // ── History ─────────────────────────────────────────────────────────────────

  static const _historyKey = 'entries';
  static const _maxHistorySize = 200;

  Future<void> addToHistory(
    String contentId,
    ContentType type, {
    Duration? position,
    DateTime? timestamp,
  }) async {
    _assertInit();
    final entries = _loadHistoryEntries();

    // Remove previous entry for this content to avoid duplicates
    entries.removeWhere((e) => e.id == contentId && e.type == type);

    entries.insert(
      0,
      HistoryEntry(
        id: contentId,
        type: type,
        timestamp: timestamp ?? DateTime.now(),
        position: position,
      ),
    );

    // Keep list bounded
    if (entries.length > _maxHistorySize) {
      entries.removeRange(_maxHistorySize, entries.length);
    }

    await _saveHistoryEntries(entries);
    dev.log('[StorageService] History updated: $contentId ($type)',
        name: 'StorageService');
    notifyListeners();
  }

  /// Returns history entries, optionally filtered by [type].
  List<HistoryEntry> getHistory([ContentType? type]) {
    _assertInit();
    final entries = _loadHistoryEntries();
    if (type == null) return entries;
    return entries.where((e) => e.type == type).toList();
  }

  Future<void> removeHistoryEntry(String contentId, ContentType type) async {
    _assertInit();
    final entries = _loadHistoryEntries()
      ..removeWhere((e) => e.id == contentId && e.type == type);
    await _saveHistoryEntries(entries);
    dev.log('[StorageService] Removed history entry: $contentId ($type)',
        name: 'StorageService');
    notifyListeners();
  }

  Future<void> clearHistory([ContentType? type]) async {
    _assertInit();
    if (type == null) {
      await _history.delete(_historyKey);
    } else {
      final entries = _loadHistoryEntries()
        ..removeWhere((e) => e.type == type);
      await _saveHistoryEntries(entries);
    }
    dev.log('[StorageService] History cleared (type: $type)',
        name: 'StorageService');
    notifyListeners();
  }

  /// Returns the last playback position saved for [contentId], or null.
  Duration? getLastPosition(String contentId, ContentType type) {
    _assertInit();
    final entry = _loadHistoryEntries()
        .where((e) => e.id == contentId && e.type == type)
        .firstOrNull;
    return entry?.position;
  }

  // ── Settings / Preferences ──────────────────────────────────────────────────

  Future<void> setTheme(String theme) async {
    _assertInit();
    await _settings.put('theme', theme);
    notifyListeners();
  }

  String getTheme() {
    _assertInit();
    return _settings.get('theme', defaultValue: 'dark') as String;
  }

  Future<void> setLanguage(String lang) async {
    _assertInit();
    await _settings.put('language', lang);
    notifyListeners();
  }

  String getLanguage() {
    _assertInit();
    return _settings.get('language', defaultValue: 'es') as String;
  }

  Future<void> setDefaultSubtitles(bool enabled) async {
    _assertInit();
    await _settings.put('defaultSubtitles', enabled);
    notifyListeners();
  }

  bool getDefaultSubtitles() {
    _assertInit();
    return _settings.get('defaultSubtitles', defaultValue: false) as bool;
  }

  bool useProfessionalMotor() {
    _assertInit();
    return _settings.get('useProfessionalMotor', defaultValue: false) as bool;
  }

  Future<void> setProfessionalMotor(bool enabled) async {
    _assertInit();
    await _settings.put('useProfessionalMotor', enabled);
    notifyListeners();
  }

  // ── Search indices ───────────────────────────────────────────────────────────

  bool _isIndexing = false;
  bool get isIndexing => _isIndexing;

  Future<void> _buildIndicesAsync(Playlist pl) async {
    _isIndexing = true;
    notifyListeners();
    
    final result = await compute(_backgroundIndexBuilder, pl);
    
    _channelNameIndex.clear();
    _channelNameIndex.addAll(result.channelNameIndex);
    _movieNameIndex.clear();
    _movieNameIndex.addAll(result.movieNameIndex);
    _seriesNameIndex.clear();
    _seriesNameIndex.addAll(result.seriesNameIndex);
    
    _channelById.clear();
    _channelById.addAll(result.channelById);
    _movieById.clear();
    _movieById.addAll(result.movieById);
    _seriesById.clear();
    _seriesById.addAll(result.seriesById);
    
    _channelsByCategory.clear();
    _channelsByCategory.addAll(result.channelsByCategory);
    _moviesByCategory.clear();
    _moviesByCategory.addAll(result.moviesByCategory);
    _seriesByCategory.clear();
    _seriesByCategory.addAll(result.seriesByCategory);
    
    _isIndexing = false;
    notifyListeners();
    
    dev.log('[StorageService] Search indices built in Isolate', name: 'StorageService');
  }

  void _clearSearchIndices() {
    _channelNameIndex.clear();
    _movieNameIndex.clear();
    _seriesNameIndex.clear();
    _channelById.clear();
    _movieById.clear();
    _seriesById.clear();
    _channelsByCategory.clear();
    _moviesByCategory.clear();
    _seriesByCategory.clear();
    notifyListeners();
  }

  void _clearSearchIndices() {
    _channelNameIndex.clear();
    _movieNameIndex.clear();
    _seriesNameIndex.clear();
    _channelById.clear();
    _movieById.clear();
    _seriesById.clear();
    _channelsByCategory.clear();
    _moviesByCategory.clear();
    _seriesByCategory.clear();
  }

  // ── Public fast-search API ───────────────────────────────────────────────────

  /// Substring search over channels. Returns all channels if [query] is empty.
  List<Channel> searchChannelsFast(String query) =>
      _searchNameIndex(query, _channelNameIndex);

  /// Substring search over movies. Returns all movies if [query] is empty.
  List<Movie> searchMoviesFast(String query) =>
      _searchNameIndex(query, _movieNameIndex);

  /// Substring search over series. Returns all series if [query] is empty.
  List<Series> searchSeriesFast(String query) =>
      _searchNameIndex(query, _seriesNameIndex);

  List<T> _searchNameIndex<T>(String query, List<(String, T)> index) {
    if (query.isEmpty) return index.map((e) => e.$2).toList();
    final q = _indexNormalize(query);
    return [for (final (name, item) in index) if (name.contains(q)) item];
  }

  // O(1) category lookup
  List<Channel> getChannelsByCategory(String category) =>
      _channelsByCategory[category] ?? const [];
  List<Movie>   getMoviesByCategory(String category)   =>
      _moviesByCategory[category] ?? const [];
  List<Series>  getSeriesByCategory(String category)   =>
      _seriesByCategory[category] ?? const [];

  // O(1) ID lookup
  Channel? getChannelById(String id) => _channelById[id];
  Movie?   getMovieById(String id)   => _movieById[id];
  Series?  getSeriesById(String id)  => _seriesById[id];

  /// Whether indices are ready (i.e. an active playlist has been decoded).
  bool get hasSearchIndices => _channelNameIndex.isNotEmpty ||
      _movieNameIndex.isNotEmpty || _seriesNameIndex.isNotEmpty;

  /// Same normalization as [SearchService._normalize].
  static String _indexNormalize(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâä]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[íìîï]'), 'i')
      .replaceAll(RegExp(r'[óòôö]'), 'o')
      .replaceAll(RegExp(r'[úùûü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c');

  // ── Internal serialization ──────────────────────────────────────────────────

  // -- History -----------------------------------------------------------------

  List<HistoryEntry> getHistory() {
    _assertInit();
    return _loadHistoryEntries();
  }

  List<HistoryEntry> _loadHistoryEntries() {
    final raw = _history.get(_historyKey);
    if (raw == null) return [];
    try {
      final list = (raw as List).cast<Map>();
      return list
          .map((m) => HistoryEntry.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (e) {
      dev.log('[StorageService] Failed to parse history: $e',
          name: 'StorageService');
      return [];
    }
  }

  Future<void> _saveHistoryEntries(List<HistoryEntry> entries) async {
    await _history.put(
      _historyKey,
      entries.map((e) => e.toJson()).toList(),
    );
  }

  // -- Playlist ----------------------------------------------------------------

  Map<String, dynamic> _encodePlaylist(Playlist p) => {
        'id': p.id,
        'name': p.name,
        'url': p.url,
        'lastUpdated': p.lastUpdated.toIso8601String(),
        'isActive': p.isActive,
        'channels': p.channels.map(_encodeChannel).toList(),
        'series': p.series.map(_encodeSeries).toList(),
        'movies': p.movies.map(_encodeMovie).toList(),
      };

  Playlist _decodePlaylist(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    return Playlist(
      id: m['id'] as String,
      name: m['name'] as String,
      url: m['url'] as String,
      lastUpdated: DateTime.parse(m['lastUpdated'] as String),
      isActive: m['isActive'] as bool? ?? true,
      channels: (m['channels'] as List? ?? [])
          .map((c) => _decodeChannel(c as Map))
          .toList(),
      series: (m['series'] as List? ?? [])
          .map((s) => _decodeSeries(s as Map))
          .toList(),
      movies: (m['movies'] as List? ?? [])
          .map((mv) => _decodeMovie(mv as Map))
          .toList(),
    );
  }

  // -- Channel -----------------------------------------------------------------

  Map<String, dynamic> _encodeChannel(Channel c) => {
        'id': c.id,
        'name': c.name,
        'logo': c.logo,
        'url': c.url,
        'tvgId': c.tvgId,
        'tvgName': c.tvgName,
        'group': c.group,
        'contentType': c.contentType.name,
      };

  Channel _decodeChannel(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    return Channel(
      id: m['id'] as String,
      name: m['name'] as String,
      logo: m['logo'] as String?,
      url: m['url'] as String,
      tvgId: m['tvgId'] as String?,
      tvgName: m['tvgName'] as String?,
      group: m['group'] as String? ?? 'Sin categoría',
      contentType: ContentType.values.byName(
        m['contentType'] as String? ?? ContentType.TV.name,
      ),
    );
  }

  // -- Movie -------------------------------------------------------------------

  Map<String, dynamic> _encodeMovie(Movie mv) => {
        'id': mv.id,
        'title': mv.title,
        'poster': mv.poster,
        'description': mv.description,
        'category': mv.category,
        'year': mv.year,
        'durationMs': mv.duration?.inMilliseconds,
        'rating': mv.rating,
        'url': mv.url,
        'watched': mv.watched,
        'contentType': mv.contentType.name,
      };

  Movie _decodeMovie(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    return Movie(
      id: m['id'] as String,
      title: m['title'] as String,
      poster: m['poster'] as String?,
      description: m['description'] as String?,
      category: m['category'] as String? ?? 'Películas',
      year: m['year'] as int?,
      duration: m['durationMs'] != null
          ? Duration(milliseconds: m['durationMs'] as int)
          : null,
      rating: (m['rating'] as num?)?.toDouble(),
      url: m['url'] as String,
      watched: m['watched'] as bool? ?? false,
      contentType: ContentType.values.byName(
        m['contentType'] as String? ?? ContentType.MOVIES.name,
      ),
    );
  }

  // -- Series / Season / Episode -----------------------------------------------

  Map<String, dynamic> _encodeSeries(Series s) => {
        'id': s.id,
        'name': s.name,
        'poster': s.poster,
        'description': s.description,
        'category': s.category,
        'year': s.year,
        'rating': s.rating,
        'contentType': s.contentType.name,
        'seasons': s.seasons.map(_encodeSeason).toList(),
      };

  Series _decodeSeries(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    return Series(
      id: m['id'] as String,
      name: m['name'] as String,
      poster: m['poster'] as String?,
      description: m['description'] as String?,
      category: m['category'] as String? ?? 'Series',
      year: m['year'] as int?,
      rating: (m['rating'] as num?)?.toDouble(),
      contentType: ContentType.values.byName(
        m['contentType'] as String? ?? ContentType.SERIES.name,
      ),
      seasons: (m['seasons'] as List? ?? [])
          .map((s) => _decodeSeason(s as Map))
          .toList(),
    );
  }

  Map<String, dynamic> _encodeSeason(Season s) => {
        'seasonNumber': s.seasonNumber,
        'episodes': s.episodes.map(_encodeEpisode).toList(),
      };

  Season _decodeSeason(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    return Season(
      seasonNumber: m['seasonNumber'] as int,
      episodes: (m['episodes'] as List? ?? [])
          .map((e) => _decodeEpisode(e as Map))
          .toList(),
    );
  }

  Map<String, dynamic> _encodeEpisode(Episode e) => {
        'episodeNumber': e.episodeNumber,
        'title': e.title,
        'url': e.url,
        'durationMs': e.duration?.inMilliseconds,
        'watched': e.watched,
      };

  Episode _decodeEpisode(Map raw) {
    final m = Map<String, dynamic>.from(raw);
    return Episode(
      episodeNumber: m['episodeNumber'] as int,
      title: m['title'] as String,
      url: m['url'] as String,
      duration: m['durationMs'] != null
          ? Duration(milliseconds: m['durationMs'] as int)
          : null,
      watched: m['watched'] as bool? ?? false,
    );
  }
}

// ── Isolate Indexed Result ──────────────────────────────────────────────────

class _IndexingResult {
  final List<(String, Channel)> channelNameIndex;
  final List<(String, Movie)>   movieNameIndex;
  final List<(String, Series)>  seriesNameIndex;
  final Map<String, Channel>    _channelById;
  final Map<String, Movie>      _movieById;
  final Map<String, Series>     _seriesById;
  final Map<String, List<Channel>> channelsByCategory;
  final Map<String, List<Movie>>   moviesByCategory;
  final Map<String, List<Series>>  seriesByCategory;

  _IndexingResult({
    required this.channelNameIndex,
    required this.movieNameIndex,
    required this.seriesNameIndex,
    required Map<String, Channel> channelById,
    required Map<String, Movie> movieById,
    required Map<String, Series> seriesById,
    required this.channelsByCategory,
    required this.moviesByCategory,
    required this.seriesByCategory,
  }) : _channelById = channelById,
       _movieById = movieById,
       _seriesById = seriesById;

  Map<String, Channel> get channelById => _channelById;
  Map<String, Movie>   get movieById => _movieById;
  Map<String, Series>  get seriesById => _seriesById;
}

_IndexingResult _backgroundIndexBuilder(Playlist pl) {
  final channelNameIndex = pl.channels.map((c) => (StorageService._indexNormalize(c.name), c)).toList();
  final movieNameIndex   = pl.movies.map((m) => (StorageService._indexNormalize(m.title), m)).toList();
  final seriesNameIndex  = pl.series.map((s) => (StorageService._indexNormalize(s.name), s)).toList();

  final channelById = {for (final c in pl.channels) c.id: c};
  final movieById   = {for (final m in pl.movies) m.id: m};
  final seriesById  = {for (final s in pl.series) s.id: s};

  final channelsByCategory = <String, List<Channel>>{};
  for (final c in pl.channels) {
    channelsByCategory.putIfAbsent(c.group, () => []).add(c);
  }
  final moviesByCategory = <String, List<Movie>>{};
  for (final m in pl.movies) {
    moviesByCategory.putIfAbsent(m.category, () => []).add(m);
  }
  final seriesByCategory = <String, List<Series>>{};
  for (final s in pl.series) {
    seriesByCategory.putIfAbsent(s.category, () => []).add(s);
  }

  return _IndexingResult(
    channelNameIndex: channelNameIndex,
    movieNameIndex: movieNameIndex,
    seriesNameIndex: seriesNameIndex,
    channelById: channelById,
    movieById: movieById,
    seriesById: seriesById,
    channelsByCategory: channelsByCategory,
    moviesByCategory: moviesByCategory,
    seriesByCategory: seriesByCategory,
  );
}
