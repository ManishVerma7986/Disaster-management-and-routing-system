import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

class BackgroundLocationService {
  Future<void> configure() async {
    final service = FlutterBackgroundService();
    await service.configure(androidConfiguration: AndroidConfiguration(onStart: backgroundEntryPoint, autoStart: false, isForegroundMode: true, notificationChannelId: 'location_tracking', initialNotificationTitle: 'SafeRoute location active', initialNotificationContent: 'Monitoring route safety'), iosConfiguration: IosConfiguration(autoStart: false, onForeground: backgroundEntryPoint, onBackground: iosBackgroundEntryPoint));
  }

  Future<void> start() => FlutterBackgroundService().startService();
  Future<void> stop() async { FlutterBackgroundService().invoke('stopService'); }
}

@pragma('vm:entry-point')
void backgroundEntryPoint(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();
  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
  }
  final timer = Timer.periodic(const Duration(seconds: 30), (_) async {
    if (service is AndroidServiceInstance && await service.isForegroundService()) await Geolocator.getCurrentPosition();
  });
  service.on('stopService').listen((_) {
    timer.cancel();
    service.stopSelf();
  });
}

@pragma('vm:entry-point')
Future<bool> iosBackgroundEntryPoint(ServiceInstance service) async => true;
