import 'package:flutter/foundation.dart';
import 'channel.dart';
import 'series.dart';
import 'movie.dart';

@immutable
class Playlist {
  final String id;
  final String name;
  final String url;
  final List<Channel> channels;
  final List<Series> series;
  final List<Movie> movies;
  final DateTime lastUpdated;
  final bool isActive;

  const Playlist({
    required this.id,
    required this.name,
    required this.url,
    this.channels = const [],
    this.series = const [],
    this.movies = const [],
    required this.lastUpdated,
    this.isActive = true,
  });

  int get totalItems => channels.length + series.length + movies.length;

  bool get isEmpty => totalItems == 0;

  /// Groups channels by their `group` field.
  Map<String, List<Channel>> get channelsByGroup {
    final map = <String, List<Channel>>{};
    for (final ch in channels) {
      map.putIfAbsent(ch.group, () => []).add(ch);
    }
    return map;
  }

  /// Groups series by category.
  Map<String, List<Series>> get seriesByCategory {
    final map = <String, List<Series>>{};
    for (final s in series) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  /// Groups movies by category.
  Map<String, List<Movie>> get moviesByCategory {
    final map = <String, List<Movie>>{};
    for (final m in movies) {
      map.putIfAbsent(m.category, () => []).add(m);
    }
    return map;
  }

  Playlist copyWith({
    String? id,
    String? name,
    String? url,
    List<Channel>? channels,
    List<Series>? series,
    List<Movie>? movies,
    DateTime? lastUpdated,
    bool? isActive,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      channels: channels ?? this.channels,
      series: series ?? this.series,
      movies: movies ?? this.movies,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Playlist && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Playlist(id: $id, name: $name, '
      'channels: ${channels.length}, series: ${series.length}, movies: ${movies.length})';
}
