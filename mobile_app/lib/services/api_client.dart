import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/activity.dart';
import '../models/caregiver.dart';
import '../models/child_profile.dart';
import '../models/feedback.dart';

/// An error the UI can show to the user as-is.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;

  /// HTTP status, or null when the server could not be reached.
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetworkError => statusCode == null;

  @override
  String toString() => message;
}

/// Thin typed wrapper around the FastAPI backend (backend/Api.py).
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _http;
  final String baseUrl;

  /// Bearer token for the signed-in caregiver, set by AuthService.
  String? token;

  /// Called when an authenticated request comes back 401 (expired session).
  void Function()? onUnauthorized;

  static const _timeout = Duration(seconds: 30);

  Future<dynamic> _send(String method, String path, {Object? body}) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on SocketException {
      throw const ApiException(
          'Could not reach the server. Check your connection.');
    } on http.ClientException {
      throw const ApiException(
          'Could not reach the server. Check your connection.');
    }

    final text = utf8.decode(response.bodyBytes);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return text.isEmpty ? null : jsonDecode(text);
    }
    if (response.statusCode == 401 && token != null) onUnauthorized?.call();
    throw ApiException(_errorMessage(text, response.statusCode),
        statusCode: response.statusCode);
  }

  /// FastAPI errors look like {"detail": "..."} or, for validation errors,
  /// {"detail": [{"msg": "...", "loc": [...]}, ...]}.
  static String _errorMessage(String body, int status) {
    try {
      final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        return detail
            .map((e) => (e as Map<String, dynamic>)['msg'].toString())
            .map((m) => m.replaceFirst('Value error, ', ''))
            .join('\n');
      }
    } catch (_) {
      // Not JSON; fall through to a generic message.
    }
    return 'Request failed ($status).';
  }

  // ------------------------------------------------------------------ auth
  Future<AuthSession> register(String name, String email, String password) async =>
      AuthSession.fromJson(await _send('POST', '/auth/register',
          body: {'name': name, 'email': email, 'password': password}));

  Future<AuthSession> login(String email, String password) async =>
      AuthSession.fromJson(await _send('POST', '/auth/login',
          body: {'email': email, 'password': password}));

  Future<AuthSession> loginWithGoogle(String idToken) async =>
      AuthSession.fromJson(
          await _send('POST', '/auth/google', body: {'id_token': idToken}));

  Future<Caregiver> me() async =>
      Caregiver.fromJson(await _send('GET', '/auth/me'));

  // -------------------------------------------------------------- children
  Future<List<ChildProfile>> listChildren() async =>
      (await _send('GET', '/children') as List)
          .map((e) => ChildProfile.fromJson(e as Map<String, dynamic>))
          .toList();

  Future<ChildProfile> createChild(ChildDraft draft) async =>
      ChildProfile.fromJson(
          await _send('POST', '/children', body: draft.toJson()));

  Future<ChildProfile> updateChild(int childId, ChildDraft draft) async =>
      ChildProfile.fromJson(
          await _send('PUT', '/children/$childId', body: draft.toJson()));

  Future<void> deleteChild(int childId) =>
      _send('DELETE', '/children/$childId');

  // ------------------------------------------------------- recommendations
  Future<RecommendationResult> recommend(
    int childId, {
    int k = 5,
    List<String>? interests,
  }) async =>
      RecommendationResult.fromJson(await _send('POST', '/recommend', body: {
        'child_id': childId,
        'k': k,
        if (interests != null) 'interests': interests,
      }));

  // -------------------------------------------------------------- feedback
  String _activityPath(int childId, String activityId) =>
      '/children/$childId/activities/${Uri.encodeComponent(activityId)}';

  Future<ActivityFeedback> getFeedback(int childId, String activityId) async =>
      ActivityFeedback.fromJson(await _send(
          'GET', '${_activityPath(childId, activityId)}/feedback'));

  Future<void> rateActivity(int childId, String activityId, int rating) =>
      _send('PUT', '${_activityPath(childId, activityId)}/rating',
          body: {'rating': rating});

  Future<void> clearRating(int childId, String activityId) =>
      _send('DELETE', '${_activityPath(childId, activityId)}/rating');

  Future<ActivityComment> addComment(
          int childId, String activityId, String body) async =>
      ActivityComment.fromJson(await _send(
          'POST', '${_activityPath(childId, activityId)}/comments',
          body: {'body': body}));

  Future<void> deleteComment(int commentId) =>
      _send('DELETE', '/comments/$commentId');
}
