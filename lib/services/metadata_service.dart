import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

class MetadataService {
  MetadataService._();
  static final MetadataService instance = MetadataService._();

  // Public TMDB API Key for demo purposes (usually would be env var)
  static const _tmdbApiKey = '15d12a66d3a4369be3fb65e44d47ad9c'; 
  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _imgBase = 'https://image.tmdb.org/t/p/w500';

  final Map<String, Map<String, dynamic>> _cache = {};

  Future<Map<String, dynamic>?> fetchMetadata(String title, {bool isMovie = true}) async {
    final cacheKey = '${isMovie ? 'm' : 's'}_$title';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    try {
      final query = Uri.encodeComponent(title);
      final type = isMovie ? 'movie' : 'tv';
      final url = '$_baseUrl/search/$type?api_key=$_tmdbApiKey&query=$query&language=es-ES';

      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;

      final data = json.decode(resp.body);
      final results = data['results'] as List;
      if (results.isEmpty) return null;

      final bestMatch = results.first;
      final result = {
        'poster': bestMatch['poster_path'] != null ? '$_imgBase${bestMatch['poster_path']}' : null,
        'description': bestMatch['overview'],
        'rating': (bestMatch['vote_average'] as num?)?.toDouble(),
        'year': _parseYear(bestMatch[isMovie ? 'release_date' : 'first_air_date']),
      };

      _cache[cacheKey] = result;
      return result;
    } catch (e) {
      dev.log('[MetadataService] Error fetching metadata for $title: $e', name: 'MetadataService');
      return null;
    }
  }

  int? _parseYear(dynamic date) {
    if (date == null || date.toString().isEmpty) return null;
    return int.tryParse(date.toString().substring(0, 4));
  }
}
