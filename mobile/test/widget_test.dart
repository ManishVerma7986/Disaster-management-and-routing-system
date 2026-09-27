// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'package:disaster_routing_mobile/main.dart';
import 'package:disaster_routing_mobile/api_service.dart';

void main() {
  testWidgets('login screen renders emergency-first branding',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SafeRouteApp());
    expect(find.text('DISASTER AWARE'), findsOneWidget);
    expect(find.text('Stay Safe. Stay Informed.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('home dashboard exposes emergency-first controls',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeTab(
          onRoute: (_, __, ___) async {},
          route: null,
          position: null,
          status: 'Monitoring local road conditions',
          emergencyMode: false,
          onChooseFromMap: () async => null,
          onChooseSourceFromMap: () async => null,
          onEmergency: () {},
          api: ApiService(),
        ),
      ),
    ));

    expect(find.text('Emergency control center'), findsOneWidget);
    expect(find.text('Active warnings'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Find a safer route'), findsOneWidget);
    expect(find.text('Emergency'), findsOneWidget);
  });

  testWidgets('emergency screen guards SOS behind a hold action',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: EmergencyTab(api: ApiService(), position: null),
      ),
    ));
    await tester.pump();

    expect(find.text('HOLD TO SEND SOS'), findsOneWidget);
    expect(
        find.text('Press and hold for 2 seconds to activate'), findsOneWidget);
  });

  testWidgets('home enters dynamic emergency mode for critical risk',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeTab(
          onRoute: (_, __, ___) async {},
          route: null,
          position: null,
          status: 'Critical route risk detected',
          emergencyMode: true,
          onChooseFromMap: () async => null,
          onChooseSourceFromMap: () async => null,
          onEmergency: () {},
          api: ApiService(),
        ),
      ),
    ));

    expect(find.text('EMERGENCY MODE'), findsOneWidget);
    expect(find.text('Critical route risk detected'), findsOneWidget);
  });

  testWidgets('home ignores an invalid boolean recommended route',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HomeTab(
          onRoute: (_, __, ___) async {},
          route: const {'recommended': true},
          position: null,
          status: 'OFFLINE ROUTING',
          emergencyMode: false,
          onChooseFromMap: () async => null,
          onChooseSourceFromMap: () async => null,
          onEmergency: () {},
          api: ApiService(),
        ),
      ),
    ));

    expect(find.text('Emergency control center'), findsOneWidget);
  });

  testWidgets('profile exposes safety and accessibility settings',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ProfileTab(
          user: const {
            'name': 'Test User',
            'email': 'test.user@example.com',
            'role': 'USER'
          },
          onLogout: () async {},
        ),
      ),
    ));

    expect(find.text('Emergency notifications'), findsOneWidget);
    expect(find.text('Location services'), findsOneWidget);
    expect(find.text('Larger text'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Emergency contacts'), 400,
        scrollable: find.byType(Scrollable));
    expect(find.text('Emergency contacts'), findsOneWidget);
  });

}
