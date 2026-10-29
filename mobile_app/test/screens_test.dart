import 'dart:convert';

import 'package:child_activities/main.dart';
import 'package:child_activities/models/child_profile.dart';
import 'package:child_activities/screens/child_profile_screen.dart';
import 'package:child_activities/screens/recommendations_screen.dart';
import 'package:child_activities/services/api_client.dart';
import 'package:child_activities/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

/// A tiny in-memory stand-in for the FastAPI backend.
class FakeBackend {
  final requests = <http.Request>[];
  final children = <Map<String, dynamic>>[];
  final ratings = <String, int>{};

  late final client = MockClient((req) async {
    requests.add(req);
    final path = req.url.path;
    Map<String, dynamic> body() => jsonDecode(req.body) as Map<String, dynamic>;
    http.Response ok(Object? json, [int code = 200]) =>
        http.Response(jsonEncode(json), code);

    if (path == '/auth/login') {
      if (body()['password'] != 'password123') {
        return ok({'detail': 'Incorrect email or password'}, 401);
      }
      return ok({
        'access_token': 'tok',
        'caregiver': {'caregiver_id': 1, 'name': 'Sam', 'email': 'sam@example.com'}
      });
    }
    if (path == '/children' && req.method == 'GET') return ok(children);
    if (path == '/children' && req.method == 'POST') {
      final b = body();
      final child = {
        'child_id': children.length + 1,
        'caregiver_id': 1,
        'name': b['name'],
        'birth_date': b['birth_date'],
        'age_in_months': 13,
        'interests': b['interests'],
      };
      children.add(child);
      return ok(child, 201);
    }
    if (path == '/recommend') {
      return ok({
        'child_name': 'Ada',
        'age_in_months': 13,
        'interests_used': body()['interests'],
        'results': [
          for (final id in ['A1', 'A2'])
            {
              'activity_id': id,
              'age_in_months': 12,
              'activity_description': 'Activity $id',
              'category': 'Play',
              'interest': 'Music',
              'target_developmental_area': 'Cognitive',
              'materials_needed': 'Rattle',
              'similarity': 0.6,
              'my_rating': ratings[id],
              'comment_count': 0,
            }
        ],
      });
    }
    final rating = RegExp(r'^/children/(\d+)/activities/(\w+)/rating$').firstMatch(path);
    if (rating != null && req.method == 'PUT') {
      ratings[rating.group(2)!] = body()['rating'] as int;
      return ok({'rating': ratings[rating.group(2)!]});
    }
    return ok({'detail': 'Not found: ${req.method} $path'}, 404);
  });
}

Widget wrap(ApiClient api, AuthService auth, Widget child) => MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ],
      child: MaterialApp(home: child),
    );

void main() {
  late FakeBackend backend;
  late ApiClient api;
  late AuthService auth;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    backend = FakeBackend();
    api = ApiClient(baseUrl: 'http://api.test', httpClient: backend.client);
    auth = AuthService(api);
  });

  testWidgets('login validates input, shows server errors, then signs in',
      (tester) async {
    await auth.init();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ],
      child: const ChildActivitiesApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('email')), 'sam@example.com');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect email or password'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('password')), 'password123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    expect(auth.status, AuthStatus.signedIn);
    expect(find.text('Add your first child'), findsOneWidget);
    expect(await const FlutterSecureStorage().read(key: 'auth_token'), 'tok');
  });

  testWidgets('register mode asks for name and matching passwords',
      (tester) async {
    await auth.init();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthService>.value(value: auth),
      ],
      child: const ChildActivitiesApp(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('email')), 'a@b.co');
    await tester.enterText(find.byKey(const Key('password')), 'password123');
    await tester.enterText(find.byKey(const Key('confirm')), 'different1');
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(backend.requests, isEmpty);
  });

  testWidgets('child profile form requires birth date and interests, then saves',
      (tester) async {
    await tester.pumpWidget(wrap(api, auth, const ChildProfileScreen()));

    await tester.enterText(find.byKey(const Key('child-name')), 'Ada');
    await tester.tap(find.byKey(const Key('save-child')));
    await tester.pump();
    expect(find.text('Choose a birth date'), findsOneWidget);
    expect(find.text('Choose at least one interest'), findsOneWidget);

    await tester.tap(find.byKey(const Key('birth-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('interest-Music')));
    await tester.tap(find.byKey(const Key('interest-Art')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-child')));
    await tester.pumpAndSettle();

    final post = backend.requests.singleWhere((r) => r.method == 'POST');
    final sent = jsonDecode(post.body) as Map<String, dynamic>;
    expect(sent['name'], 'Ada');
    expect(sent['interests'], ['Music', 'Art']);
    expect(sent['birth_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  testWidgets('recommendations list loads and rating a card saves it',
      (tester) async {
    final child = ChildProfile(
      id: 1,
      name: 'Ada',
      birthDate: DateTime(2025, 9, 1),
      ageInMonths: 13,
      interests: const ['Music'],
    );
    await tester.pumpWidget(wrap(api, auth, RecommendationsScreen(child: child)));
    await tester.pumpAndSettle();

    expect(find.text('Activity A1'), findsOneWidget);
    expect(find.text('Activity A2'), findsOneWidget);
    // Only 2 of the 5 requested matched, so the list says it's showing all.
    expect(find.text("That's all 2 Music activities for 13 months."),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('star-4')).first);
    await tester.pumpAndSettle();
    expect(backend.ratings, {'A1': 4});
    // First card now shows 4 filled stars; the second card is still unrated.
    expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));

    // Changing interests re-queries the model with the new selection.
    await tester.tap(find.widgetWithText(FilterChip, 'Art'));
    await tester.pumpAndSettle();
    final last = backend.requests.lastWhere((r) => r.url.path == '/recommend');
    expect(jsonDecode(last.body)['interests'], ['Music', 'Art']);
  });
}
