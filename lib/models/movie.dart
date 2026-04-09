import 'package:flutter/foundation.dart';
import 'content_type.dart';

@immutable
class Movie {
  final String id;
  final String title;
  final String? poster;
  final String? description;
  final String category;
  final int? year;
  final Duration? duration;
  final double? rating;
  final String url;
  final bool watched;
  final ContentType contentType;

  const Movie({
    required this.id,
    required this.title,
    this.poster,
    this.description,
    required this.category,
    this.year,
    this.duration,
    this.rating,
    required this.url,
    this.watched = false,
    this.contentType = ContentType.MOVIES,
  });

  /// Formatted duration string, e.g. "1h 45m"
  String? get durationLabel {
    if (duration == null) return null;
    final h = duration!.inHours;
    final m = duration!.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  Movie copyWith({
    String? id,
    String? title,
    String? poster,
    String? description,
    String? category,
    int? year,
    Duration? duration,
    double? rating,
    String? url,
    bool? watched,
    ContentType? contentType,
  }) {
    return Movie(
      id: id ?? this.id,
      title: title ?? this.title,
      poster: poster ?? this.poster,
      description: description ?? this.description,
      category: category ?? this.category,
      year: year ?? this.year,
      duration: duration ?? this.duration,
      rating: rating ?? this.rating,
      url: url ?? this.url,
      watched: watched ?? this.watched,
      contentType: contentType ?? this.contentType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Movie && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Movie(id: $id, title: $title, year: $year)';
}
