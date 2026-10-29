import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../models/caregiver.dart';
import 'api_client.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Holds the signed-in caregiver and persists the session token securely.
class AuthService extends ChangeNotifier {
  AuthService(
    this._api, {
    FlutterSecureStorage? storage,
    GoogleSignIn? googleSignIn,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _google = googleSignIn ??
            GoogleSignIn(
              scopes: const ['email', 'profile'],
              clientId: defaultTargetPlatform == TargetPlatform.iOS &&
                      AppConfig.googleIosClientId.isNotEmpty
                  ? AppConfig.googleIosClientId
                  : null,
              serverClientId: AppConfig.googleServerClientId.isEmpty
                  ? null
                  : AppConfig.googleServerClientId,
            ) {
    _api.onUnauthorized = () => signOut();
  }

  static const _tokenKey = 'auth_token';
  static const _caregiverKey = 'auth_caregiver';

  final ApiClient _api;
  final FlutterSecureStorage _storage;
  final GoogleSignIn _google;

  AuthStatus _status = AuthStatus.unknown;
  Caregiver? _caregiver;

  AuthStatus get status => _status;
  Caregiver? get caregiver => _caregiver;

  /// Restore a saved session on app start.
  Future<void> init() async {
    String? token;
    String? cached;
    try {
      token = await _storage.read(key: _tokenKey);
      cached = await _storage.read(key: _caregiverKey);
    } catch (_) {
      // Corrupted keystore entries (e.g. after a reinstall): start fresh.
      await _clearStorage();
    }
    if (token == null) {
      _set(AuthStatus.signedOut, null);
      return;
    }

    _api.token = token;
    try {
      _set(AuthStatus.signedIn, await _api.me());
    } on ApiException catch (e) {
      if (e.isNetworkError && cached != null) {
        // Offline: trust the cached profile; requests will retry later.
        _set(AuthStatus.signedIn,
            Caregiver.fromJson(jsonDecode(cached) as Map<String, dynamic>));
      } else {
        await signOut();
      }
    }
  }

  Future<void> signIn(String email, String password) async =>
      _startSession(await _api.login(email.trim(), password));

  Future<void> register(String name, String email, String password) async =>
      _startSession(await _api.register(name.trim(), email.trim(), password));

  /// Returns false if the user closed the Google account picker.
  Future<bool> signInWithGoogle() async {
    final GoogleSignInAccount? account;
    try {
      account = await _google.signIn();
    } on PlatformException catch (e) {
      throw ApiException(
          'Google sign-in failed (${e.code}). Check the Google OAuth setup.');
    }
    if (account == null) return false;

    final idToken = (await account.authentication).idToken;
    if (idToken == null) {
      await _google.signOut();
      throw const ApiException(
          'Google did not return an ID token. Set GOOGLE_SERVER_CLIENT_ID.');
    }
    try {
      await _startSession(await _api.loginWithGoogle(idToken));
    } catch (_) {
      await _google.signOut();
      rethrow;
    }
    return true;
  }

  Future<void> signOut() async {
    _api.token = null;
    await _clearStorage();
    try {
      await _google.signOut();
    } catch (_) {
      // Not signed in with Google, or plugin unavailable: nothing to undo.
    }
    _set(AuthStatus.signedOut, null);
  }

  Future<void> _startSession(AuthSession session) async {
    _api.token = session.accessToken;
    await _storage.write(key: _tokenKey, value: session.accessToken);
    await _storage.write(
        key: _caregiverKey, value: jsonEncode(session.caregiver.toJson()));
    _set(AuthStatus.signedIn, session.caregiver);
  }

  Future<void> _clearStorage() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _caregiverKey);
    } catch (_) {}
  }

  void _set(AuthStatus status, Caregiver? caregiver) {
    _status = status;
    _caregiver = caregiver;
    notifyListeners();
  }
}
