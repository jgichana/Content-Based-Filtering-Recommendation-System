import 'dart:convert';

import 'package:child_activities/models/child_profile.dart';
import 'package:child_activities/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ApiClient', () {
    test('sends bearer token and parses recommendations', () async {
      late http.Request seen;
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'child_name': 'Ada',
              'age_in_months': 13,
              'interests_used': ['Music'],
              'results': [
                {
                  'activity_id': 'A1',
                  'age_in_months': 12,
                  'activity_description': 'Shake a rattle',
                  'category': 'Play',
                  'interest': 'Music',
                  'target_developmental_area': 'Cognitive',
                  'materials_needed': null,
                  'similarity': 0.71,
                  'my_rating': 4,
                  'comment_count': 2,
                }
              ],
            }),
            200,
          );
        }),
      )..token = 'tok';

      final result = await api.recommend(1, k: 3, interests: ['Music']);

      expect(seen.method, 'POST');
      expect(seen.url.toString(), 'http://api.test/recommend');
      expect(seen.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(seen.body),
          {'child_id': 1, 'k': 3, 'interests': ['Music']});
      final a = result.activities.single;
      expect(a.activityId, 'A1');
      expect(a.myRating, 4);
      expect(a.commentCount, 2);
      expect(a.materialsNeeded, isNull);
    });

    test('turns FastAPI validation errors into readable messages', () async {
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({
                'detail': [
                  {'loc': ['body', 'birth_date'], 'msg': 'Value error, birth_date cannot be in the future'}
                ]
              }),
              422,
            )),
      );
      expect(
        () => api.createChild(ChildDraft(
            name: 'X', birthDate: DateTime(2030), interests: const [])),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message',
                'birth_date cannot be in the future')
            .having((e) => e.statusCode, 'statusCode', 422)),
      );
    });

    test('calls onUnauthorized when a signed-in request gets 401', () async {
      var called = false;
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) async =>
            http.Response(jsonEncode({'detail': 'expired'}), 401)),
      )
        ..token = 'old'
        ..onUnauthorized = () => called = true;

      await expectLater(api.listChildren(), throwsA(isA<ApiException>()));
      expect(called, isTrue);
    });

    test('reports network failures without a status code', () async {
      final api = ApiClient(
        baseUrl: 'http://api.test',
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );
      expect(
        () => api.me(),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });

    test('encodes child drafts with an ISO date', () {
      final json = ChildDraft(
        name: 'Ada',
        birthDate: DateTime(2025, 3, 7),
        interests: const ['Art'],
      ).toJson();
      expect(json['birth_date'], '2025-03-07');
    });
  });
}
