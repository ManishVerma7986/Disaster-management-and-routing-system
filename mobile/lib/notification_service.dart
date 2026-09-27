import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class NotificationService {
  final _tapEvents = <void Function(Map<String, dynamic>)>[];
  final _messageEvents = <void Function(RemoteMessage)>[];
  bool available = false;

  Future<void> initialize() async {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen((message) { for (final listener in _messageEvents) { listener(message); } });
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _notifyTap(message.data));
      available = true;
    } catch (_) {
      available = false;
    }
  }

  void onTap(void Function(Map<String, dynamic>) listener) => _tapEvents.add(listener);
  void onMessage(void Function(RemoteMessage) listener) => _messageEvents.add(listener);
  Future<String?> token() async => available ? FirebaseMessaging.instance.getToken() : null;
  void _notifyTap(Map<String, dynamic> data) {
    for (final listener in _tapEvents) {
      listener(data);
    }
  }
}
