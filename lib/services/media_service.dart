import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/models.dart';
import 'progress_service.dart';
import 'storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MediaService
// ─────────────────────────────────────────────────────────────────────────────

class MediaService extends ChangeNotifier {
  MediaService._();
  static final MediaService instance = MediaService._();

  // ── Player ───────────────────────────────────────────────────────────────────

  late final Player           _player;
  late final VideoController  videoController;

  StreamSubscription<bool>?     _playingSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>?     _bufferingSub;
  StreamSubscription<String>?   _errorSub;
  StreamSubscription<bool>?     _completedSub;
  Timer?                        _progressTimer;

  // Retry state: after a format/codec error we retry once with VLC headers
  String? _lastUrl;
  bool    _retryPending = false;

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

  bool         get isPlaying          => _isPlaying;
  ContentType? get currentContentType => _currentContentType;
  Channel?     get currentChannel     => _currentChannel;
  Series?      get currentSeries      => _currentSeries;
  Season?      get currentSeason      => _currentSeason;
  Episode?     get currentEpisode     => _currentEpisode;
  Movie?       get currentMovie       => _currentMovie;
  Duration     get duration           => _duration;
  Duration     get position           => _position;
  double       get volume             => _volume;
  String?      get error              => _error;
  bool         get subtitlesEnabled   => _subtitlesEnabled;

  /// Progress 0.0–1.0, or 0 if duration is zero.
  double get progress =>
      _duration.inMilliseconds > 0
          ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;

  // ── Init ─────────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    MediaKit.ensureInitialized();
    _player = Player(
      configuration: PlayerConfiguration(
        // ready() fires once the internal mpv context is fully initialized.
        // This is the only safe moment to call setProperty(); calling it
        // earlier (right after Player()) crashes because the mpv handle
        // doesn't exist yet.
        ready: _applyMkvFix,
      ),
    );
    videoController = VideoController(_player);
    _subscribeToStreams();
    dev.log('[MediaService] Initialized', name: 'MediaService');
  }

  /// Configures libmpv for reliable MKV playback over HTTP.
  ///
  /// Root cause of "Failed to recognize file format":
  ///   - mpv's native EBML/Matroska demuxer has a parser bug (mpv #15691)
  ///     that misidentifies certain MKV streams served over HTTP.
  ///   - Fix: force FFmpeg's lavf demuxer (+lavf), which handles Matroska
  ///     correctly and is the same code path used by VLC.
  ///   - Increase probe size/duration so slow IPTV servers have enough time
  ///     to deliver sufficient data for format detection.
  void _applyMkvFix() {
    if (_player.platform is! NativePlayer) return;
    final native = _player.platform as NativePlayer;
    // Errors are swallowed — a failed property set must never crash the app.
    native.setProperty('demuxer', '+lavf').catchError((_) {});
    native.setProperty('demuxer-lavf-probesize', '8388608').catchError((_) {});
    native.setProperty('demuxer-lavf-analyzeduration', '10').catchError((_) {});
    native.setProperty('hwdec', 'auto-safe').catchError((_) {});
    dev.log('[MediaService] MKV fix applied (lavf demuxer, 8 MB probe)',
        name: 'MediaService');
  }

  void _subscribeToStreams() {
    _playingSub = _player.stream.playing.listen((playing) {
      if (_isPlaying != playing) {
        _isPlaying = playing;
        isPlayingNotifier.value = playing;
        notifyListeners();
      }
    });

    _durationSub = _player.stream.duration.listen((dur) {
      if (_duration != dur) {
        _duration = dur;
        durationNotifier.value = dur;
        notifyListeners();
      }
    });

    _positionSub = _player.stream.position.listen((pos) {
      if (_position != pos) {
        _position = pos;
        positionNotifier.value = pos;
        // position fires too often — no notifyListeners()
      }
    });

    _bufferingSub = _player.stream.buffering.listen((buffering) {
      if (isBufferingNotifier.value != buffering) {
        isBufferingNotifier.value = buffering;
      }
    });

    _errorSub = _player.stream.error.listen((errStr) {
      if (errStr.isEmpty || _error == errStr) return;

      _error = errStr;
      errorNotifier.value = errStr;
      dev.log('[MediaService] Video error: $errStr — URL: $_lastUrl',
          name: 'MediaService');

      // Detect format/codec errors and retry once with VLC headers.
      // These errors come from libmpv and typically mean the server is blocking
      // the Chrome UA or the stream needs a plain HTTP range request.
      final lower = errStr.toLowerCase();
      final isFormatError = lower.contains('format') ||
          lower.contains('codec') ||
          lower.contains('recognized') ||
          lower.contains('invalid data') ||
          lower.contains('failed to open');

      if (isFormatError && !_retryPending && _lastUrl != null) {
        _retryPending = true;
        dev.log('[MediaService] Format/codec error detectado — '
            'reintentando con VLC User-Agent...',
            name: 'MediaService');
        _retryWithVlcHeaders();
      } else {
        notifyListeners();
      }
    });

    _completedSub = _player.stream.completed.listen((completed) {
      if (completed && !completedNotifier.value) {
        completedNotifier.value = true;
        dev.log('[MediaService] Playback completed', name: 'MediaService');
        _onPlaybackCompleted();
      }
    });
  }

  // ── Open URL ─────────────────────────────────────────────────────────────────

  // Primary headers — Chrome UA, used for live TV and series on first attempt
  static const _fullHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'http://iota.proxy-pass.vip/',
    'Origin': 'http://iota.proxy-pass.vip',
    'Accept': '*/*',
    'Accept-Language': 'es-ES,es;q=0.9',
    'Accept-Encoding': 'gzip, deflate',
    'Cache-Control': 'no-cache',
    'Pragma': 'no-cache',
    'Connection': 'keep-alive',
  };

  // Movie headers — VLC UA + Range from the start.
  // MKV files require an HTTP Range request so libmpv can probe the container
  // format correctly; without it the server may return a partial/chunked
  // response that libmpv cannot recognize ("Failed to recognize file format").
  static const _movieHeaders = <String, String>{
    'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
    'Connection': 'keep-alive',
    'Range': 'bytes=0-',
  };

  // Fallback headers — VLC UA + Range, used when first attempt reports a
  // format/codec error (many IPTV providers gate content behind UA detection).
  static const _vlcHeaders = <String, String>{
    'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20',
    'Connection': 'keep-alive',
    'Range': 'bytes=0-',
  };

  Future<void> _openUrl(String url) async {
    _lastUrl      = url;
    _retryPending = false;
    _clearError();
    completedNotifier.value        = false;
    isBufferingNotifier.value      = false;
    _subtitlesEnabled              = false;
    subtitlesEnabledNotifier.value = false;

    // Movies (typically MKV) need Range: bytes=0- from the first request so
    // libmpv can seek to the moov atom and identify the container format.
    final headers = _currentContentType == ContentType.MOVIES
        ? _movieHeaders
        : _fullHeaders;

    dev.log('[MediaService] Intentando reproducir: $url', name: 'MediaService');
    dev.log('[MediaService] Tipo de contenido: $_currentContentType — '
        'headers: ${_currentContentType == ContentType.MOVIES ? "movie" : "full"}',
        name: 'MediaService');
    // ignore: avoid_print
    print('=== URL PELÍCULA === $url');
    // ignore: avoid_print
    print('=== TIPO ========== $_currentContentType');

    try {
      await _player.open(Media(url, httpHeaders: headers));
      // Subtitles off by default; user can enable via toggleSubtitles().
      await _player.setSubtitleTrack(SubtitleTrack.no());
    } catch (e) {
      dev.log('[MediaService] Error al abrir stream: $e', name: 'MediaService');
      _setError('No se pudo abrir el stream. Comprueba la URL o la conexión.');
    }
  }

  /// Retries [_lastUrl] with VLC headers after a format/codec error.
  Future<void> _retryWithVlcHeaders() async {
    final url = _lastUrl;
    if (url == null) return;
    _clearError();
    dev.log('[MediaService] Reintentando con VLC headers: $url',
        name: 'MediaService');
    try {
      await _player.open(Media(url, httpHeaders: _vlcHeaders));
      await _player.setSubtitleTrack(SubtitleTrack.no());
      dev.log('[MediaService] Reintento exitoso: $url', name: 'MediaService');
    } catch (e) {
      dev.log('[MediaService] Reintento también falló: $e',
          name: 'MediaService');
      _retryPending = false;
      _setError('Formato no soportado o stream caído.');
    }
  }

  // ── Playback commands ────────────────────────────────────────────────────────

  Future<void> playChannel(Channel ch) async {
    dev.log('[MediaService] playChannel: ${ch.name}', name: 'MediaService');
    _cancelProgressTimer();
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
    dev.log('[MediaService] playSeries: ${s.name} S${season.seasonNumber}E${ep.episodeNumber}',
        name: 'MediaService');
    _cancelProgressTimer();
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
    _cancelProgressTimer();
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

  /// Returns true if there was a next episode to play.
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
      final nextSeason = series.seasons[sIdx + 1];
      if (nextSeason.episodes.isNotEmpty) {
        await playSeries(series, nextSeason, nextSeason.episodes.first);
        return true;
      }
    }

    dev.log('[MediaService] No next episode available', name: 'MediaService');
    return false;
  }

  /// Returns true if there was a previous episode to play.
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
      final prevSeason = series.seasons[sIdx - 1];
      if (prevSeason.episodes.isNotEmpty) {
        await playSeries(series, prevSeason, prevSeason.episodes.last);
        return true;
      }
    }

    dev.log('[MediaService] No previous episode available', name: 'MediaService');
    return false;
  }

  // ── Channel navigation ────────────────────────────────────────────────────────

  Future<void> playNextChannel(List<Channel> channels) async {
    if (channels.isEmpty) return;
    final ch = _currentChannel;
    if (ch == null) { await playChannel(channels.first); return; }
    final idx  = channels.indexWhere((c) => c.id == ch.id);
    final next = channels[(idx + 1) % channels.length];
    await playChannel(next);
  }

  Future<void> playPreviousChannel(List<Channel> channels) async {
    if (channels.isEmpty) return;
    final ch = _currentChannel;
    if (ch == null) { await playChannel(channels.last); return; }
    final idx  = channels.indexWhere((c) => c.id == ch.id);
    final prev = channels[(idx - 1 + channels.length) % channels.length];
    await playChannel(prev);
  }

  // ── Playback controls ────────────────────────────────────────────────────────

  Future<void> play() async {
    try {
      await _player.play();
    } catch (e) {
      _setError('Error al reproducir: $e');
    }
  }

  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      _setError('Error al pausar: $e');
    }
  }

  Future<void> stop() async {
    _cancelProgressTimer();
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (e) {
      _setError('Error al detener: $e');
    }
  }

  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      dev.log('[MediaService] Seek error: $e', name: 'MediaService');
    }
  }

  /// Volume in 0–100 range.
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 100.0);
    _volume = clamped;
    volumeNotifier.value = clamped;
    try {
      await _player.setVolume(clamped);
    } catch (e) {
      dev.log('[MediaService] Volume error: $e', name: 'MediaService');
    }
  }

  /// Toggles subtitles on/off. For VOD content only; live TV has no subtitles.
  Future<void> toggleSubtitles() async {
    _subtitlesEnabled = !_subtitlesEnabled;
    subtitlesEnabledNotifier.value = _subtitlesEnabled;
    try {
      await _player.setSubtitleTrack(
        _subtitlesEnabled ? SubtitleTrack.auto() : SubtitleTrack.no(),
      );
      dev.log('[MediaService] Subtítulos: ${_subtitlesEnabled ? "ON" : "OFF"}',
          name: 'MediaService');
    } catch (e) {
      dev.log('[MediaService] Subtitle toggle error: $e', name: 'MediaService');
    }
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
      final contentId =
          '${_currentSeries!.id}_S${_currentSeason!.seasonNumber}E${_currentEpisode!.episodeNumber}';
      ProgressService.instance.saveProgress(
        contentId:     contentId,
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
              _currentSeason != null &&
              _currentEpisode != null
          ? '${_currentSeries!.id}_S${_currentSeason!.seasonNumber}E${_currentEpisode!.episodeNumber}'
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
    // Mark progress as completed so "Continuar viendo" won't show this item.
    final type = _currentContentType;
    if (type == ContentType.MOVIES && _currentMovie != null) {
      ProgressService.instance.markAsCompleted(_currentMovie!.id);
    } else if (type == ContentType.SERIES &&
        _currentSeries  != null &&
        _currentSeason  != null &&
        _currentEpisode != null) {
      ProgressService.instance.markAsCompleted(
        '${_currentSeries!.id}_S${_currentSeason!.seasonNumber}E${_currentEpisode!.episodeNumber}',
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

    _playingSub?.cancel();
    _durationSub?.cancel();
    _positionSub?.cancel();
    _bufferingSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();

    _player.dispose();

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
