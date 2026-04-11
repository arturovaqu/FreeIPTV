import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../models/models.dart';
import '../utils/config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// XtreamService
// ─────────────────────────────────────────────────────────────────────────────

class XtreamService {
  final String baseUrl;
  final String username;
  final String password;

  XtreamService({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  String get _apiUrl => '$baseUrl/player_api.php?username=$username&password=$password';

  /// Authenticate and fetch basic account info.
  Future<Map<String, dynamic>> login() async {
    final url = _apiUrl;
    dev.log('[XtreamService] Login attempt: $baseUrl', name: 'XtreamService');
    
    final resp = await http.get(Uri.parse(url)).timeout(AppConfig.fetchTimeout);
    if (resp.statusCode != 200) throw Exception('Server error: ${resp.statusCode}');
    
    final data = json.decode(resp.body);
    if (data['user_info']['auth'] == 0) throw Exception('Invalid credentials');
    
    return data;
  }

  // -- Categories -------------------------------------------------------------

  Future<List<Map<String, dynamic>>> getCategories(String action) async {
    final url = '$_apiUrl&action=$action';
    final resp = await http.get(Uri.parse(url)).timeout(AppConfig.fetchTimeout);
    final data = json.decode(resp.body) as List;
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // -- Content ----------------------------------------------------------------

  Future<List<Channel>> getLiveStreams() async {
    final url = '$_apiUrl&action=get_live_streams';
    final resp = await http.get(Uri.parse(url)).timeout(AppConfig.fetchTimeout);
    final data = json.decode(resp.body) as List;
    
    return data.map((item) {
      final id = item['stream_id'].toString();
      return Channel(
        id: id,
        name: item['name'] ?? 'Unknown',
        logo: item['stream_icon'] ?? '',
        group: item['category_id']?.toString() ?? 'Default',
        url: '$baseUrl/live/$username/$password/$id.ts',
      );
    }).toList();
  }

  Future<List<Movie>> getVodStreams() async {
    final url = '$_apiUrl&action=get_vod_streams';
    final resp = await http.get(Uri.parse(url)).timeout(AppConfig.fetchTimeout);
    final data = json.decode(resp.body) as List;
    
    return data.map((item) {
      final id = item['stream_id'].toString();
      final ext = item['container_extension'] ?? 'mkv';
      return Movie(
        id: id,
        title: item['name'] ?? 'Unknown',
        poster: item['stream_icon'] ?? '',
        category: item['category_id']?.toString() ?? 'Default',
        rating: double.tryParse(item['rating']?.toString() ?? ''),
        url: '$baseUrl/movie/$username/$password/$id.$ext',
      );
    }).toList();
  }

  Future<List<Series>> getSeries() async {
    final url = '$_apiUrl&action=get_series';
    final resp = await http.get(Uri.parse(url)).timeout(AppConfig.fetchTimeout);
    final data = json.decode(resp.body) as List;
    
    return data.map((item) {
      final id = item['series_id'].toString();
      return Series(
        id: id,
        name: item['name'] ?? 'Unknown',
        cover: item['last_modified'] ?? '', // API usually has 'cover' or 'last_modified'
        category: item['category_id']?.toString() ?? 'Default',
        rating: double.tryParse(item['rating']?.toString() ?? ''),
        seasons: [], // Requires separate call get_series_info
      );
    }).toList();
  }
}
