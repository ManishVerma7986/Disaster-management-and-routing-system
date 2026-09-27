import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SavedRouteStore {
  const SavedRouteStore();

  static const _key = 'saved_offline_routes';

  Future<List<Map<String, dynamic>>> list() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.whereType<Map>().map((value) => Map<String, dynamic>.from(value)).toList();
  }

  Future<void> save(Map<String, dynamic> route, {required String source, required String destination, required String mode}) async {
    final routes = await list();
    final entry = <String, dynamic>{'id': route['route_id'] ?? DateTime.now().millisecondsSinceEpoch.toString(), 'source': source, 'destination': destination, 'mode': mode, 'saved_at': DateTime.now().toUtc().toIso8601String(), 'route': route};
    routes.removeWhere((item) => item['id'] == entry['id']);
    routes.insert(0, entry);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(routes));
  }

  Future<void> remove(String id) async {
    final routes = await list();
    routes.removeWhere((item) => item['id'] == id);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, jsonEncode(routes));
  }
}
