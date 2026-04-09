import 'package:flutter/foundation.dart';
import 'content_type.dart';

// ─────────────────────────────────────────────
// Episode
// ─────────────────────────────────────────────
@immutable
class Episode {
  final int episodeNumber;
  final String title;
  final String url;
  final Duration? duration;
  final bool watched;

  const Episode({
    required this.episodeNumber,
    required this.title,
    required this.url,
    this.duration,
    this.watched = false,
  });

  Episode copyWith({
    int? episodeNumber,
    String? title,
    String? url,
    Duration? duration,
    bool? watched,
  }) {
    return Episode(
      episodeNumber: episodeNumber ?? this.episodeNumber,
      title: title ?? this.title,
      url: url ?? this.url,
      duration: duration ?? this.duration,
      watched: watched ?? this.watched,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Episode &&
          other.episodeNumber == episodeNumber &&
          other.url == url;

  @override
  int get hashCode => Object.hash(episodeNumber, url);

  @override
  String toString() => 'Episode($episodeNumber: $title)';
}

// ─────────────────────────────────────────────
// Season
// ─────────────────────────────────────────────
@immutable
class Season {
  final int seasonNumber;
  final List<Episode> episodes;

  const Season({
    required this.seasonNumber,
    required this.episodes,
  });

  int get watchedCount => episodes.where((e) => e.watched).length;
  bool get isCompleted => episodes.isNotEmpty && watchedCount == episodes.length;

  Season copyWith({
    int? seasonNumber,
    List<Episode>? episodes,
  }) {
    return Season(
      seasonNumber: seasonNumber ?? this.seasonNumber,
      episodes: episodes ?? this.episodes,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Season && other.seasonNumber == seasonNumber;

  @override
  int get hashCode => seasonNumber.hashCode;

  @override
  String toString() =>
      'Season($seasonNumber, ${episodes.length} episodes)';
}

// ─────────────────────────────────────────────
// Series
// ─────────────────────────────────────────────
@immutable
class Series {
  final String id;
  final String name;
  final String? poster;
  final String? description;
  final String category;
  final int? year;
  final double? rating;
  final List<Season> seasons;
  final ContentType contentType;

  const Series({
    required this.id,
    required this.name,
    this.poster,
    this.description,
    required this.category,
    this.year,
    this.rating,
    required this.seasons,
    this.contentType = ContentType.SERIES,
  });

  int get totalEpisodes =>
      seasons.fold(0, (sum, s) => sum + s.episodes.length);

  int get watchedEpisodes =>
      seasons.fold(0, (sum, s) => sum + s.watchedCount);

  double get watchProgress =>
      totalEpisodes == 0 ? 0 : watchedEpisodes / totalEpisodes;

  Series copyWith({
    String? id,
    String? name,
    String? poster,
    String? description,
    String? category,
    int? year,
    double? rating,
    List<Season>? seasons,
    ContentType? contentType,
  }) {
    return Series(
      id: id ?? this.id,
      name: name ?? this.name,
      poster: poster ?? this.poster,
      description: description ?? this.description,
      category: category ?? this.category,
      year: year ?? this.year,
      rating: rating ?? this.rating,
      seasons: seasons ?? this.seasons,
      contentType: contentType ?? this.contentType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Series && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Series(id: $id, name: $name, seasons: ${seasons.length})';
}
