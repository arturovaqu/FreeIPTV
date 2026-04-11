import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/models.dart';
import '../services/media_service.dart';
import '../services/progress_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/responsive.dart';
import '../widgets/professional_player.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlayerScreen
// ─────────────────────────────────────────────────────────────────────────────

class PlayerScreen extends StatefulWidget {
  final Channel?  channel;
  final Series?   series;
  final Season?   season;
  final Episode?  episode;
  final Movie?    movie;
  /// If set, seek to this position automatically (no dialog). Used when
  /// navigating from "Continuar viendo" or a detail sheet with explicit choice.
  final Duration? startPosition;
  /// Full channel list for next/prev channel navigation (TV mode)
  final List<Channel> channels;

  const PlayerScreen.channel({
    super.key,
    required this.channel,
    this.channels = const [],
  })  : series        = null,
        season        = null,
        episode       = null,
        movie         = null,
        startPosition = null;

  const PlayerScreen.series({
    super.key,
    required this.series,
    required this.season,
    required this.episode,
    this.startPosition,
    this.channels = const [],
  })  : channel = null,
        movie   = null;

  const PlayerScreen.movie({
    super.key,
    required this.movie,
    this.startPosition,
    this.channels = const [],
  })  : channel = null,
        series  = null,
        season  = null,
        episode = null;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class _PlayerScreenState extends State<PlayerScreen> {
  final _media  = MediaService.instance;
  final _storage = StorageService.instance;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool    _controlsVisible  = true;
  bool    _showVolumeSlider = false;
  bool    _isBuffering      = false;
  bool    _isFullscreen     = false;
  bool    _subtitlesEnabled = false;
  String? _error;

  // True for live TV, false for movies/series (VOD)
  bool get _isLive => _type == ContentType.TV;

  // ── Timers ─────────────────────────────────────────────────────────────────
  Timer?  _hideTimer;
  Timer?  _nextEpTimer;
  Timer?  _volumeHideTimer;
  int     _nextEpCountdown  = 10;

  // ── Listeners ──────────────────────────────────────────────────────────────
  late final VoidCallback _bufferingListener;
  late final VoidCallback _completedListener;
  late final VoidCallback _errorListener;
  late final VoidCallback _subtitleListener;

  // ── Swipe tracking ────────────────────────────────────────────────────────
  double _swipeDx = 0;

  // ── Focus ─────────────────────────────────────────────────────────────────
  final _focusNode = FocusNode();

  // ── Helpers ────────────────────────────────────────────────────────────────

  ContentType get _type {
    if (widget.channel != null) return ContentType.TV;
    if (widget.series  != null) return ContentType.SERIES;
    return ContentType.MOVIES;
  }

  String get _currentId {
    switch (_type) {
      case ContentType.TV:
        return widget.channel!.id;
      case ContentType.SERIES:
        return '${widget.series!.id}_'
            'S${widget.season!.seasonNumber}'
            'E${widget.episode!.episodeNumber}';
      case ContentType.MOVIES:
        return widget.movie!.id;
    }
  }

  String get _title {
    switch (_type) {
      case ContentType.TV:
        return widget.channel!.name;
      case ContentType.SERIES:
        return 'T${widget.season!.seasonNumber} '
            'E${widget.episode!.episodeNumber} — '
            '${widget.episode!.title}';
      case ContentType.MOVIES:
        return widget.movie!.title;
    }
  }

  String get _subtitle {
    if (_type == ContentType.SERIES) return widget.series!.name;
    if (_type == ContentType.TV)     return widget.channel!.group;
    return widget.movie?.durationLabel ?? '';
  }

  // ── Init / dispose ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _enterImmersive();
    _startPlayback();
    _setupListeners();
    _scheduleHide();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _savePosition();
    _media.stop(); // stop playback so audio doesn't continue after navigation
    _hideTimer?.cancel();
    _nextEpTimer?.cancel();
    _volumeHideTimer?.cancel();
    _media.isBufferingNotifier.removeListener(_bufferingListener);
    _media.completedNotifier.removeListener(_completedListener);
    _media.errorNotifier.removeListener(_errorListener);
    _media.subtitlesEnabledNotifier.removeListener(_subtitleListener);
    _focusNode.dispose();
    _exitImmersive();
    super.dispose();
  }

  // ── Immersive mode ─────────────────────────────────────────────────────────

  void _enterImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitImmersive() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  void _startPlayback() {
    // Update session activity and warn if another device is concurrently active
    _storage.updateActivity().then((_) async {
      if (!mounted) return;
      final concurrent = await _storage.isSessionActive();
      if (concurrent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'La app está activa en otro dispositivo. '
              'Esto puede causar bloqueos.',
            ),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    });

    _startPlaybackAsync();
  }

  Future<void> _startPlaybackAsync() async {
    switch (_type) {
      case ContentType.TV:
        await _media.playChannel(widget.channel!);
        return; // live TV: no position restore
      case ContentType.SERIES:
        await _media.playSeries(widget.series!, widget.season!, widget.episode!);
      case ContentType.MOVIES:
        await _media.playMovie(widget.movie!);
    }

    if (!mounted) return;

    // Controller is now initialized — handle position restore immediately.
    final explicit = widget.startPosition;
    if (explicit != null && explicit.inSeconds > 5) {
      // Caller already decided where to start (from detail sheet / continue tab)
      _media.seek(explicit);
      dev.log('[PlayerScreen] Auto-seeked to ${explicit.inSeconds}s',
          name: 'PlayerScreen');
    } else {
      // Check saved progress and ask the user
      final progress = ProgressService.instance.getProgress(_currentId);
      if (progress != null &&
          !progress.isCompleted &&
          progress.position.inSeconds > 5) {
        _showResumeDialog(progress.position);
      }
    }
  }

  void _showResumeDialog(Duration position) {
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Reanudar reproducción'),
        content: Text('¿Continuar desde ${_fmtDur(position)}?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _media.seek(Duration.zero);
            },
            child: const Text('Desde el inicio',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _media.seek(position);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reanudar'),
          ),
        ],
      ),
    );
  }

  void _retryPlayback() {
    setState(() => _error = null);
    _startPlaybackAsync();
  }

  void _savePosition() {
    _storage.addToHistory(
      _currentId,
      _type,
      position: _media.position,
    );
    dev.log('[PlayerScreen] Saved position: ${_media.position.inSeconds}s',
        name: 'PlayerScreen');
  }

  // ── Listeners ──────────────────────────────────────────────────────────────

  void _setupListeners() {
    // Buffering
    _bufferingListener = () {
      if (mounted) setState(() => _isBuffering = _media.isBufferingNotifier.value);
    };
    _media.isBufferingNotifier.addListener(_bufferingListener);

    // Error
    _errorListener = () {
      final err = _media.error;
      if (err != null && mounted) setState(() => _error = err);
    };
    _media.errorNotifier.addListener(_errorListener);

    // Subtitles
    _subtitleListener = () {
      if (mounted) {
        setState(() => _subtitlesEnabled = _media.subtitlesEnabledNotifier.value);
      }
    };
    _media.subtitlesEnabledNotifier.addListener(_subtitleListener);

    // Playback completed → show next episode prompt
    _completedListener = () {
      if (_media.completedNotifier.value &&
          _type == ContentType.SERIES &&
          mounted) {
        _startNextEpCountdown();
      }
    };
    _media.completedNotifier.addListener(_completedListener);
  }

  // ── Controls visibility ────────────────────────────────────────────────────

  void _showControls() {
    setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(AppDurations.playerHide, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _cancelHide() => _hideTimer?.cancel();

  /// Shows the volume slider overlay and schedules its auto-dismiss.
  void _showVolumeOverlay() {
    _volumeHideTimer?.cancel();
    if (!_showVolumeSlider) setState(() => _showVolumeSlider = true);
    _volumeHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showVolumeSlider = false);
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  // ── Next episode countdown ─────────────────────────────────────────────────

  void _startNextEpCountdown() {
    setState(() => _nextEpCountdown = 10);
    _nextEpTimer?.cancel();
    _nextEpTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _nextEpCountdown--);
      if (_nextEpCountdown <= 0) {
        t.cancel();
        _playNext();
      }
    });
  }

  void _cancelNextEpCountdown() {
    _nextEpTimer?.cancel();
    setState(() => _nextEpCountdown = 10);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _playNext() async {
    if (_type == ContentType.TV) {
      await _media.playNextChannel(widget.channels);
    } else if (_type == ContentType.SERIES) {
      final ok = await _media.playNextEpisode();
      if (!ok && mounted) _showEndOfSeriesDialog();
    }
  }

  Future<void> _playPrev() async {
    if (_type == ContentType.TV) {
      await _media.playPreviousChannel(widget.channels);
    } else if (_type == ContentType.SERIES) {
      await _media.playPreviousEpisode();
    }
  }

  void _skipIntro() {
    _media.seek(_media.position + const Duration(seconds: 90));
    _showControls();
  }

  void _toggleSubtitles() {
    if (StorageService.instance.useProfessionalMotor()) {
      _showTrackSelector();
    } else {
      _media.toggleSubtitles();
      _showControls();
    }
  }

  void _showTrackSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const TrackSelectorModal(),
    );
  }

  void _showEndOfSeriesDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Serie terminada',
            style: AppTextStyles.headlineSmall),
        content: const Text(
            '¡Has terminado todos los episodios disponibles!',
            style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  // ── D-Pad keyboard handler ─────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _showControls();

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _media.seek(_media.position + const Duration(seconds: 10));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        final newPos = _media.position - const Duration(seconds: 10);
        _media.seek(newPos < Duration.zero ? Duration.zero : newPos);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _media.setVolume((_media.volume + 5).clamp(0, 100));
        _showVolumeOverlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _media.setVolume((_media.volume - 5).clamp(0, 100));
        _showVolumeOverlay();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.select:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        _media.isPlaying ? _media.pause() : _media.play();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
      case LogicalKeyboardKey.goBack:
        Navigator.pop(context);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  // ── Fullscreen ────────────────────────────────────────────────────────────

  void _toggleFullscreen() {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  // ── Favorites ─────────────────────────────────────────────────────────────

  String get _favId {
    if (_type == ContentType.SERIES) return widget.series!.id;
    return _currentId;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final device = getDeviceInfo(context);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── 1. Video ──────────────────────────────────────────────────
            Positioned.fill(
              child: _buildVideoRenderer(),
            ),

            // ── 2. Gesture layer ──────────────────────────────────────────
            Positioned.fill(child: _buildGestureLayer()),

            // ── 3. Buffering spinner ──────────────────────────────────────
            if (_isBuffering && _error == null)
              const Center(
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white70,
                  ),
                ),
              ),

            // ── 4. Controls overlay ───────────────────────────────────────
            if (_error == null)
              AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: AppDurations.normal,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _buildControlsOverlay(device),
                ),
              ),

            // ── 5. Error overlay ──────────────────────────────────────────
            if (_error != null) _buildErrorOverlay(),

            // ── 6. Next episode prompt ────────────────────────────────────
            if (_type == ContentType.SERIES &&
                _nextEpCountdown < 10 &&
                _nextEpTimer != null)
              _buildNextEpPrompt(),

            // ── 7. Volume slider ──────────────────────────────────────────
            if (_showVolumeSlider) _buildVolumeOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoRenderer() {
    if (StorageService.instance.useProfessionalMotor()) {
      return ValueListenableBuilder<VideoController?>(
        valueListenable: _media.mediaKitControllerNotifier,
        builder: (_, ctrl, __) {
          if (ctrl == null) return const SizedBox.shrink();
          return ProfessionalPlayer(controller: ctrl);
        },
      );
    } else {
      return ValueListenableBuilder<VideoPlayerController?>(
        valueListenable: _media.videoControllerNotifier,
        builder: (_, ctrl, __) {
          if (ctrl == null || !ctrl.value.isInitialized) return const SizedBox.shrink();
          return Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : 16 / 9,
              child: VideoPlayer(ctrl),
            ),
          );
        },
      );
    }
  }

  // ── Gesture layer ─────────────────────────────────────────────────────────

  Widget _buildGestureLayer() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTap: _toggleFullscreen,
      onLongPress: _type == ContentType.SERIES ? _showSeriesOptions : null,
      onHorizontalDragStart: (_) => _swipeDx = 0,
      onHorizontalDragUpdate: (d) => _swipeDx += d.delta.dx,
      onHorizontalDragEnd: (_) {
        if (_swipeDx.abs() > 60) {
          _swipeDx > 0 ? _playPrev() : _playNext();
        }
        _swipeDx = 0;
      },
    );
  }

  // ── Controls overlay ──────────────────────────────────────────────────────

  Widget _buildControlsOverlay(DeviceInfo device) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCC000000),
            Colors.transparent,
            Colors.transparent,
            Color(0xDD000000),
          ],
          stops: [0.0, 0.25, 0.70, 1.0],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildTopBar(device),
          _buildProgressBar(),
          _buildBottomBar(device),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar(DeviceInfo device) {
    final btnSize = ResponsiveSpacing.getButtonHeight(device);
    final iconSz  = ResponsiveSpacing.getIconSize(device);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            // Back
            _CtrlButton(
              icon: Icons.arrow_back,
              buttonSize: btnSize,
              size: iconSz,
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: AppSpacing.md),
            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_title,
                      style: AppTextStyles.playerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (_subtitle.isNotEmpty)
                    Text(_subtitle,
                        style: AppTextStyles.playerSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Favorite
            Consumer<StorageService>(
              builder: (_, storage, __) {
                final isFav = storage.isFavorite(_favId, _type);
                return _CtrlButton(
                  icon:
                      isFav ? Icons.favorite : Icons.favorite_border,
                  buttonSize: btnSize,
                  size: iconSz,
                  color: isFav ? AppColors.error : Colors.white,
                  onPressed: () => isFav
                      ? storage.removeFavorite(_favId, _type)
                      : storage.saveFavorite(_favId, _type),
                );
              },
            ),
            // Series options (skip intro shortcut)
            if (_type == ContentType.SERIES)
              _CtrlButton(
                icon: Icons.skip_next,
                buttonSize: btnSize,
                size: iconSz,
                label: 'Saltar intro',
                onPressed: _skipIntro,
              ),
            // Fullscreen toggle
            _CtrlButton(
              icon: _isFullscreen
                  ? Icons.fullscreen_exit
                  : Icons.fullscreen,
              buttonSize: btnSize,
              size: iconSz,
              onPressed: _toggleFullscreen,
            ),
          ],
        ),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    return ValueListenableBuilder<Duration>(
      valueListenable: _media.positionNotifier,
      builder: (_, pos, __) {
        return ValueListenableBuilder<Duration>(
          valueListenable: _media.durationNotifier,
          builder: (_, dur, __) {
            final maxMs = dur.inMilliseconds.toDouble();
            final curMs = pos.inMilliseconds
                .toDouble()
                .clamp(0.0, maxMs == 0 ? 1.0 : maxMs);
            // Use content type to decide live/VOD — more reliable than duration == 0
            // which can briefly be zero during buffering.
            final isLive = _isLive;

            if (isLive) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentLive,
                      borderRadius: AppRadius.chipRadius,
                    ),
                    child: const Text('EN VIVO',
                        style: AppTextStyles.badge),
                  ),
                ]),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                      overlayShape: SliderComponentShape.noOverlay,
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: curMs,
                      min: 0,
                      max: maxMs == 0 ? 1 : maxMs,
                      onChangeStart: (_) => _cancelHide(),
                      onChanged: (v) =>
                          _media.seek(Duration(
                              milliseconds: v.toInt())),
                      onChangeEnd: (_) => _scheduleHide(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_fmtDur(pos),
                            style: AppTextStyles.bodySmall
                                .copyWith(color: Colors.white70)),
                        Text(_fmtDur(dur),
                            style: AppTextStyles.bodySmall
                                .copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar(DeviceInfo device) {
    final btnSize      = ResponsiveSpacing.getButtonHeight(device);
    final largeBtnSize = device.isTV ? 80.0 : device.isDesktop ? 72.0 : 64.0;
    final iconSz       = ResponsiveSpacing.getIconSize(device);
    final largeIconSz  = device.isTV ? 48.0 : 40.0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Previous
            _CtrlButton(
              icon: Icons.skip_previous,
              buttonSize: btnSize,
              size: iconSz,
              onPressed: _playPrev,
            ),

            const SizedBox(width: AppSpacing.md),

            // Play / Pause
            ValueListenableBuilder<bool>(
              valueListenable: _media.isPlayingNotifier,
              builder: (_, playing, __) => _CtrlButton(
                icon: playing ? Icons.pause : Icons.play_arrow,
                buttonSize: largeBtnSize,
                size: largeIconSz,
                large: true,
                onPressed:
                    playing ? _media.pause : _media.play,
              ),
            ),

            const SizedBox(width: AppSpacing.md),

            // Next
            _CtrlButton(
              icon: Icons.skip_next,
              buttonSize: btnSize,
              size: iconSz,
              onPressed: _playNext,
            ),

            const Spacer(),

            // Volume
            _CtrlButton(
              icon: Icons.volume_up,
              buttonSize: btnSize,
              size: iconSz,
              onPressed: () => setState(
                  () => _showVolumeSlider = !_showVolumeSlider),
            ),

            const SizedBox(width: AppSpacing.md),

            // Seek -10s (VOD only)
            if (_type != ContentType.TV)
              _CtrlButton(
                icon: Icons.replay_10,
                buttonSize: btnSize,
                size: iconSz,
                onPressed: () {
                  final p = _media.position -
                      const Duration(seconds: 10);
                  _media.seek(
                      p < Duration.zero ? Duration.zero : p);
                },
              ),

            if (_type != ContentType.TV)
              const SizedBox(width: AppSpacing.sm),

            // Seek +10s (VOD only)
            if (_type != ContentType.TV)
              _CtrlButton(
                icon: Icons.forward_10,
                buttonSize: btnSize,
                size: iconSz,
                onPressed: () => _media.seek(_media.position +
                    const Duration(seconds: 10)),
              ),

            // Subtitle toggle (VOD only)
            if (_type != ContentType.TV) ...[
              const SizedBox(width: AppSpacing.sm),
              _CtrlButton(
                icon: _subtitlesEnabled
                    ? Icons.subtitles
                    : Icons.subtitles_off,
                buttonSize: btnSize,
                size: iconSz,
                color: _subtitlesEnabled ? AppColors.accent : Colors.white,
                onPressed: _toggleSubtitles,
              ),
            ],

            const SizedBox(width: AppSpacing.md),

            // Close / back to list
            _CtrlButton(
              icon: Icons.close,
              buttonSize: btnSize,
              size: iconSz,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Volume overlay ────────────────────────────────────────────────────────

  Widget _buildVolumeOverlay() {
    return Positioned(
      bottom: 80,
      right: AppSpacing.xl,
      child: Container(
        width: 52,
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.overlay,
          borderRadius: AppRadius.cardRadius,
        ),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ValueListenableBuilder<double>(
          valueListenable: _media.volumeNotifier,
          builder: (_, vol, __) => RotatedBox(
            quarterTurns: 3,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: Slider(
                value: vol,
                min: 0,
                max: 100,
                onChanged: _media.setVolume,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Error overlay ─────────────────────────────────────────────────────────

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              margin: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.15),
                borderRadius: AppRadius.cardRadius,
                border: Border.all(color: AppColors.error),
              ),
              child: Column(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 56),
                  const SizedBox(height: AppSpacing.md),
                  const Text('Error al reproducir',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error ?? 'Stream no disponible',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _retryPlayback,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reintentar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: Colors.white30),
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.md),
                        ),
                        child: const Text('Volver'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Next episode prompt ───────────────────────────────────────────────────

  Widget _buildNextEpPrompt() {
    return Positioned(
      bottom: AppSpacing.xxl,
      right: AppSpacing.xl,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: 0.92),
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Siguiente episodio en $_nextEpCountdown s',
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () {
                    _cancelNextEpCountdown();
                  },
                  child: const Text('Cancelar',
                      style: TextStyle(
                          color: AppColors.textSecondary)),
                ),
                const SizedBox(width: AppSpacing.sm),
                ElevatedButton.icon(
                  onPressed: () {
                    _nextEpTimer?.cancel();
                    _playNext();
                  },
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('Reproducir ahora'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentSeries,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Series long-press options ─────────────────────────────────────────────

  void _showSeriesOptions() {
    _cancelHide();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.fast_forward,
                  color: AppColors.textPrimary),
              title: const Text('Saltar intro (+90s)',
                  style: AppTextStyles.bodyLarge),
              onTap: () { Navigator.pop(context); _skipIntro(); },
            ),
            ListTile(
              leading: const Icon(Icons.skip_next,
                  color: AppColors.textPrimary),
              title: const Text('Siguiente episodio',
                  style: AppTextStyles.bodyLarge),
              onTap: () { Navigator.pop(context); _playNext(); },
            ),
            ListTile(
              leading: const Icon(Icons.skip_previous,
                  color: AppColors.textPrimary),
              title: const Text('Episodio anterior',
                  style: AppTextStyles.bodyLarge),
              onTap: () { Navigator.pop(context); _playPrev(); },
            ),
          ],
        ),
      ),
    ).whenComplete(_scheduleHide);
  }

  // ── Utils ─────────────────────────────────────────────────────────────────

  static String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CtrlButton  — consistent control button for the overlay
// ─────────────────────────────────────────────────────────────────────────────

class _CtrlButton extends StatelessWidget {
  final IconData   icon;
  final double     size;
  final bool       large;
  final Color      color;
  final String?    label;
  final double?    buttonSize;
  final VoidCallback onPressed;

  const _CtrlButton({
    required this.icon,
    required this.onPressed,
    this.size       = 24,
    this.large      = false,
    this.color      = Colors.white,
    this.label,
    this.buttonSize,
  });

  @override
  Widget build(BuildContext context) {
    final sz = buttonSize ?? (large ? 64.0 : 44.0);
    final btn = Container(
      width:  sz,
      height: sz,
      decoration: const BoxDecoration(
        color: Colors.black38,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size),
    );

    return GestureDetector(
      onTap: onPressed,
      child: label != null
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              btn,
              const SizedBox(height: 4),
              Text(label!,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 10)),
            ])
          : btn,
    );
  }
}
