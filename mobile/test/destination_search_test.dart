import 'package:flutter_test/flutter_test.dart';
import 'package:disaster_routing_mobile/destination_search_service.dart';

void main() {
  test('destination suggestions parse coordinates and display metadata', () {
    final suggestion = DestinationSuggestion.fromJson({'name': 'Relief Centre', 'display_name': 'Relief Centre, Bengaluru', 'lat': '12.9716', 'lon': '77.5946'});

    expect(suggestion.name, 'Relief Centre');
    expect(suggestion.displayName, contains('Bengaluru'));
    expect(suggestion.latitude, 12.9716);
    expect(suggestion.longitude, 77.5946);
  });
}
