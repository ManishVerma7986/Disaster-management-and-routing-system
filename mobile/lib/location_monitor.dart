import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';

class LocationMonitor {
  StreamSubscription<Position>? _subscription;
  final _events = StreamController<LocationEvent>.broadcast();
  Stream<LocationEvent> get events => _events.stream;

  void start({required List<List<double>>? routeGeometry, double offRouteMeters = 200}) {
    _subscription?.cancel();
    _subscription = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25)).listen((position) {
      final metrics = routeGeometry == null ? null : _routeMetrics(position.latitude, position.longitude, routeGeometry);
      final distance = metrics?.distanceToRouteMeters;
      if (distance != null && distance > offRouteMeters) {
        _events.add(LocationEvent(position, LocationEventType.offRoute, distance, metrics?.remainingMeters, metrics?.progress));
      } else {
        _events.add(LocationEvent(position, LocationEventType.position, distance, metrics?.remainingMeters, metrics?.progress));
      }
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  _RouteMetrics? _routeMetrics(double lat, double lon, List<List<double>> geometry) {
    if (geometry.isEmpty) return null;
    var totalMeters = 0.0;
    final cumulative = <double>[0];
    for (var index = 1; index < geometry.length; index++) {
      totalMeters += _haversineMeters(geometry[index - 1][0],
          geometry[index - 1][1], geometry[index][0], geometry[index][1]);
      cumulative.add(totalMeters);
    }
    var nearestDistance = double.infinity;
    var travelledMeters = 0.0;
    for (var index = 1; index < geometry.length; index++) {
      final start = geometry[index - 1];
      final end = geometry[index];
      final segmentLength = cumulative[index] - cumulative[index - 1];
      final latitudeScale = cos(lat * pi / 180);
      final px = lon * latitudeScale;
      final py = lat;
      final ax = start[1] * latitudeScale;
      final ay = start[0];
      final bx = end[1] * latitudeScale;
      final by = end[0];
      final dx = bx - ax;
      final dy = by - ay;
      final squared = dx * dx + dy * dy;
      final fraction = squared == 0
          ? 0.0
          : ((px - ax) * dx + (py - ay) * dy) / squared;
      final clamped = fraction.clamp(0.0, 1.0);
      final closestLat = ay + dy * clamped;
      final closestLon = (ax + dx * clamped) / latitudeScale;
      final distance = _haversineMeters(lat, lon, closestLat, closestLon);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        travelledMeters =
          cumulative[index - 1] + segmentLength * clamped.toDouble();
      }
    }
    final remainingMeters = max(0.0, totalMeters - travelledMeters);
    return _RouteMetrics(nearestDistance, remainingMeters, totalMeters == 0 ? 0 : (travelledMeters / totalMeters).clamp(0.0, 1.0));
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const radius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final value = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLon / 2) * sin(dLon / 2);
    return radius * 2 * atan2(sqrt(value), sqrt(1 - value));
  }
}

enum LocationEventType { position, offRoute }

class LocationEvent {
  const LocationEvent(this.position, this.type, this.distanceMeters, this.remainingMeters, this.progress);
  final Position position;
  final LocationEventType type;
  final double? distanceMeters;
  final double? remainingMeters;
  final double? progress;
}

class _RouteMetrics {
  const _RouteMetrics(this.distanceToRouteMeters, this.remainingMeters, this.progress);
  final double distanceToRouteMeters;
  final double remainingMeters;
  final double progress;
}
