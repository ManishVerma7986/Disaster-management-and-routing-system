import 'package:flutter_tts/flutter_tts.dart';

class VoiceNavigationService {
  final FlutterTts _tts = FlutterTts();
  bool enabled = true;

  Future<void> initialize({String language = 'en-US'}) async {
    try {
      await _tts.setLanguage(language);
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
    } catch (_) {
      enabled = false;
    }
  }

  Future<void> announce(String message) async {
    if (!enabled) return;
    try {
      await _tts.stop();
      await _tts.speak(message);
    } catch (_) {
      enabled = false;
    }
  }

  Future<void> routeStarted(Map<String, dynamic> route) => announce('Navigation started. ${route['distance_km']} kilometres, approximately ${route['eta_minutes']} minutes.');
  Future<void> routeRecalculated() => announce('The route has changed. Recalculating a safer route.');
  Future<void> arrived() => announce('You have arrived at your destination.');
  Future<void> stop() => _tts.stop();
}