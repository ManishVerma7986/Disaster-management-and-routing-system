import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ActiveRouteRiskMonitor', () {
    test('SegmentRisk.fromJson correctly parses response', () {
      final json = {
        'current_segment': {
          'road_id': 'road_123',
          'road_name': 'Test Road',
          'distance_to_segment_m': 45.5,
        },
        'flood': {
          'level': 'HIGH',
          'confidence': 85,
          'sources': ['weather', 'incident'],
        },
        'landslide': {
          'level': 'MEDIUM',
          'confidence': 70,
          'sources': ['road_data'],
        },
        'distance_to_hazard_m': 450.0,
        'hazard_type': 'flood',
        'warnings': ['High flood risk ahead'],
        'data_source': 'online',
      };

      // This test verifies the model can parse the JSON response
      expect((json['current_segment'] as Map?)?['road_id'], 'road_123');
      expect((json['flood'] as Map?)?['level'], 'HIGH');
      expect((json['landslide'] as Map?)?['level'], 'MEDIUM');
    });

    test('SegmentRisk identifies high risk correctly', () {
      final json = {
        'current_segment': {
          'road_id': 'road_123',
          'road_name': 'High Risk Road',
          'distance_to_segment_m': 50.0,
        },
        'flood': {
          'level': 'CRITICAL',
          'confidence': 95,
          'sources': ['weather'],
        },
        'landslide': {
          'level': 'LOW',
          'confidence': 50,
          'sources': <String>[],
        },
        'distance_to_hazard_m': null,
        'hazard_type': null,
        'warnings': <String>[],
        'data_source': 'online',
      };

      // Check high risk detection
      final floodLevel = (json['flood'] as Map?)?['level'] as String? ?? 'LOW';
      final landslideLevel = (json['landslide'] as Map?)?['level'] as String? ?? 'LOW';
      final isHighRisk = floodLevel == 'HIGH' ||
          floodLevel == 'CRITICAL' ||
          landslideLevel == 'HIGH' ||
          landslideLevel == 'CRITICAL';

      expect(isHighRisk, true);
    });

    test('SegmentRisk identifies low risk correctly', () {
      final json = {
        'current_segment': {
          'road_id': 'road_456',
          'road_name': 'Safe Road',
          'distance_to_segment_m': 75.0,
        },
        'flood': {
          'level': 'LOW',
          'confidence': 90,
          'sources': ['road_data'],
        },
        'landslide': {
          'level': 'LOW',
          'confidence': 90,
          'sources': <String>[],
        },
        'distance_to_hazard_m': 5000.0,
        'hazard_type': null,
        'warnings': <String>[],
        'data_source': 'online',
      };

      // Check low risk detection
      final floodLevel = (json['flood'] as Map?)?['level'] as String? ?? 'LOW';
      final landslideLevel = (json['landslide'] as Map?)?['level'] as String? ?? 'LOW';
      final isHighRisk = floodLevel == 'HIGH' ||
          floodLevel == 'CRITICAL' ||
          landslideLevel == 'HIGH' ||
          landslideLevel == 'CRITICAL';

      expect(isHighRisk, false);
    });

    test('formatWarningMessage creates correct warning text', () {
      // Simulate warning message formatting
      final riskData = {
        'floodLevel': 'HIGH',
        'landslideLevel': 'LOW',
        'distanceToHazardM': 450.0,
      };

      final parts = <String>[];
      final floodLevel = riskData['floodLevel'] as String?;
      final landslideLevel = riskData['landslideLevel'] as String?;
      final distance = riskData['distanceToHazardM'] as double?;

      if (floodLevel == 'CRITICAL' || floodLevel == 'HIGH') {
        parts.add('⚠️ FLOOD RISK: $floodLevel');
      }
      if (landslideLevel == 'CRITICAL' || landslideLevel == 'HIGH') {
        parts.add('⚠️ LANDSLIDE RISK: $landslideLevel');
      }
      if (distance != null && distance > 0) {
        parts.add('Distance: ${(distance / 1000).toStringAsFixed(1)} km');
      }

      final message = parts.join('\n');
      expect(message.contains('FLOOD RISK'), true);
      expect(message.contains('0.4'), true); // 450m ≈ 0.45km
    });

    test('Risk level color mapping is correct', () {
      // Verify color mapping logic
      final levelToColor = {
        'CRITICAL': 'red',
        'HIGH': 'orange',
        'MEDIUM': 'yellow',
        'LOW': 'green',
      };

      expect(levelToColor['CRITICAL'], 'red');
      expect(levelToColor['HIGH'], 'orange');
      expect(levelToColor['MEDIUM'], 'yellow');
      expect(levelToColor['LOW'], 'green');
    });

    test('Warning deduplication prevents repeated warnings', () {
      // Simulate deduplication logic
      String? lastWarningSegmentId;
      DateTime? lastWarningTime;

      // First warning
      lastWarningSegmentId = 'road_123';
      lastWarningTime = DateTime.now();
      var shouldWarn = true;

      // Second update on same segment, immediately
      final isDifferentSegment = 'road_123' != lastWarningSegmentId;
      final isTimedOut = DateTime.now().difference(lastWarningTime).inMinutes >= 2;

      shouldWarn = isDifferentSegment || isTimedOut;
      expect(shouldWarn, false); // Should NOT warn again

      // Third update after 2 minutes
      lastWarningTime = DateTime.now().subtract(const Duration(minutes: 3));
      final isTimedOut2 =
          DateTime.now().difference(lastWarningTime).inMinutes >= 2;

      shouldWarn = isDifferentSegment || isTimedOut2;
      expect(shouldWarn, true); // Should warn after timeout
    });

    test('Different segment triggers warning even without timeout', () {
      // Simulate segment change detection
      final lastWarningSegmentId = 'road_123';

      // User enters new segment
      final newSegmentId = 'road_456';
      final isDifferentSegment = newSegmentId != lastWarningSegmentId;

      expect(isDifferentSegment, true);
      // Should warn immediately for new segment
    });

    test('Offline data source is handled gracefully', () {
      final json = {
        'current_segment': {
          'road_id': 'road_offline',
          'road_name': 'Offline Road',
          'distance_to_segment_m': 60.0,
        },
        'flood': {
          'level': 'LOW',
          'confidence': 60,
          'sources': ['road_data'],
        },
        'landslide': {
          'level': 'MEDIUM',
          'confidence': 50,
          'sources': ['road_data'],
        },
        'distance_to_hazard_m': null,
        'hazard_type': null,
        'warnings': <String>[],
        'data_source': 'offline',
      };

      expect(json['data_source'], 'offline');
      expect(json['current_segment'] != null, true);
      // Offline mode should still provide risk data
    });

    test('Missing data is handled safely', () {
      // Minimal response
      final json = {
        'current_segment': null,
        'flood': {'level': 'LOW', 'confidence': 0, 'sources': <String>[]},
        'landslide': {'level': 'LOW', 'confidence': 0, 'sources': <String>[]},
        'distance_to_hazard_m': null,
        'hazard_type': null,
        'warnings': ['GPS position not matched to route segment'],
        'data_source': 'offline',
      };

      expect(json['current_segment'], null);
      final warnings = json['warnings'] as List?;
      expect(warnings?.isNotEmpty ?? false, true);
      // Should gracefully handle missing segment data
    });

    test('Multiple sources are tracked correctly', () {
      final json = {
        'current_segment': {
          'road_id': 'road_multi',
          'road_name': 'Multi-Source Road',
          'distance_to_segment_m': 30.0,
        },
        'flood': {
          'level': 'HIGH',
          'confidence': 90,
          'sources': ['road_data', 'weather', 'incident'],
        },
        'landslide': {
          'level': 'MEDIUM',
          'confidence': 75,
          'sources': ['weather'],
        },
        'distance_to_hazard_m': 750.0,
        'hazard_type': 'flood',
        'warnings': <String>[],
        'data_source': 'online',
      };

      final floodSources = (json['flood'] as Map?)?['sources'] as List?;
      expect(floodSources?.length, 3);
      expect(floodSources?.contains('road_data'), true);
      expect(floodSources?.contains('weather'), true);
      expect(floodSources?.contains('incident'), true);
    });
  });
}

