import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'content_type.dart';

@immutable
class Channel {
  final String id;
  final String name;
  final String? logo;
  final String url;
  final String? tvgId;
  final String? tvgName;
  final String group;
  final ContentType contentType;

  const Channel({
    required this.id,
    required this.name,
    this.logo,
    required this.url,
    this.tvgId,
    this.tvgName,
    this.group = 'Sin categoría',
    this.contentType = ContentType.TV,
  });

  /// Parses a single #EXTINF line + its URL from an M3U playlist.
  ///
  /// Example extinf:
  ///   #EXTINF:-1 tvg-id="CNN" tvg-name="CNN HD" tvg-logo="http://..." group-title="News",CNN HD
  factory Channel.fromM3ULine(String extinf, String url) {
    String? extract(String attr) {
      final re = RegExp('$attr="([^"]*)"', caseSensitive: false);
      return re.firstMatch(extinf)?.group(1);
    }

    // Name is the text after the last comma on the #EXTINF line
    final commaIndex = extinf.lastIndexOf(',');
    final name =
        commaIndex != -1 ? extinf.substring(commaIndex + 1).trim() : 'Canal';

    final group = extract('group-title') ?? 'Sin categoría';

    return Channel(
      id: const Uuid().v4(),
      name: name,
      logo: extract('tvg-logo'),
      url: url.trim(),
      tvgId: extract('tvg-id'),
      tvgName: extract('tvg-name'),
      group: group.isEmpty ? 'Sin categoría' : group,
    );
  }

  Channel copyWith({
    String? id,
    String? name,
    String? logo,
    String? url,
    String? tvgId,
    String? tvgName,
    String? group,
    ContentType? contentType,
  }) {
    return Channel(
      id: id ?? this.id,
      name: name ?? this.name,
      logo: logo ?? this.logo,
      url: url ?? this.url,
      tvgId: tvgId ?? this.tvgId,
      tvgName: tvgName ?? this.tvgName,
      group: group ?? this.group,
      contentType: contentType ?? this.contentType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Channel && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Channel(id: $id, name: $name, group: $group)';
}
