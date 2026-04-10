import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/models.dart';

const _uuid = Uuid();

// ── Series detection ──────────────────────────────────────────────────────────

/// Primary: "Breaking Bad (S05E14)"
final _seriesRe = RegExp(
  r"^([\w][\w\s\-\.\:\']+?)\s*\(S(\d{1,3})E(\d{1,3})\)",
  caseSensitive: false,
);

/// Secondary: "Breaking Bad S05E14", "Breaking Bad - S05E14"
final _seriesRe2 = RegExp(
  r'^(.+?)\s[-–]?\s*[Ss](\d{1,3})\s*[Ee](\d{1,3})\b',
  caseSensitive: false,
);

/// tvg-type values that indicate series content (lowercase).
const _seriesTypes = <String>{
  'series', 'serie', 'tvshow', 'tv_show', 'tv-show',
};

/// tvg-type values that indicate movie/VOD content (lowercase).
const _movieTypes = <String>{
  'movie', 'movies', 'vod', 'film', 'films', 'pelicula', 'película',
};

/// group-title substrings that indicate series content (lowercase).
const _seriesGroupKw = <String>[
  'serie', 'episod', 'temporada', 'season', 'tvshow', 'tv show', 'capitulo',
];

/// URL path segments that indicate series content (lowercase).
const _seriesUrlKw = <String>[
  '/series/', '/serie/', '/episodios/', '/episodes/', '/tvshows/', '/shows/',
];

// ── Movie detection ───────────────────────────────────────────────────────────

/// Exact group-title values that map to movies (lowercase).
const _movieGroupsExact = <String>{
  'movies', 'películas', 'peliculas', 'film', 'films',
  'movie', 'vod movies', 'vod - movies', 'vod', 'pelis', 'peli',
  'videoteca', 'largometrajes', 'cine',
};

/// group-title substrings that indicate movie content (lowercase).
/// Long keywords use substring matching; short/ambiguous ones need word boundaries.
const _movieGroupKwSubstring = <String>[
  'movie', 'pelicula', 'película', 'film',
];

/// Short keywords that require word-boundary matching to avoid false positives
/// (e.g. "vodafone" must NOT match "vod", "cinemax" must NOT match "cine").
const _movieGroupKwWord = <String>[
  'vod', 'cine', 'peli',
];

/// URL path segments that indicate movie content (lowercase).
const _movieUrlKw = <String>[
  '/movies/', '/movie/', '/peliculas/', '/films/', '/cine/', '/vod/',
];

/// URL file extensions that indicate a live stream (high-confidence signal).
/// These override group-title keyword checks to prevent misclassification.
const _liveStreamExts = <String>['.m3u8', '.ts', '.m3u'];

/// URL path segments that indicate a live stream even without a file extension.
/// Covers xtream-codes style URLs: /live/user/pass/channel_id
const _liveStreamPathKw = <String>['/live/', '/iptv/', '/stream/'];

/// URL file extensions that indicate a VOD file (high-confidence signal).
const _vodFileExts = <String>['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv'];

/// Returns true if [urlLower] ends with one of [exts] or has it before a '?'
bool _urlHasExt(String urlLower, List<String> exts) {
  // Strip query string for extension check
  final path = urlLower.contains('?')
      ? urlLower.substring(0, urlLower.indexOf('?'))
      : urlLower;
  return exts.any((e) => path.endsWith(e));
}

// ── Classification result ────────────────────────────────────────────────────

enum _Kind { tv, series, movie }

/// Returns true if [groupLower] contains a movie keyword.
/// Uses substring matching for long keywords and word-boundary matching for
/// short ones to avoid false positives (e.g. "vodafone" ≠ "vod").
bool _groupHasMovieKeyword(String groupLower) {
  if (_movieGroupKwSubstring.any((kw) => groupLower.contains(kw))) return true;
  // Word boundary: keyword must be preceded/followed by space, |, -, _, /, \ or string edge
  final pattern = RegExp(
    r'(?:^|[\s|\-_/\\])(' + _movieGroupKwWord.join('|') + r')(?:$|[\s|\-_/\\])',
  );
  return pattern.hasMatch(groupLower);
}

// ─────────────────────────────────────────────────────────────────────────────
// M3UParser
// ─────────────────────────────────────────────────────────────────────────────

class M3UParser {
  M3UParser._();

  // ── Public API ──────────────────────────────────────────────────────────────

  static Future<Map<String, List<dynamic>>> loadPlaylistFromURL(
      String url) async {
    final content = await fetchM3UContent(url);
    return parseM3U(content);
  }

  static Future<String> fetchM3UContent(String url) async {
    dev.log('[M3UParser] Fetching: $url', name: 'M3UParser');
    try {
      final response = await http
          .get(Uri.parse(url), headers: {
            'Accept': '*/*',
            'User-Agent': 'Mozilla/5.0',
          })
          .timeout(const Duration(seconds: 180));

      if (response.statusCode != 200) {
        throw M3UFetchException(
          'HTTP ${response.statusCode} for $url',
          statusCode: response.statusCode,
        );
      }

      dev.log(
        '[M3UParser] Downloaded ${response.contentLength ?? response.bodyBytes.length} bytes',
        name: 'M3UParser',
      );
      return response.body;
    } on M3UFetchException {
      rethrow;
    } catch (e) {
      throw M3UFetchException('Failed to fetch M3U: $e');
    }
  }

  /// Parses raw M3U [content] into three typed lists.
  ///
  /// Classification priority (first match wins):
  ///   1. `tvg-type="series"` → series
  ///   2. `tvg-type="movie"` / `tvg-type="vod"` → movie
  ///   3. Name matches `(S01E01)` or `S01E01` pattern → series
  ///   4. URL has live-stream extension (.m3u8/.ts/.m3u) → TV
  ///   4b. URL has live-stream path segment (/live/ /iptv/ /stream/) → TV
  ///   5. URL has VOD extension (.mp4/.mkv/.avi…) → series/movie by group+URL
  ///      (keyword/substring movie detection ONLY inside this block)
  ///   6. group-title contains series keywords → series
  ///   7. URL path contains series segments → series
  ///   8. URL path contains movie segments (/movie/ /movies/ /vod/) → movie
  ///   9. group-title EXACT movie label ("movies","peliculas","vod"…) → movie
  ///  10. Everything else → live TV
  static Future<Map<String, List<dynamic>>> parseM3U(String content) async {
    final lines = content.split('\n');

    if (lines.isEmpty || !lines.first.trim().startsWith('#EXTM3U')) {
      dev.log('[M3UParser] Warning: missing #EXTM3U header', name: 'M3UParser');
    }

    final channels  = <Channel>[];
    final movies    = <Movie>[];
    final seriesMap = <String, Map<int, List<Episode>>>{};
    final seriesMeta    = <String, _SeriesMeta>{};
    final seriesEpCtr   = <String, int>{}; // auto-counter for entries with no S/E

    int tvCount = 0, seriesCount = 0, movieCount = 0, skipped = 0;

    // Debug samples: first 5 of each type
    final _dbgTV     = <String>[];
    final _dbgSeries = <String>[];
    final _dbgMovies = <String>[];

    for (int i = 0; i < lines.length - 1; i++) {
      final rawExtinf = lines[i].trim();
      if (!rawExtinf.startsWith('#EXTINF')) continue;

      // Find the next non-comment, non-empty URL line
      String? streamUrl;
      for (int j = i + 1; j < lines.length; j++) {
        final candidate = lines[j].trim();
        if (candidate.isNotEmpty && !candidate.startsWith('#')) {
          streamUrl = candidate;
          i = j;
          break;
        }
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        skipped++;
        continue;
      }

      final attrs   = _parseAttributes(rawExtinf);
      final name    = attrs['name'] ?? 'Sin nombre';
      final group   = attrs['group-title'] ?? '';
      final logo    = attrs['tvg-logo'];
      final tvgId   = attrs['tvg-id'];
      final tvgName = attrs['tvg-name'];
      final tvgType = (attrs['tvg-type'] ?? '').toLowerCase();

      final groupLower = group.toLowerCase();
      final urlLower   = streamUrl.toLowerCase();

      final kind = _classify(name, tvgType, groupLower, urlLower);

      switch (kind) {
        case _Kind.series:
          final (sName, sNum, eNum) =
              _extractSeriesInfo(name, group, seriesEpCtr);

          seriesMap
              .putIfAbsent(sName, () => {})
              .putIfAbsent(sNum, () => [])
              .add(Episode(
                episodeNumber: eNum,
                title: tvgName ?? name,
                url: streamUrl,
              ));

          seriesMeta.putIfAbsent(
              sName,
              () => _SeriesMeta(
                    poster: logo,
                    category: _deriveSeriesCategory(group, sName),
                  ));
          seriesCount++;
          if (_dbgSeries.length < 5) {
            _dbgSeries.add('  [SERIE ] group="$group" tvg-type="$tvgType" name="$name"');
          }

        case _Kind.movie:
          movies.add(Movie(
            id: _uuid.v4(),
            title: tvgName ?? name,
            poster: logo,
            category: group.isEmpty ? 'Películas' : group,
            url: streamUrl,
          ));
          movieCount++;
          if (_dbgMovies.length < 5) {
            _dbgMovies.add('  [PELI  ] group="$group" tvg-type="$tvgType" name="$name"');
          }

        case _Kind.tv:
          channels.add(Channel(
            id: _uuid.v4(),
            name: tvgName ?? name,
            logo: logo,
            url: streamUrl,
            tvgId: tvgId,
            tvgName: tvgName,
            group: group.isEmpty ? 'Sin categoría' : group,
          ));
          tvCount++;
          if (_dbgTV.length < 5) {
            _dbgTV.add('  [CANAL ] group="$group" tvg-type="$tvgType" name="$name"');
          }
      }
    }

    // ── Build Series objects ───────────────────────────────────────────────────
    final seriesList = seriesMap.entries.map((entry) {
      final sName = entry.key;
      final meta  = seriesMeta[sName];
      final seasons = entry.value.entries
          .map((s) {
            final sortedEps = s.value
              ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
            return Season(seasonNumber: s.key, episodes: sortedEps);
          })
          .toList()
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));

      return Series(
        id: _uuid.v4(),
        name: sName,
        poster: meta?.poster,
        category: meta?.category ?? 'Series',
        seasons: seasons,
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final summary =
        'Canales: $tvCount | Series: ${seriesList.length} ($seriesCount eps) '
        '| Películas: $movieCount | Omitidos: $skipped';

    dev.log('[M3UParser] $summary', name: 'M3UParser');
    // ignore: avoid_print
    print('[M3UParser] $summary');
    // ignore: avoid_print
    print('Canales detectados: $tvCount');
    // ignore: avoid_print
    print('Series detectadas: ${seriesList.length} ($seriesCount episodios)');
    // ignore: avoid_print
    print('Películas detectadas: $movieCount');

    // Debug samples — shows the first 5 entries of each type so you can verify
    // the group-title / tvg-type / name that triggered the classification.
    if (_dbgTV.isNotEmpty) {
      // ignore: avoid_print
      print('[M3UParser] Muestra canales:');
      for (final s in _dbgTV) { print(s); } // ignore: avoid_print
    }
    if (_dbgSeries.isNotEmpty) {
      // ignore: avoid_print
      print('[M3UParser] Muestra series:');
      for (final s in _dbgSeries) { print(s); } // ignore: avoid_print
    }
    if (_dbgMovies.isNotEmpty) {
      // ignore: avoid_print
      print('[M3UParser] Muestra películas:');
      for (final s in _dbgMovies) { print(s); } // ignore: avoid_print
    }
    if (_dbgSeries.isEmpty && _dbgMovies.isEmpty) {
      // ignore: avoid_print
      print('[M3UParser] ⚠ NINGUNA serie/película detectada.');
      // ignore: avoid_print
      print('[M3UParser] Revisa el group-title y tvg-type de tu M3U.');
      if (_dbgTV.isNotEmpty) {
        // ignore: avoid_print
        print('[M3UParser] Primeras entradas clasificadas como CANAL:');
        for (final s in _dbgTV) { print(s); } // ignore: avoid_print
      }
    }

    return {
      'TV':     channels,
      'SERIES': seriesList,
      'MOVIES': movies,
    };
  }

  // ── Private: category derivation ─────────────────────────────────────────────

  /// Derives a genre/category string from the M3U `group-title` attribute.
  ///
  /// Many providers set `group-title` to the series name (not the genre), so we
  /// must distinguish "identifier" groups from "genre" groups:
  ///
  /// - Empty → `'Series'`
  /// - Equals the series name (case-insensitive, trimmed) → `'Series'`
  /// - Contains `|` separators (e.g. `"EN | SERIES | Acción"`) → strip language
  ///   codes and meta-tokens, return the best genre token or `'Series'`
  /// - Otherwise → the trimmed group-title as-is (it's a genre label)
  static String _deriveSeriesCategory(String group, String seriesName) {
    final g     = group.trim();
    final sLow  = seriesName.trim().toLowerCase();

    // 1. Empty → generic bucket
    if (g.isEmpty) return 'Series';

    // 2. Exact series-name match (case-insensitive) → not a genre
    if (g.toLowerCase() == sLow) return 'Series';

    // 3. Pipe-separated format: e.g. "ES | SERIES | Drama" or "Series | Acción"
    if (g.contains('|')) {
      final parts = g
          .split('|')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      final genre = parts.lastWhere(
        (p) {
          final low = p.toLowerCase();
          // Skip: equals the series name
          if (low == sLow) return false;
          // Skip: generic "series/serie" labels
          if (low == 'series' || low == 'serie' || low == 'tvshow') return false;
          // Skip: language/country codes (1–3 uppercase letters)
          if (RegExp(r'^[A-Z]{1,3}$').hasMatch(p)) return false;
          return true;
        },
        orElse: () => '',
      );

      return genre.isNotEmpty ? genre : 'Series';
    }

    // 4. Group-title contains the series name as a substring → not a genre
    if (g.toLowerCase().contains(sLow) && sLow.length > 4) return 'Series';

    return g;
  }

  // ── Private: classification ──────────────────────────────────────────────────

  static _Kind _classify(
      String name, String tvgType, String groupLower, String urlLower) {
    // 1. Explicit tvg-type (highest confidence — trust the provider)
    if (_seriesTypes.contains(tvgType)) return _Kind.series;
    if (_movieTypes.contains(tvgType)) return _Kind.movie;

    // 2. Series name pattern (S01E01 / (S01E01))
    if (_seriesRe.hasMatch(name) || _seriesRe2.hasMatch(name)) {
      return _Kind.series;
    }

    // 3. Live stream URL → TV regardless of group-title.
    //    a) extension (.m3u8 / .ts / .m3u) — highest confidence
    //    b) path segment (/live/ /iptv/ /stream/) — xtream-codes style:
    //       http://host:8080/live/user/pass/channel_id
    if (_urlHasExt(urlLower, _liveStreamExts)) return _Kind.tv;
    if (_liveStreamPathKw.any((kw) => urlLower.contains(kw))) return _Kind.tv;

    // 4. VOD file extension → narrow down to series or movie.
    //    Only here (where the URL already proves it's a file) do we trust
    //    group-title keyword/substring matching for movies — avoids false
    //    positives on live-TV groups like "BeIN Movies HD" or "AR-MOVIES".
    if (_urlHasExt(urlLower, _vodFileExts)) {
      // Series indicators take priority within VOD files
      if (_seriesGroupKw.any((kw) => groupLower.contains(kw))) {
        return _Kind.series;
      }
      if (_seriesUrlKw.any((kw) => urlLower.contains(kw))) {
        return _Kind.series;
      }
      // Keyword/substring movie detection is safe here: we know it's a file
      if (_groupHasMovieKeyword(groupLower)) return _Kind.movie;
      return _Kind.movie;
    }

    // 5. Series group-title keywords (no clear URL extension)
    if (_seriesGroupKw.any((kw) => groupLower.contains(kw))) {
      return _Kind.series;
    }

    // 6. Series URL path segments
    if (_seriesUrlKw.any((kw) => urlLower.contains(kw))) {
      return _Kind.series;
    }

    // 7. Movie URL path segments — catches xtream-codes /movie/user/pass/ID
    if (_movieUrlKw.any((kw) => urlLower.contains(kw))) {
      return _Kind.movie;
    }

    // 8. Movie group-title EXACT match only (no keyword/substring).
    //    Substring matching is omitted here because groups like "BeIN Movies HD",
    //    "AR-MOVIES", "Action Movies" are live-TV channel groups, NOT VOD folders.
    //    Only unambiguous genre labels like "movies", "peliculas", "vod" qualify.
    if (_movieGroupsExact.contains(groupLower)) {
      return _Kind.movie;
    }

    return _Kind.tv;
  }

  // ── Private: S/E extraction ──────────────────────────────────────────────────

  /// Returns (seriesName, seasonNumber, episodeNumber).
  ///
  /// Tries both name regexes; falls back to group-title as series name
  /// and auto-increments episode number.
  static (String, int, int) _extractSeriesInfo(
      String name, String group, Map<String, int> epCtr) {
    // Primary: "ShowName (S01E01)"
    var m = _seriesRe.firstMatch(name.trim());
    if (m != null) {
      return (
        m.group(1)!.trim(),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }

    // Secondary: "ShowName S01E01", "ShowName - S01E01"
    m = _seriesRe2.firstMatch(name.trim());
    if (m != null) {
      return (
        m.group(1)!.trim(),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
      );
    }

    // No S/E in name — use group-title as series name, auto-number episodes
    final sName = group.isNotEmpty ? group : name;
    final ep    = (epCtr[sName] ?? 0) + 1;
    epCtr[sName] = ep;
    return (sName, 1, ep);
  }

  // ── Private: attribute parsing ───────────────────────────────────────────────

  static Map<String, String> _parseAttributes(String extinf) {
    final result = <String, String>{};

    final attrRe = RegExp(r'([\w-]+)="([^"]*)"');
    for (final m in attrRe.allMatches(extinf)) {
      final key   = m.group(1)!.toLowerCase();
      final value = m.group(2)!.trim();
      if (value.isNotEmpty) result[key] = value;
    }

    // Display name is everything after the last comma
    final commaIndex = extinf.lastIndexOf(',');
    if (commaIndex != -1 && commaIndex < extinf.length - 1) {
      result['name'] = extinf.substring(commaIndex + 1).trim();
    }

    return result;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SeriesMeta {
  final String? poster;
  final String  category;
  _SeriesMeta({this.poster, required this.category});
}

class M3UFetchException implements Exception {
  final String message;
  final int? statusCode;
  const M3UFetchException(this.message, {this.statusCode});

  @override
  String toString() => 'M3UFetchException: $message';
}
