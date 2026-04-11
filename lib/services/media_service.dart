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
  Timer?                 _seekTimeoutTimer;
  Timer?                 _bufferingWatchdogTimer;
  Timer?                 _spinnerDebounceTimer;
  int                    _openGeneration  = 0;
  DateTime               _lastPositionAdvance = DateTime.now();

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
  /// started.  Sets error state on failure.
  ///
  /// Uses a generation counter so that if a second call arrives while the
  /// first [ctrl.initialize()] is still running, the stale result is discarded
  /// and only the latest request takes effect.
  Future<void> _openUrl(String url) async {
    _cancelProgressTimer();
    _cancelPositionPollTimer();
    _seekTimeoutTimer?.cancel();
    _seekTimeoutTimer = null;
    _cancelBufferingWatchdog();
    _spinnerDebounceTimer?.cancel();
    _spinnerDebounceTimer = null;
    _clearError();
    completedNotifier.value   = false;
    isBufferingNotifier.value = true;

    // Tear down the active controller NOW (synchronously) so the old stream
    // stops playing immediately and its listener can no longer fire.
    final staleCtrl = _controller;
    _controller = null;
    videoControllerNotifier.value = null;
    if (staleCtrl != null) {
      staleCtrl.removeListener(_onControllerUpdate);
      staleCtrl.dispose();
    }

    // Stamp this request so a concurrent _openUrl() that finishes later can
    // detect it is stale and discard its result.
    final generation = ++_openGeneration;

    // Encode URL to handle spaces and special characters
    final safeUrl = Uri.encodeFull(url);

    dev.log('[MediaService] Opening (gen $generation): $safeUrl',
        name: 'MediaService');
    dev.log('[MediaService] Type: $_currentContentType', name: 'MediaService');
    // ignore: avoid_print
    print('=== MEDIA URL  === $safeUrl');
    // ignore: avoid_print
    print('=== MEDIA TYPE === $_currentContentType');

    // Attempt 1: with Chrome UA headers
    // Attempt 2: no headers (some servers block specific UA for certain categories)
    final attempts = [_headers, <String, String>{}];

    for (int attempt = 0; attempt < attempts.length; attempt++) {
      final ctrl = VideoPlayerController.networkUrl(
        Uri.parse(safeUrl),
        httpHeaders: attempts[attempt],
      );

      try {
        await ctrl.initialize();

        // Another _openUrl() call arrived while we were initialising — discard.
        if (generation != _openGeneration) {
          ctrl.dispose();
          dev.log('[MediaService] Stale open discarded (gen $generation)',
              name: 'MediaService');
          return;
        }

        dev.log('[MediaService] ExoPlayer OK (attempt ${attempt + 1}) — '
            'duration: ${ctrl.value.duration}', name: 'MediaService');

        _controller = ctrl;
        _duration   = ctrl.value.duration;
        _position   = Duration.zero;

        durationNotifier.value = _duration;
        positionNotifier.value = Duration.zero;

        ctrl.addListener(_onControllerUpdate);
        await ctrl.setVolume(_volume / 100.0);
        await ctrl.play();

        videoControllerNotifier.value = ctrl;
        isBufferingNotifier.value = false;
        _startPositionPollTimer();

        return; // success — stop trying
      } catch (e) {
        ctrl.dispose();
        dev.log('[MediaService] Attempt ${attempt + 1} failed: $e',
            name: 'MediaService');
        if (attempt == attempts.length - 1) {
          // All attempts exhausted — only report error if we're still current.
          if (generation == _openGeneration) {
            isBufferingNotifier.value = false;
            _setError('No se pudo abrir el stream.\nURL: $safeUrl\n$e');
          }
        }
      }
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
    if (val.isBuffering && !isBufferingNotifier.value) {
      // Buffering started.
      // Live TV: debounce 1.5 s so brief recoveries don't flash the spinner.
      // VOD:     show immediately (seek already set it explicitly).
      if (_currentContentType == ContentType.TV) {
        _spinnerDebounceTimer?.cancel();
        _spinnerDebounceTimer = Timer(
          const Duration(milliseconds: 1500),
          () {
            if (_controller?.value.isBuffering == true) {
              isBufferingNotifier.value = true;
            }
          },
        );
      } else {
        isBufferingNotifier.value = true;
      }
      _startBufferingWatchdog();
    } else if (!val.isBuffering) {
      // Buffering cleared — cancel debounce so spinner never shows for
      // brief events, and cancel all safety timers.
      _spinnerDebounceTimer?.cancel();
      _spinnerDebounceTimer = null;
      isBufferingNotifier.value = false;
      _seekTimeoutTimer?.cancel();
      _seekTimeoutTimer = null;
      _cancelBufferingWatchdog();
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
    _lastPositionAdvance = DateTime.now();
    _positionPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) async {
        final ctrl = _controller;
        if (ctrl == null || !ctrl.value.isInitialized) return;
        final pos = ctrl.value.position;
        if (_position != pos) {
          _position = pos;
          positionNotifier.value = pos;
          _lastPositionAdvance = DateTime.now();

          // Position is advancing → stream is actually playing.
          // ExoPlayer sometimes leaves isBuffering=true even after recovery
          // (known HLS live bug). Position advancement is the ground truth:
          // if it moves, we are playing — force-clear spinner and all timers.
          if (isBufferingNotifier.value) {
            isBufferingNotifier.value = false;
            _spinnerDebounceTimer?.cancel();
            _spinnerDebounceTimer = null;
            _seekTimeoutTimer?.cancel();
            _seekTimeoutTimer = null;
            _cancelBufferingWatchdog();
            dev.log('[MediaService] Position advancing — forced buffering clear',
                name: 'MediaService');
          }
        } else if (_currentContentType == ContentType.TV &&
            ctrl.value.isPlaying) {
          // Live TV: position not advancing despite isPlaying=true.
          // Catches both buffering-reported and silent stalls.
          final stuck = DateTime.now().difference(_lastPositionAdvance);
          if (stuck.inSeconds >= 8) {
            dev.log(
                '[MediaService] Stall ${stuck.inSeconds}s — restarting',
                name: 'MediaService');
            _lastPositionAdvance = DateTime.now(); // prevent repeated restarts
            await _restartCurrentStream();
          }
        }
      },
    );
  }

  void _cancelPositionPollTimer() {
    _positionPollTimer?.cancel();
    _positionPollTimer = null;
  }

  // ── Buffering watchdog ────────────────────────────────────────────────────────
  //
  // Restarts the stream if ExoPlayer stays buffering without recovering.
  // Live TV: 6 s timeout (streams rarely need more to recover).
  // VOD:     15 s timeout (seek + buffering can take longer on slow servers).

  void _startBufferingWatchdog() {
    _bufferingWatchdogTimer?.cancel();
    // Only restart on buffering for live TV. Live streams should recover in
    // seconds; if they don't, reconnecting is cheap.
    //
    // VOD (movies / series) intentionally has NO watchdog:
    //   - MP4 movies may legitimately buffer for >20 s before first frame.
    //   - HLS series segments buffer quickly on their own.
    //   - The position-poll already force-clears the spinner the moment the
    //     position advances, so no watchdog is needed for VOD.
    //   - A watchdog for VOD would restart the stream in a loop and prevent
    //     movies from ever starting (the original bug).
    if (_currentContentType != ContentType.TV) return;
    _bufferingWatchdogTimer = Timer(const Duration(seconds: 12), () async {
      if (!isBufferingNotifier.value) return; // Already recovered.
      dev.log('[MediaService] Buffering watchdog fired — restarting stream',
          name: 'MediaService');
      await _restartCurrentStream();
    });
  }

  void _cancelBufferingWatchdog() {
    _bufferingWatchdogTimer?.cancel();
    _bufferingWatchdogTimer = null;
  }

  /// Reopens the current content URL from scratch.
  /// For VOD, attempts to restore the playback position after reconnect.
  Future<void> _restartCurrentStream() async {
    final type     = _currentContentType;
    final savedPos = _position;
    String? url;
    if (type == ContentType.TV)     url = _currentChannel?.url;
    if (type == ContentType.SERIES) url = _currentEpisode?.url;
    if (type == ContentType.MOVIES) url = _currentMovie?.url;
    if (url == null) return;

    await _openUrl(url);

    // Restore VOD position after reconnect (not needed for live streams).
    if (type != ContentType.TV && savedPos > const Duration(seconds: 2)) {
      await seek(savedPos);
    }
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
    // Show spinner immediately and guard against ExoPlayer not firing isBuffering.
    isBufferingNotifier.value = true;
    _seekTimeoutTimer?.cancel();
    _seekTimeoutTimer = Timer(const Duration(seconds: 10), () {
      isBufferingNotifier.value = false;
      dev.log('[MediaService] Seek timeout — forced buffering clear',
          name: 'MediaService');
    });
    try {
      await _controller?.seekTo(position);
    } catch (e) {
      _seekTimeoutTimer?.cancel();
      _seekTimeoutTimer = null;
      isBufferingNotifier.value = false;
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
    _seekTimeoutTimer?.cancel();
    _cancelBufferingWatchdog();
    _spinnerDebounceTimer?.cancel();

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
