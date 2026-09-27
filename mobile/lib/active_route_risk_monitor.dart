import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'location_monitor.dart';
import 'api_service.dart';

/// Represents the current risk for a route segment
class SegmentRisk {
  final String? roadId;
  final String? roadName;
  final double? distanceToSegmentM;
  final String floodLevel;
  final String landslideLevel;
  final int floodConfidence;
  final int landslideConfidence;
  final List<String> floodSources;
  final List<String> landslideSources;
  final double? distanceToHazardM;
  final String? hazardType;
  final List<String> warnings;
  final String dataSource;

  SegmentRisk({
    required this.roadId,
    required this.roadName,
    required this.distanceToSegmentM,
    required this.floodLevel,
    required this.landslideLevel,
    required this.floodConfidence,
    required this.landslideConfidence,
    required this.floodSources,
    required this.landslideSources,
    required this.distanceToHazardM,
    required this.hazardType,
    required this.warnings,
    required this.dataSource,
  });

  factory SegmentRisk.fromJson(Map<String, dynamic> json) {
    return SegmentRisk(
      roadId: json['current_segment']?['road_id'] as String?,
      roadName: json['current_segment']?['road_name'] as String?,
      distanceToSegmentM: (json['current_segment']?['distance_to_segment_m'] as num?)?.toDouble(),
      floodLevel: json['flood']?['level'] ?? 'LOW',
      landslideLevel: json['landslide']?['level'] ?? 'LOW',
      floodConfidence: json['flood']?['confidence'] ?? 50,
      landslideConfidence: json['landslide']?['confidence'] ?? 50,
      floodSources: List<String>.from(json['flood']?['sources'] ?? []),
      landslideSources: List<String>.from(json['landslide']?['sources'] ?? []),
      distanceToHazardM: (json['distance_to_hazard_m'] as num?)?.toDouble(),
      hazardType: json['hazard_type'] as String?,
      warnings: List<String>.from(json['warnings'] ?? []),
      dataSource: json['data_source'] ?? 'offline',
    );
  }

  /// Check if this is a HIGH or CRITICAL risk
  bool get isHighRisk => floodLevel == 'HIGH' || floodLevel == 'CRITICAL' || landslideLevel == 'HIGH' || landslideLevel == 'CRITICAL';

  /// Get color for UI display
  Color getRiskColor(String level) {
    switch (level) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.orange;
      case 'MEDIUM':
        return Colors.yellow[700]!;
      case 'LOW':
      default:
        return Colors.green;
    }
  }

  /// Get icon for risk level
  IconData getRiskIcon(String level) {
    switch (level) {
      case 'CRITICAL':
      case 'HIGH':
        return Icons.warning_rounded;
      case 'MEDIUM':
        return Icons.info_rounded;
      case 'LOW':
      default:
        return Icons.check_circle_rounded;
    }
  }
}

/// Monitors real-time flood and landslide risks on active route
class ActiveRouteRiskMonitor {
  final ApiService apiService;
  final LocationMonitor locationMonitor;
  final VoidCallback? onRiskUpdate;
  final Function(SegmentRisk)? onWarning;

  StreamSubscription<LocationEvent>? _locationSubscription;
  final _riskUpdates = StreamController<SegmentRisk>.broadcast();
  Stream<SegmentRisk> get riskUpdates => _riskUpdates.stream;

  SegmentRisk? _currentRisk;
  SegmentRisk? get currentRisk => _currentRisk;

  String? _lastWarningSegmentId;
  DateTime? _lastWarningTime;

  List<List<double>>? _routeGeometry;
  bool _isMonitoring = false;
  int _skipCount = 0; // Skip GPS updates to avoid excessive backend calls

  ActiveRouteRiskMonitor({
    required this.apiService,
    required this.locationMonitor,
    this.onRiskUpdate,
    this.onWarning,
  });

  /// Start monitoring risk with active route geometry
  void start(List<List<double>> routeGeometry) {
    if (_isMonitoring) return;

    _routeGeometry = routeGeometry;
    _isMonitoring = true;
    _lastWarningSegmentId = null;
    _lastWarningTime = null;
    _skipCount = 0;

    developer.log('ActiveRouteRiskMonitor: Started monitoring route with ${routeGeometry.length} points');

    _locationSubscription = locationMonitor.events.listen((LocationEvent event) {
      _onLocationUpdate(event);
    });
  }

  /// Stop monitoring
  void stop() {
    if (!_isMonitoring) return;
    _locationSubscription?.cancel();
    _isMonitoring = false;
    developer.log('ActiveRouteRiskMonitor: Stopped monitoring');
  }

  /// Dispose resources
  Future<void> dispose() async {
    stop(); // Don't await - it's fire and forget
    await _riskUpdates.close();
  }

  /// Handle location update from GPS
  Future<void> _onLocationUpdate(LocationEvent event) async {
    if (!_isMonitoring || _routeGeometry == null || _routeGeometry!.isEmpty) return;

    // Skip some GPS updates to reduce backend calls (hysteresis)
    _skipCount++;
    if (_skipCount < 3) return; // Only check every 3rd GPS update (~75m movement)
    _skipCount = 0;

    try {
      final lat = event.position.latitude;
      final lon = event.position.longitude;

      // Build geometry string for API
      final geometryStr = _routeGeometry!.map((point) => '${point[0]},${point[1]}').join(',');

      // Call backend endpoint via API service
      final response = await apiService.getEndpoint('/risk/segment?lat=$lat&lon=$lon&geometry=$geometryStr');

      if (response.containsKey('current_segment')) {
        final risk = SegmentRisk.fromJson(response);

        _currentRisk = risk;
        _riskUpdates.add(risk);
        onRiskUpdate?.call();

        // Check if warning should be shown
        _checkAndShowWarning(risk);

        developer.log(
          'Risk update: ${risk.roadName}, Flood: ${risk.floodLevel}, Landslide: ${risk.landslideLevel}, '
          'Distance: ${risk.distanceToHazardM}m, Hazard: ${risk.hazardType}',
        );
      }
    } catch (e) {
      developer.log('Error fetching segment risk: $e');
      // Continue with cached risk on error
    }
  }

  /// Check and show warning if needed (with deduplication)
  void _checkAndShowWarning(SegmentRisk risk) {
    if (risk.roadId == null) return;

    final isHighRisk = risk.floodLevel == 'HIGH' ||
        risk.floodLevel == 'CRITICAL' ||
        risk.landslideLevel == 'HIGH' ||
        risk.landslideLevel == 'CRITICAL';

    if (!isHighRisk) return;

    // Deduplication logic
    final now = DateTime.now();
    final isDifferentSegment = risk.roadId != _lastWarningSegmentId;
    final isTimedOut = _lastWarningTime == null ||
        now.difference(_lastWarningTime!).inMinutes >= 2;

    if (!isDifferentSegment && !isTimedOut) {
      // Same segment, too soon — don't warn again
      return;
    }

    // Update tracking
    _lastWarningSegmentId = risk.roadId;
    _lastWarningTime = now;

    // Trigger callback
    onWarning?.call(risk);

    developer.log('⚠️ WARNING: ${risk.roadName} - Flood: ${risk.floodLevel}, '
        'Landslide: ${risk.landslideLevel}, Distance: ${risk.distanceToHazardM}m');
  }

  /// Get formatted warning message
  static String formatWarningMessage(SegmentRisk risk) {
    final parts = <String>[];

    if (risk.floodLevel == 'CRITICAL' || risk.floodLevel == 'HIGH') {
      parts.add('⚠️ FLOOD RISK: ${risk.floodLevel}');
    }

    if (risk.landslideLevel == 'CRITICAL' || risk.landslideLevel == 'HIGH') {
      parts.add('⚠️ LANDSLIDE RISK: ${risk.landslideLevel}');
    }

    if (risk.distanceToHazardM != null && risk.distanceToHazardM! > 0) {
      parts.add('Distance: ${(risk.distanceToHazardM! / 1000).toStringAsFixed(1)} km');
    }

    return parts.join('\n');
  }
}
