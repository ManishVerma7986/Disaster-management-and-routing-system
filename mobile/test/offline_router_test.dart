import 'package:flutter_test/flutter_test.dart';
import 'package:disaster_routing_mobile/offline_router.dart';

void main() {
  test('offline router calculates a cached graph path with metrics', () {
    final result = OfflineRouter().find(roads: [
      {'id': 'A', 'start_node': 'START', 'end_node': 'DEST', 'distance_km': 4.5, 'travel_time_minutes': 8, 'flood_risk': 'LOW', 'landslide_risk': 'LOW', 'geometry': [[12.9, 77.5], [12.91, 77.51]]},
    ], source: 'START', destination: 'DEST', mode: 'SAFEST');

    expect(result?['distance_km'], 4.5);
    expect(result?['eta_minutes'], 8);
    expect((result?['geometry'] as List).length, 2);
  });
}
