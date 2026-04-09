import 'content_type.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WatchProgress — persisted per-content playback state
// ─────────────────────────────────────────────────────────────────────────────

class WatchProgress {
  final String      contentId;
  final ContentType contentType;
  final Duration    position;
  final Duration?   duration;
  final DateTime    lastWatched;
  final bool        isCompleted;

  // Series only — used to look up content for "Continuar viendo"
  final String? seriesId;
  final int?    seasonNumber;
  final int?    episodeNumber;

  const WatchProgress({
    required this.contentId,
    required this.contentType,
    required this.position,
    required this.lastWatched,
    required this.isCompleted,
    this.duration,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
  });

  /// Progress fraction 0.0–1.0.
  double get progressFraction {
    final dur = duration;
    if (dur == null || dur.inMilliseconds == 0) return 0;
    return (position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
  }

  WatchProgress copyWith({bool? isCompleted}) => WatchProgress(
        contentId:     contentId,
        contentType:   contentType,
        position:      position,
        duration:      duration,
        lastWatched:   lastWatched,
        isCompleted:   isCompleted ?? this.isCompleted,
        seriesId:      seriesId,
        seasonNumber:  seasonNumber,
        episodeNumber: episodeNumber,
      );

  Map<String, dynamic> toJson() => {
        'contentId':     contentId,
        'contentType':   contentType.name,
        'positionMs':    position.inMilliseconds,
        'durationMs':    duration?.inMilliseconds,
        'lastWatched':   lastWatched.toIso8601String(),
        'isCompleted':   isCompleted,
        'seriesId':      seriesId,
        'seasonNumber':  seasonNumber,
        'episodeNumber': episodeNumber,
      };

  factory WatchProgress.fromJson(Map<String, dynamic> j) => WatchProgress(
        contentId:     j['contentId']   as String,
        contentType:   ContentType.values.byName(j['contentType'] as String),
        position:      Duration(milliseconds: j['positionMs'] as int),
        duration:      j['durationMs'] != null
            ? Duration(milliseconds: j['durationMs'] as int)
            : null,
        lastWatched:   DateTime.parse(j['lastWatched'] as String),
        isCompleted:   j['isCompleted'] as bool? ?? false,
        seriesId:      j['seriesId']     as String?,
        seasonNumber:  j['seasonNumber'] as int?,
        episodeNumber: j['episodeNumber'] as int?,
      );
}
