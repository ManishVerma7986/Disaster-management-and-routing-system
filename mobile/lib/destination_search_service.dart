import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class DestinationSuggestion {
  const DestinationSuggestion({required this.name, required this.displayName, required this.latitude, required this.longitude});

  final String name;
  final String displayName;
  final double latitude;
  final double longitude;

  factory DestinationSuggestion.fromJson(Map<String, dynamic> json) {
    final latitude = json['lat'];
    final longitude = json['lon'];
    return DestinationSuggestion(
      name: (json['name'] as String?)?.trim().isNotEmpty == true ? json['name'] as String : json['formatted_address'] as String? ?? 'Selected location',
      displayName: json['formatted_address'] as String? ?? json['display_name'] as String? ?? 'Selected location',
      latitude: latitude is num ? latitude.toDouble() : double.parse(latitude as String),
      longitude: longitude is num ? longitude.toDouble() : double.parse(longitude as String),
    );
  }

}

class DestinationSearchService {
  DestinationSearchService({required this.baseUrl, http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  Timer? _debounce;

  Future<List<DestinationSuggestion>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.length < 3) return const [];
    final uri = Uri.parse('$baseUrl/places/search').replace(queryParameters: {'q': trimmed, 'limit': '5'});
    final response = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Destination search is temporarily unavailable.');
    final values = jsonDecode(response.body);
    if (values is! List) return const [];
    return values.whereType<Map<String, dynamic>>().map(DestinationSuggestion.fromJson).toList();
  }

  Future<DestinationSuggestion> reverse(double latitude, double longitude) async {
    final uri = Uri.parse('$baseUrl/places/reverse').replace(queryParameters: {'lat': '$latitude', 'lon': '$longitude'});
    final response = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Address lookup is temporarily unavailable.');
    return DestinationSuggestion.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<Map<String, dynamic>>> nearby({
    required double latitude,
    required double longitude,
    String categories = 'healthcare.hospital,service.police,service.fire_station',
    int radiusMeters = 5000,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$baseUrl/places/nearby').replace(queryParameters: {
      'lat': '$latitude',
      'lon': '$longitude',
      'categories': categories,
      'radius_m': '$radiusMeters',
      'limit': '$limit',
    });
    final response = await _client.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 10));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('Nearby places lookup is temporarily unavailable.');
    final values = jsonDecode(response.body);
    if (values is! List) return const [];
    return values.whereType<Map<String, dynamic>>().toList();
  }

  Future<List<DestinationSuggestion>> debouncedSearch(String query) {
    _debounce?.cancel();
    final completer = Completer<List<DestinationSuggestion>>();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        completer.complete(await search(query));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void dispose() => _debounce?.cancel();
}
