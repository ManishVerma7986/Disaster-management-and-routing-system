import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:disaster_routing_mobile/api_service.dart';

class RecordingClient extends http.BaseClient {
  Uri? requestedUri;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUri = request.url;
    return http.StreamedResponse(Stream.value('{"access_token":"token","user":{}}'.codeUnits), 200, headers: {'content-type': 'application/json'});
  }
}

void main() {
  test('login sends credentials as a JSON body', () async {
    final client = RecordingClient();
    final service = ApiService(client: client);
    final result = await service.login('test.user@example.com', 'TestUser123!');

    expect(result['access_token'], 'token');
    expect(client.requestedUri?.queryParameters, isEmpty);
  });
}
