import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:vereinsappell/config_loader.dart';

/// Creates an [AppConfig] where [Member.fetchMember] completes with mock data
/// (including [isAdmin]) before the config is returned.
///
/// Must be called with [tester] so that the HTTP call runs outside fakeAsync
/// (via [WidgetTester.runAsync]), which prevents the pending socket from
/// blocking [pumpAndSettle] later.
Future<AppConfig> makeConfig(
  WidgetTester tester, {
  bool isAdmin = false,
  String? sessionPassword = 'testpw',
}) async {
  final config = await tester.runAsync(() async {
    final memberJson = jsonEncode({
      'memberId': 'user-1',
      'name': 'Test User',
      'isAdmin': isAdmin,
      'isSpiess': false,
      'token': '',
    });

    final client = MockClient((request) async {
      if (request.method == 'GET' && request.url.path == '/members/user-1') {
        return http.Response(memberJson, 200);
      }
      return http.Response('{}', 200);
    });

    late AppConfig config;
    await http.runWithClient(() async {
      config = AppConfig(
        apiBaseUrl: 'https://api.example.com',
        applicationId: 'test-app',
        memberId: 'user-1',
        sessionPassword: sessionPassword,
      );
      // Give Member.fetchMember() time to complete via MockClient
      await Future.delayed(const Duration(milliseconds: 100));
    }, () => client);

    return config;
  });
  return config!;
}

Widget wrapScreen(Widget screen, AppConfig config) => MaterialApp(
      home: ChangeNotifierProvider<Member>.value(
        value: config.member,
        child: screen,
      ),
    );
