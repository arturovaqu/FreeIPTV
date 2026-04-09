import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import 'progress_service.dart';
import 'storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MediaService  —  ExoPlayer backend via video_player
// ─────────────────────────────────────────────────────────────────────────────

class MediaService extends ChangeNotifier {
  MediaService._();
  static final MediaService instance = MediaService._();

  // ── Player ───────────────────────────────────────────────────────────────────

  VideoPlayerController? _controller;
  Timer?                 _progressTimer;
  Timer?                 _positionPollTimer;

  // ── State ───────────────────────────────────────────────────────────────────

  ContentType? _currentContentType;
  Channel?     _currentChannel;
  Series?      _currentSeries;
  Season?      _currentSeason;
  Episode?     _currentEpisode;
  Movie?       _currentMovie;
  bool         _isPlaying        = false;
  Duration     _duration         = Duration.zero;
  Duration     _position         = Duration.zero;
  double       _volume           = 100.0;
  String?      _error;
  bool         _subtitlesEnabled = false;

  // ── ValueNotifiers ──────────────────────────────────────────────────────────

  /// Fires whenever a new VideoPlayerController is ready for rendering.
  final videoControllerNotifier   = ValueNotifier<VideoPlayerController?>(null);
  final isPlayingNotifier          = ValueNotifier<bool>(false);
  final currentContentTypeNotifier = ValueNotifier<ContentType?>(null);
  final currentChannelNotifier     = ValueNotifier<Channel?>(null);
  final currentSeriesNotifier      = ValueNotifier<Series?>(null);
  final currentEpisodeNotifier     = ValueNotifier<Episode?>(null);
  final currentMovieNotifier       = ValueNotifier<Movie?>(null);
  final durationNotifier           = ValueNotifier<Duration>(Duration.zero);
  final positionNotifier           = ValueNotifier<Duration>(Duration.zero);
  final volumeNotifier             = ValueNotifier<double>(100.0);
  final errorNotifier              = ValueNotifier<String?>(null);
  final isBufferingNotifier        = ValueNotifier<bool>(false);
  final completedNotifier          = ValueNotifier<bool>(false);
  final subtitlesEnabledNotifier   = ValueNotifier<bool>(false);

  // ── Getters ──────────────────────────────────────────────────────────────────

  bool                   get isPlaying          => _isPlaying;
  ContentType?           get currentContentType => _currentContentType;
  Channel?               get currentChannel     => _currentChannel;
  Series?                get currentSeries      => _currentSeries;
  Season?                get currentSeason      => _currentSeason;
  Episode?               get currentEpisode     => _currentEpisode;
  Movie?                 get currentMovie       => _currentMovie;
  Duration               get duration           => _duration;
  Duration               get position           => _position;
  double                 get volume             => _volume;
  String?                get error              => _error;
  bool                   get subtitlesEnabled   => _subtitlesEnabled;
  VideoPlayerController? get videoController    => _controller;

  double get progress =>
      _duration.inMilliseconds > 0
          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  // ── Init ─────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    dev.log('[MediaService] Initialized — backend: ExoPlayer (video_player)',
        name: 'MediaService');
  }

  // ── HTTP headers ─────────────────────────────────────────────────────────────

  // All content types — same Chrome UA that works for live TV and series
  static const _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer':        'http://iota.proxy-pass.vip/',
    'Origin':         'http://iota.proxy-pass.vip',
    'Accept':         '*/*',
    'Accept-Language': 'es-ES,es;q=0.9',
    'Cache-Control':  'no-cache',
    'Pragma':         'no-cache',
    'Connection':     'keep-alive',
  };

  // ── Open URL ─────────────────────────────────────────────────────────────────

  /// Opens [url] in a brand-new VideoPlayerController.
  ///
  /// Returns normally when the controller has been initialized and playback
  /// started.  Throws / sets error state on failure.
  Future<void> _openUrl(String url) async {
    _cancelProgressTimer();
    _cancelPositionPollTimer();
    _clearError();
    completedNotifier.value   = false;
    isBufferingNotifier.value = true;

    dev.log('[MediaService] Opening: $url', name: 'MediaService');
    dev.log('[MediaService] Type: $_currentContentType', name: 'MediaService');
    // ignore: avoid_print
    print('=== MEDIA URL  === $url');
    // ignore: avoid_print
    print('=== MEDIA TYPE === $_currentContentType');

    final newCtrl = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: _headers,
    );

    try {
      await newCtrl.initialize();
      dev.log('[MediaService] ExoPlayer initialized OK — '
          'duration: ${newCtrl.value.duration}', name: 'MediaService');

      final oldCtrl = _controller;

      // Swap to the new controller before exposing it to the UI
      _controller = newCtrl;
      _duration   = newCtrl.value.duration;
      _position   = Duration.zero;

      durationNotifier.value = _duration;
      positionNotifier.value = Duration.zero;

      newCtrl.addListener(_onControllerUpdate);
      await newCtrl.setVolume(_volume / 100.0);
      await newCtrl.play();

      // Publish AFTER play() so the VideoPlayer widget gets an already-playing
      // controller and renders the first frame immediately.
      videoControllerNotifier.value = newCtrl;

      isBufferingNotifier.value = false;
      _startPositionPollTimer();

      // Dispose old controller after the new one is live
      if (oldCtrl != null) {
        oldCtrl.removeListener(_onControllerUpdate);
        oldCtrl.dispose();
      }
    } catch (e) {
      dev.log('[MediaService] Error opening stream: $e', name: 'MediaService');
      newCtrl.dispose();
      isBufferingNotifier.value = false;
      _setError('No se pudo abrir el stream.\n$e');
    }
  }

  // ── Controller listener ───────────────────────────────────────────────────────

  void _onControllerUpdate() {
    final ctrl = _controller;
    if (ctrl == null) return;
    final val = ctrl.value;

    // Playing state
    if (_isPlaying != val.isPlaying) {
      _isPlaying = val.isPlaying;
      isPlayingNotifier.value = val.isPlaying;
      notifyListeners();
    }

    // Buffering
    if (isBufferingNotifier.value != val.isBuffering) {
      isBufferingNotifier.value = val.isBuffering;
    }

    // Error
    if (val.hasError) {
      final msg = val.errorDescription ?? 'Error desconocido';
      if (_error != msg) {
        _error = msg;
        errorNotifier.value = msg;
        dev.log('[MediaService] Video error: $msg', name: 'MediaService');
        notifyListeners();
      }
    }

    // Duration (can arrive late for some streams)
    if (val.duration > Duration.zero && _duration != val.duration) {
      _duration = val.duration;
      durationNotifier.value = val.duration;
    }

    // Completion: within last 2 s and paused/stopped
    if (!completedNotifier.value &&
        _duration > Duration.zero &&
        val.position >= _duration - const Duration(seconds: 2) &&
        !val.isPlaying) {
      completedNotifier.value = true;
      _onPlaybackCompleted();
    }
  }

  // ── Position poll ─────────────────────────────────────────────────────────────
  //
  // video_player has no position stream; we poll every 500 ms instead.

  void _startPositionPollTimer() {
    _cancelPositionPollTimer();
    _positionPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        final ctrl = _controller;
        if (ctrl == null || !ctrl.value.isInitialized) return;
        final pos = ctrl.value.position;
        if (_position != pos) {
          _position = pos;
          positionNotifier.value = pos;
        }
      },
    );
  }

  void _cancelPositionPollTimer() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
  }

  // ── Playback commands ────────────────────────────────────────────────────────

  Future<void> playChannel(Channel ch) async {
    dev.log('[MediaService] playChannel: ${ch.name}', name: 'MediaService');
    _currentContentType = ContentType.TV;
    _currentChannel     = ch;
    _currentSeries      = null;
    _currentSeason      = null;
    _currentEpisode     = null;
    _currentMovie       = null;
    _updateContentNotifiers();
    await _openUrl(ch.url);
    StorageService.instance.addToHistory(ch.id, ContentType.TV);
    notifyListeners();
  }

  Future<void> playSeries(Series s, Season season, Episode ep) async {
    dev.log('[MediaService] playSeries: ${s.name} '
        'S${season.seasonNumber}E${ep.episodeNumber}',
        name: 'MediaService');
    _currentContentType = ContentType.SERIES;
    _currentSeries      = s;
    _currentSeason      = season;
    _currentEpisode     = ep;
    _currentChannel     = null;
    _currentMovie       = null;
    _updateContentNotifiers();
    await _openUrl(ep.url);
    StorageService.instance.addToHistory(
      '${s.id}_S${season.seasonNumber}E${ep.episodeNumber}',
      ContentType.SERIES,
    );
    _startProgressTimer();
    notifyListeners();
  }

  Future<void> playMovie(Movie m) async {
    dev.log('[MediaService] playMovie: ${m.title}', name: 'MediaService');
    _currentContentType = ContentType.MOVIES;
    _currentMovie       = m;
    _currentChannel     = null;
    _currentSeries      = null;
    _currentSeason      = null;
    _currentEpisode     = null;
    _updateContentNotifiers();
    await _openUrl(m.url);
    StorageService.instance.addToHistory(m.id, ContentType.MOVIES);
    _startProgressTimer();
    notifyListeners();
  }

  // ── Episode navigation ────────────────────────────────────────────────────────

  Future<bool> playNextEpisode() async {
    final series  = _currentSeries;
    final season  = _currentSeason;
    final episode = _currentEpisode;
    if (series == null || season == null || episode == null) return false;

    final epIdx = season.episodes.indexOf(episode);

    if (epIdx < season.episodes.length - 1) {
      await playSeries(series, season, season.episodes[epIdx + 1]);
      return true;
    }

    final sIdx = series.seasons.indexOf(season);
    if (sIdx < series.seasons.length - 1) {
      final next = series.seasons[sIdx + 1];
      if (next.episodes.isNotEmpty) {
        await playSeries(series, next, next.episodes.first);
        return true;
      }
    }

    dev.log('[MediaService] No next episode', name: 'MediaService');
    return false;
  }

  Future<bool> playPreviousEpisode() async {
    final series  = _currentSeries;
    final season  = _currentSeason;
    final episode = _currentEpisode;
    if (series == null || season == null || episode == null) return false;

    final epIdx = season.episodes.indexOf(episode);

    if (epIdx > 0) {
      await playSeries(series, season, season.episodes[epIdx - 1]);
      return true;
    }

    final sIdx = series.seasons.indexOf(season);
    if (sIdx > 0) {
      final prev = series.seasons[sIdx - 1];
      if (prev.episodes.isNotEmpty) {
        await playSeries(series, prev, prev.episodes.last);
        return true;
      }
    }

    dev.log('[MediaService] No previous episode', name: 'MediaService');
    return false;
  }

  // ── Channel navigation ────────────────────────────────────────────────────────

  Future<void> playNextChannel(List<Channel> channels) async {
    if (channels.isEmpty) return;
    final ch  = _currentChannel;
    if (ch == null) { await playChannel(channels.first); return; }
    final idx  = channels.indexWhere((c) => c.id == ch.id);
    await playChannel(channels[(idx + 1) % channels.length]);
  }

  Future<void> playPreviousChannel(List<Channel> channels) async {
    if (channels.isEmpty) return;
    final ch  = _currentChannel;
    if (ch == null) { await playChannel(channels.last); return; }
    final idx  = channels.indexWhere((c) => c.id == ch.id);
    await playChannel(channels[(idx - 1 + channels.length) % channels.length]);
  }

  // ── Playback controls ────────────────────────────────────────────────────────

  Future<void> play() async {
    try {
      await _controller?.play();
    } catch (e) {
      _setError('Error al reproducir: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _controller?.pause();
    } catch (e) {
      _setError('Error al pausar: $e');
    }
  }

  Future<void> stop() async {
    _cancelProgressTimer();
    _cancelPositionPollTimer();
    try {
      await _controller?.pause();
      await _controller?.seekTo(Duration.zero);
    } catch (e) {
      _setError('Error al detener: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _controller?.seekTo(position);
    } catch (e) {
      dev.log('[MediaService] Seek error: $e', name: 'MediaService');
    }
  }

  /// Volume in 0–100 range (consistent with previous media_kit API).
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 100.0);
    _volume = clamped;
    volumeNotifier.value = clamped;
    try {
      // video_player uses 0.0–1.0
      await _controller?.setVolume(clamped / 100.0);
    } catch (e) {
      dev.log('[MediaService] Volume error: $e', name: 'MediaService');
    }
  }

  /// Subtitle toggle — ExoPlayer renders embedded MKV subs automatically.
  /// video_player doesn't expose track selection, so this only updates the
  /// UI indicator.
  Future<void> toggleSubtitles() async {
    _subtitlesEnabled = !_subtitlesEnabled;
    subtitlesEnabledNotifier.value = _subtitlesEnabled;
  }

  // ── Progress timer ───────────────────────────────────────────────────────────

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _saveCurrentProgress(),
    );
  }

  void _cancelProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _saveCurrentProgress() {
    final type = _currentContentType;
    if (type == null || type == ContentType.TV) return;
    if (_position <= Duration.zero) return;

    if (type == ContentType.MOVIES && _currentMovie != null) {
      ProgressService.instance.saveProgress(
        contentId:   _currentMovie!.id,
        contentType: ContentType.MOVIES,
        position:    _position,
        duration:    _duration > Duration.zero ? _duration : null,
      );
    } else if (type == ContentType.SERIES &&
        _currentSeries  != null &&
        _currentSeason  != null &&
        _currentEpisode != null) {
      ProgressService.instance.saveProgress(
        contentId:     '${_currentSeries!.id}_S${_currentSeason!.seasonNumber}'
            'E${_currentEpisode!.episodeNumber}',
        contentType:   ContentType.SERIES,
        position:      _position,
        duration:      _duration > Duration.zero ? _duration : null,
        seriesId:      _currentSeries!.id,
        seasonNumber:  _currentSeason!.seasonNumber,
        episodeNumber: _currentEpisode!.episodeNumber,
      );
    }
  }

  // ── Position save ────────────────────────────────────────────────────────────

  void savePosition() {
    final type = _currentContentType;
    if (type == null) return;

    final id = switch (type) {
      ContentType.TV     => _currentChannel?.id,
      ContentType.SERIES => _currentSeries != null &&
              _currentSeason  != null &&
              _currentEpisode != null
          ? '${_currentSeries!.id}_S${_currentSeason!.seasonNumber}'
              'E${_currentEpisode!.episodeNumber}'
          : null,
      ContentType.MOVIES => _currentMovie?.id,
    };

    if (id != null && _position > Duration.zero) {
      StorageService.instance.addToHistory(id, type, position: _position);
      dev.log('[MediaService] Position saved: ${_position.inSeconds}s for $id',
          name: 'MediaService');
    }
  }

  // ── Internal helpers ─────────────────────────────────────────────────────────

  void _updateContentNotifiers() {
    currentContentTypeNotifier.value = _currentContentType;
    currentChannelNotifier.value     = _currentChannel;
    currentSeriesNotifier.value      = _currentSeries;
    currentEpisodeNotifier.value     = _currentEpisode;
    currentMovieNotifier.value       = _currentMovie;
    _position                        = Duration.zero;
    _duration                        = Duration.zero;
    positionNotifier.value           = Duration.zero;
    durationNotifier.value           = Duration.zero;
  }

  void _setError(String msg) {
    _error = msg;
    errorNotifier.value = msg;
    dev.log('[MediaService] $msg', name: 'MediaService');
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    errorNotifier.value = null;
  }

  void _onPlaybackCompleted() {
    _cancelProgressTimer();
    _cancelPositionPollTimer();
    final type = _currentContentType;
    if (type == ContentType.MOVIES && _currentMovie != null) {
      ProgressService.instance.markAsCompleted(_currentMovie!.id);
    } else if (type == ContentType.SERIES &&
        _currentSeries  != null &&
        _currentSeason  != null &&
        _currentEpisode != null) {
      ProgressService.instance.markAsCompleted(
        '${_currentSeries!.id}_S${_currentSeason!.seasonNumber}'
        'E${_currentEpisode!.episodeNumber}',
      );
      playNextEpisode();
    }
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    savePosition();
    _saveCurrentProgress();
    _cancelProgressTimer();
    _cancelPositionPollTimer();

    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();

    videoControllerNotifier.dispose();
    isPlayingNotifier.dispose();
    currentContentTypeNotifier.dispose();
    currentChannelNotifier.dispose();
    currentSeriesNotifier.dispose();
    currentEpisodeNotifier.dispose();
    currentMovieNotifier.dispose();
    durationNotifier.dispose();
    positionNotifier.dispose();
    volumeNotifier.dispose();
    errorNotifier.dispose();
    isBufferingNotifier.dispose();
    completedNotifier.dispose();
    subtitlesEnabledNotifier.dispose();

    super.dispose();
  }
}
