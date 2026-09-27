class OfflineRouter {
  Map<String, dynamic>? find({
    required List<dynamic> roads,
    required String source,
    required String destination,
    required String mode,
  }) {
    final validRoads = roads
        .whereType<Map>()
        .map(
          (road) => Map<String, dynamic>.from(road),
        )
        .toList();

    if (validRoads.isEmpty) {
      return null;
    }

    final queue = <_State>[
      _State(
        0,
        source,
        const [],
        const [],
      ),
    ];

    final visited = <String>{};

    while (queue.isNotEmpty) {
      queue.sort(
        (a, b) => a.cost.compareTo(b.cost),
      );

      final state = queue.removeAt(0);

      if (state.node == destination) {
        return _result(
          state.roads,
          validRoads,
          mode,
        );
      }

      final visitKey =
          '${state.node}:${state.roads.join(',')}';

      if (!visited.add(visitKey)) {
        continue;
      }

      for (final road in validRoads) {
        final startNode =
            road['start_node']?.toString();

        final endNode =
            road['end_node']?.toString();

        final roadId =
            road['id']?.toString();

        if (startNode == null ||
            endNode == null ||
            roadId == null) {
          continue;
        }

        if (startNode != state.node) {
          continue;
        }

        if (state.roads.contains(roadId)) {
          continue;
        }

        if (_closed(road)) {
          continue;
        }

        final cost = _cost(
          road,
          mode,
        );

        queue.add(
          _State(
            state.cost + cost,
            endNode,
            [
              ...state.nodes,
              state.node,
            ],
            [
              ...state.roads,
              roadId,
            ],
          ),
        );
      }
    }

    return null;
  }

  bool _closed(
    Map<String, dynamic> road,
  ) {
    final closureReason =
        road['closure_reason'];

    if (closureReason == null) {
      return false;
    }

    final startValue =
        road['closure_start_time'];

    if (startValue != null) {
      try {
        final start = DateTime.parse(
          startValue.toString(),
        );

        if (start.isAfter(
          DateTime.now().toUtc(),
        )) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }

    final endValue =
        road['closure_end_time'];

    if (endValue == null) {
      return true;
    }

    try {
      final end = DateTime.parse(
        endValue.toString(),
      );

      return end.isAfter(
        DateTime.now().toUtc(),
      );
    } catch (_) {
      return true;
    }
  }

  double _cost(
    Map<String, dynamic> road,
    String mode,
  ) {
    final travelTimeValue =
        road['travel_time_minutes'];

    final time = travelTimeValue is num
        ? travelTimeValue.toDouble()
        : 0.0;

    final flood = _risk(
      road['flood_risk']?.toString(),
    );

    final landslide = _risk(
      road['landslide_risk']?.toString(),
    );

    final multiplier =
        mode == 'SAFEST'
            ? 8.0
            : mode == 'FASTEST'
                ? 0.5
                : mode == 'EMERGENCY'
                    ? 2.0
                    : 3.0;

    return time +
        (flood + landslide) * multiplier;
  }

  int _risk(String? value) {
    return {
          'LOW': 0,
          'MEDIUM': 1,
          'HIGH': 3,
          'CRITICAL': 8,
        }[value] ??
        0;
  }

  Map<String, dynamic> _result(
    List<String> ids,
    List<Map<String, dynamic>> roads,
    String mode,
  ) {
    final selected =
        <Map<String, dynamic>>[];

    for (final id in ids) {
      for (final road in roads) {
        if (road['id']?.toString() == id) {
          selected.add(road);
          break;
        }
      }
    }

    if (selected.isEmpty) {
      return {
        'route_id':
            'offline-${DateTime.now().millisecondsSinceEpoch}',
        'recommended': null,
        'alternatives': <dynamic>[],
        'data_status': 'OFFLINE CACHE',
        'warnings': [
          'No valid cached road segments were found.',
        ],
        'reason':
            'Offline route could not use the cached road graph.',
        'mode': mode,
      };
    }

    final geometry = <dynamic>[];

    for (final road in selected) {
      final rawPoints =
          road['geometry'];

      final points = rawPoints is List
          ? rawPoints
          : const <dynamic>[];

      if (geometry.isEmpty) {
        geometry.addAll(points);
      } else if (points.length > 1) {
        geometry.addAll(
          points.skip(1),
        );
      }
    }

    final distance =
        selected.fold<double>(
      0.0,
      (sum, road) {
        final value =
            road['distance_km'];

        if (value is num) {
          return sum + value.toDouble();
        }

        return sum;
      },
    );

    final eta =
        selected.fold<double>(
      0.0,
      (sum, road) {
        final value =
            road['travel_time_minutes'];

        if (value is num) {
          return sum + value.toDouble();
        }

        return sum;
      },
    );

    final segments =
        selected.map((road) {
      return {
        'road_id': road['id'],
        'road_name': road['name'],
        'distance_km':
            road['distance_km'],
        'travel_time_minutes':
            road['travel_time_minutes'],
        'flood_risk':
            road['flood_risk'],
        'landslide_risk':
            road['landslide_risk'],
        'closure_status': 'OPEN',
        'geometry':
            road['geometry'],
      };
    }).toList();

    final routeId =
        'offline-${DateTime.now().millisecondsSinceEpoch}';

    final recommended =
        <String, dynamic>{
      'route_id': routeId,
      'recommended': true,
      'distance_km':
          double.parse(
        distance.toStringAsFixed(2),
      ),
      'eta_minutes':
          eta.round(),
      'risk': {
        'overall': 'UNKNOWN',
        'confidence': 0,
        'flood': 'UNKNOWN',
        'landslide': 'UNKNOWN',
      },
      'warnings': [
        'Calculated from cached road data in OFFLINE MODE.',
      ],
      'reason':
          'No network connection. This route uses the last synchronized road graph.',
      'geometry': geometry,
      'segments': segments,
      'mode': mode,
    };

  return {
  'route_id': routeId,
  'recommended': recommended,

  // Top-level metrics used by offline route tests
  // and other route consumers.
  'distance_km': double.parse(
    distance.toStringAsFixed(2),
  ),
  'eta_minutes': eta.round(),
  'geometry': geometry,
  'segments': segments,

  'alternatives': <dynamic>[],
  'data_status': 'OFFLINE CACHE',
  'warnings': [
    'Calculated from cached road data in OFFLINE MODE.',
  ],
  'reason':
      'No network connection. This route uses the last synchronized road graph.',
  'mode': mode,
};
  }
}

class _State {
  _State(
    this.cost,
    this.node,
    this.nodes,
    this.roads,
  );

  final double cost;
  final String node;
  final List<String> nodes;
  final List<String> roads;
}