import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'offline_router.dart';
import 'destination_search_service.dart';

class ApiService {
  ApiService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  String? token;

  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _queuedReportsKey = 'queued_reports';

  String get baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      // Physical Android device: use PC's local IP address
      // For emulator: use adb reverse with 127.0.0.1
      print('📱 Using physical Android device: 10.239.3.66:8000');
      return 'http://10.239.3.66:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return 'http://127.0.0.1:8000';
    }
    // Fallback for other platforms
    return 'http://127.0.0.1:8000';
  }

  String get platformLabel => kIsWeb ? 'web' : defaultTargetPlatform.name;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final url = '$baseUrl/auth/login';
    print('🔗 API LOGIN: $url');
    print('📱 Platform: $platformLabel');
    try {
      final response = await _client.post(Uri.parse(url),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}))
          .timeout(const Duration(seconds: 10), onTimeout: () {
            print('⏱️ LOGIN TIMEOUT after 10 seconds');
            throw TimeoutException('Connection timed out after 10 seconds. Backend at $url not responding.');
          });
      print('✅ LOGIN Response: ${response.statusCode}');
      return _decode(response);
    } on SocketException catch (e) {
      print('❌ SOCKET ERROR: ${e.osError?.message} (errno: ${e.osError?.errorCode})');
      print('   Address: ${e.address}, Port: ${e.port}');
      rethrow;
    } on TimeoutException catch (e) {
      print('❌ TIMEOUT: $e');
      rethrow;
    } catch (e) {
      print('❌ LOGIN Error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> register(
      {required String name,
      required String email,
      required String password}) async {
    final response = await _client.post(Uri.parse('$baseUrl/auth/register'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'name': name, 'email': email, 'password': password}));
    return _decode(response);
  }

  Future<Map<String, dynamic>> createAdmin(
      {required String name,
      required String email,
      required String password,
      String role = 'ADMIN'}) async {
    final response = await _client.post(Uri.parse('$baseUrl/auth/create-admin'),
        headers: {'content-type': 'application/json', ..._authHeaders()},
        body: jsonEncode({'name': name, 'email': email, 'password': password, 'role': role}));
    return _decode(response);
  }

  Future<Map<String, dynamic>?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('access_token');
    if (token == null) return null;
    try {
      final response = await _client.get(Uri.parse('$baseUrl/auth/me'),
          headers: _authHeaders());
      return _decode(response);
    } catch (_) {
      await logout();
      return null;
    }
  }

  Future<List<dynamic>> myReports() async {
    final response = await _client.get(Uri.parse('$baseUrl/reports/mine'),
        headers: _authHeaders());
    return _decodeList(response);
  }

  Future<void> logout() async {
    token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
  }

  Future<Map<String, dynamic>> route(
      String source, String destination, String mode) async {
    try {
      print('🔗 API ROUTE: $baseUrl/route');
      print('📍 Source: $source, Destination: $destination, Mode: $mode');
      
      final response = await _client
          .post(Uri.parse('$baseUrl/route'),
              headers: {'content-type': 'application/json', ..._authHeaders()},
              body: jsonEncode(
                  {'source': source, 'destination': destination, 'mode': mode}))
          .timeout(const Duration(seconds: 15));
      
      print('✅ ROUTE Response: ${response.statusCode}');
      final value = _decode(response);
      print('📊 Route data: ${value.keys}');
      print('📊 Recommended data: ${value['recommended']?.keys}');
      print('📊 Distance: ${value['distance_km'] ?? value['recommended']?['distance_km']}');
      print('📊 ETA: ${value['eta_minutes'] ?? value['recommended']?['eta_minutes']}');
      print('📊 Geometry type: ${value['geometry']?.runtimeType ?? value['recommended']?['geometry']?.runtimeType}');
      print('📊 Geometry sample: ${value['geometry'] is List ? (value['geometry'] as List).take(3) : value['recommended']?['geometry'] is List ? (value['recommended']?['geometry'] as List).take(3) : 'N/A'}');
      
      // Ensure the route has required fields
      if (value['recommended'] is Map) {
        final recommended = value['recommended'] as Map<String, dynamic>;
        // Copy top-level metrics from recommended if not present at top level
        if (value['distance_km'] == null && recommended['distance_km'] != null) {
          value['distance_km'] = recommended['distance_km'];
        }
        if (value['eta_minutes'] == null && recommended['eta_minutes'] != null) {
          value['eta_minutes'] = recommended['eta_minutes'];
        }
        if (value['geometry'] == null && recommended['geometry'] != null) {
          value['geometry'] = recommended['geometry'];
        }
        if (value['risk'] == null && recommended['risk'] != null) {
          value['risk'] = recommended['risk'];
        }
        if (value['warnings'] == null && recommended['warnings'] != null) {
          value['warnings'] = recommended['warnings'];
        }
        if (value['reason'] == null && recommended['reason'] != null) {
          value['reason'] = recommended['reason'];
        }
      }
      
      print('📊 Final route geometry: ${value['geometry']?.runtimeType}');
      print('📊 Final route distance: ${value['distance_km']}');
      print('📊 Final route ETA: ${value['eta_minutes']}');
      
      await _cache('cached_route', value);
      return value;
    } on http.ClientException catch (e) {
      print('❌ ROUTE ClientException: $e');
      return _routeFromCache(source, destination, mode);
    } on TimeoutException catch (e) {
      print('❌ ROUTE TimeoutException: $e');
      return _routeFromCache(source, destination, mode);
    } on ApiException catch (exception) {
      print('❌ ROUTE ApiException: $exception');
      if (exception.statusCode != null && exception.statusCode! >= 500) {
        return _routeFromCache(source, destination, mode);
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _routeFromCache(
      String source, String destination, String mode) async {
    final cached = await cachedSync();
    if (cached == null || cached['roads'] is! List) {
      throw const ApiException(
          'The route service is unavailable and no road graph is cached.');
    }
    final local = OfflineRouter().find(
        roads: cached['roads'] as List<dynamic>,
        source: source,
        destination: destination,
        mode: mode);
    if (local == null) {
      throw const ApiException(
          'No offline route is available for these nodes.');
    }
    return {
      'recommended': local,
      'alternatives': <dynamic>[],
      'destination_risk': 'UNKNOWN',
      'data_status': 'OFFLINE CACHE'
    };
  }

  Future<Map<String, dynamic>> sync() async {
    final cached = await cachedSync();
    final queued = await _queuedReports();
    final headers = {'content-type': 'application/json', ..._authHeaders()};
    final response = await _client
        .post(Uri.parse('$baseUrl/sync'),
            headers: headers,
            body: jsonEncode({
              'base_version': cached?['version'],
              'pending_reports': queued
            }))
        .timeout(const Duration(seconds: 15));
    final value = _decode(response);
    await _cache('cached_sync', value);
    await _removeAcceptedReports(value['accepted_mutations']);
    return value;
  }

  Future<Map<String, dynamic>?> cachedSync() async {
    return _safeGetJsonMap('cached_sync');
  }

  Future<String?> cachedSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cached_sync_time');
  }

  Future<List<dynamic>> facilities(
      {double? lat, double? lon, String? kind}) async {
    final parameters = <String, String>{
      if (lat != null) 'lat': '$lat',
      if (lon != null) 'lon': '$lon',
      if (kind != null) 'kind': kind
    };
    print('🔗 API FACILITIES: $baseUrl/facilities');
    print('📍 Parameters: $parameters');
    try {
      final response = await _client.get(
          Uri.parse('$baseUrl/facilities').replace(queryParameters: parameters))
          .timeout(const Duration(seconds: 15));
      print('✅ FACILITIES Response: ${response.statusCode}');
      final result = _decodeList(response);
      print('📊 Facilities count: ${result.length}');
      return result;
    } on http.ClientException catch (e) {
      print('❌ FACILITIES ClientException: $e');
      return [];
    } on TimeoutException catch (e) {
      print('❌ FACILITIES TimeoutException: $e');
      return [];
    } on ApiException catch (exception) {
      print('❌ FACILITIES ApiException: $exception');
      return [];
    }
  }

  Future<List<dynamic>> nearbyWarnings(
      {required double lat, required double lon, double radiusKm = 5}) async {
    final uri = Uri.parse('$baseUrl/warnings/nearby').replace(queryParameters: {
      'lat': '$lat',
      'lon': '$lon',
      'radius_km': '$radiusKm'
    });
    final response = await _client.get(uri);
    return _decodeList(response);
  }

  Future<Map<String, dynamic>> weather(
      {required double lat, required double lon}) async {
    final uri = Uri.parse('$baseUrl/weather')
        .replace(queryParameters: {'lat': '$lat', 'lon': '$lon'});
    return _decode(await _client.get(uri));
  }

  Future<Map<String, dynamic>> traffic() async =>
      _decode(await _client.get(Uri.parse('$baseUrl/traffic')));

  Future<List<dynamic>> incidents() async =>
      _decodeList(await _client.get(Uri.parse('$baseUrl/incidents')));

  Stream<Map<String, dynamic>> incidentUpdates() async* {
    if (token == null) return;
    final websocketBaseUrl = baseUrl.replaceFirst(RegExp(r'^http'), 'ws');
    final uri = Uri.parse('$websocketBaseUrl/incidents/stream').replace(
        queryParameters: {'access_token': token!});
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready;
      await for (final message in channel.stream) {
        final decoded = jsonDecode(message as String);
        if (decoded is Map<String, dynamic>) yield decoded;
      }
    } finally {
      await channel.sink.close();
    }
  }

  Future<Map<String, dynamic>> nearestSafeFacility(
      {required double lat,
      required double lon,
      String kind = 'SHELTER'}) async {
    final uri = Uri.parse('$baseUrl/facilities/nearest-safe')
        .replace(queryParameters: {'lat': '$lat', 'lon': '$lon', 'kind': kind});
    return _decode(await _client.get(uri));
  }

  Future<List<DestinationSuggestion>> searchPlaces(String query,
      {int limit = 5}) async {
    final uri = Uri.parse('$baseUrl/places/search')
        .replace(queryParameters: {'q': query, 'limit': '$limit'});
    final response = await _client.get(uri);
    final values = _decodeList(response);
    return values
        .whereType<Map<String, dynamic>>()
        .map(DestinationSuggestion.fromJson)
        .toList();
  }

  Future<List<Map<String, dynamic>>> nearbyPlaces({
    required double lat,
    required double lon,
    String categories = 'healthcare.hospital,service.police,service.fire_station',
    int radiusMeters = 5000,
    int limit = 20,
  }) async {
    final uri = Uri.parse('$baseUrl/places/nearby').replace(queryParameters: {
      'lat': '$lat',
      'lon': '$lon',
      'categories': categories,
      'radius_m': '$radiusMeters',
      'limit': '$limit',
    });
    final response = await _client.get(uri);
    return _decodeList(response).whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> sos(double lat, double lon,
      {String message = 'Emergency assistance requested'}) async {
    final response = await _client.post(Uri.parse('$baseUrl/emergency/sos'),
        headers: {'content-type': 'application/json', ..._authHeaders()},
        body: jsonEncode({'lat': lat, 'lon': lon, 'message': message}));
    return _decode(response);
  }

  Future<void> registerPushToken(String pushToken, String platform) async {
    final response = await _client.post(
        Uri.parse('$baseUrl/devices/push-token'),
        headers: {'content-type': 'application/json', ..._authHeaders()},
        body: jsonEncode({'token': pushToken, 'platform': platform}));
    _decode(response);
  }

  Future<List<dynamic>> reports() async {
    final response = await _client.get(Uri.parse('$baseUrl/reports'),
        headers: _authHeaders());
    return _decodeList(response);
  }

  Future<List<dynamic>> closures() async {
    final response = await _client.get(Uri.parse('$baseUrl/closures'),
        headers: _authHeaders());
    return _decodeList(response);
  }

  Future<Map<String, dynamic>> createClosure(
      {required String roadId,
      required String reason,
      required String severity}) async {
    final response = await _client.post(Uri.parse('$baseUrl/closures'),
        headers: {'content-type': 'application/json', ..._authHeaders()},
        body: jsonEncode(
            {'road_id': roadId, 'reason': reason, 'severity': severity}));
    return _decode(response);
  }

  Future<Map<String, dynamic>> reviewReport(
      String reportId, bool verify) async {
    final response = await _client.put(
        Uri.parse('$baseUrl/reports/$reportId/${verify ? 'verify' : 'reject'}'),
        headers: _authHeaders());
    return _decode(response);
  }

  Future<Map<String, dynamic>> resolveIncident(String incidentId) async {
    final response = await _client.put(
        Uri.parse('$baseUrl/incidents/$incidentId/resolve'),
        headers: _authHeaders());
    return _decode(response);
  }

  Future<Map<String, dynamic>?> cachedRoute() async {
    return _safeGetJsonMap('cached_route');
  }

  Future<void> _cache(String key, Map<String, dynamic> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
    if (key == 'cached_route' || key == 'cached_sync') {
      await prefs.setString('${key}_time', DateTime.now().toIso8601String());
    }
  }

  Future<Map<String, dynamic>?> _safeGetJsonMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(key);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String?> cachedRouteTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('cached_route_time');
  }

  Future<Map<String, dynamic>> submitReport(
      {required String type,
      required double lat,
      required double lon,
      required String description,
      String? photoData}) async {
    final payload = {
      'problem_type': type,
      'lat': lat,
      'lon': lon,
      'description': description,
      if (photoData != null) 'photo_data': photoData
    };
    try {
      return await _submitReportNetwork(payload);
    } on http.ClientException {
      await _queueReport(payload);
      return {...payload, 'status': 'QUEUED_OFFLINE'};
    } on TimeoutException {
      await _queueReport(payload);
      return {...payload, 'status': 'QUEUED_OFFLINE'};
    } on ApiException catch (exception) {
      if (exception.statusCode != null && exception.statusCode! >= 500) {
        await _queueReport(payload);
        return {...payload, 'status': 'QUEUED_OFFLINE'};
      }
      rethrow;
    }
  }

  Future<int> queuedReportCount() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_queuedReportsKey);
    if (value == null) return 0;
    try {
      final decoded = jsonDecode(value);
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  Future<int> flushQueuedReports() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_queuedReportsKey);
    if (raw == null) return 0;
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return 0;
    }
    if (decoded is! List) return 0;
    final remaining = <dynamic>[];
    var sent = 0;
    for (final item in decoded.whereType<Map>()) {
      try {
        await _submitReportNetwork(Map<String, dynamic>.from(item));
        sent++;
      } catch (_) {
        remaining.add(item);
      }
    }
    if (remaining.isEmpty) {
      await preferences.remove(_queuedReportsKey);
    } else {
      await preferences.setString(_queuedReportsKey, jsonEncode(remaining));
    }
    return sent;
  }

  Future<Map<String, dynamic>> _submitReportNetwork(
      Map<String, dynamic> payload) async {
    final response = await _client
        .post(Uri.parse('$baseUrl/reports'),
            headers: {'content-type': 'application/json', ..._authHeaders()},
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 15));
    return _decode(response);
  }

  Future<void> _queueReport(Map<String, dynamic> payload) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_queuedReportsKey);
    dynamic decoded;
    if (raw != null) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        decoded = null;
      }
    }
    final queue = decoded is List ? decoded : <dynamic>[];
    queue.add({
      ...payload,
      'client_id': 'mobile-${DateTime.now().microsecondsSinceEpoch}'
    });
    await preferences.setString(_queuedReportsKey, jsonEncode(queue));
  }

  Future<List<Map<String, dynamic>>> _queuedReports() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_queuedReportsKey);
    if (raw == null) return [];
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return [];
    }
    return decoded is List
        ? decoded
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList()
        : [];
  }

  Future<void> _removeAcceptedReports(dynamic mutations) async {
    if (mutations is! List) return;
    final accepted = mutations
        .whereType<Map>()
        .map((item) => item['client_id'])
        .whereType<String>()
        .toSet();
    if (accepted.isEmpty) return;
    final queue = await _queuedReports();
    final remaining =
        queue.where((item) => !accepted.contains(item['client_id'])).toList();
    final preferences = await SharedPreferences.getInstance();
    if (remaining.isEmpty) {
      await preferences.remove(_queuedReportsKey);
    } else {
      await preferences.setString(_queuedReportsKey, jsonEncode(remaining));
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final dynamic value = jsonDecode(response.body);
    if (value is! Map) {
      throw ApiException('Unexpected response format (${response.statusCode})',
          statusCode: response.statusCode);
    }
    final mapValue = Map<String, dynamic>.from(value);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          '${mapValue['detail'] ?? 'Request failed'} (${response.statusCode})',
          statusCode: response.statusCode);
    }
    return mapValue;
  }

  List<dynamic> _decodeList(http.Response response) {
    final value = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = value is Map ? value['detail'] : null;
      throw ApiException(
          '${detail ?? 'Request failed'} (${response.statusCode})',
          statusCode: response.statusCode);
    }
    return value is List<dynamic> ? value : <dynamic>[];
  }

  Map<String, String> _authHeaders() =>
      token == null ? {} : {'Authorization': 'Bearer $token'};

  /// Internal helper for GET requests that returns parsed JSON directly
  @pragma('vm:entry-point')
  Future<Map<String, dynamic>> _internalGet(String endpoint) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl$endpoint'), headers: _authHeaders())
          .timeout(const Duration(seconds: 5));
      return _decode(response);
    } catch (e) {
      developer.log('API _internalGet error: $e');
      rethrow;
    }
  }

  /// Public method for GET requests that returns parsed JSON directly
  Future<Map<String, dynamic>> getEndpoint(String endpoint) async {
    return _internalGet(endpoint);
  }
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}