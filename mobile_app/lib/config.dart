import 'package:flutter/foundation.dart';

/// Build-time configuration, passed with `--dart-define`:
///
///   flutter run \
///     --dart-define=API_BASE_URL=http://192.168.1.20:8000 \
///     --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com \
///     --dart-define=GOOGLE_IOS_CLIENT_ID=yyyy.apps.googleusercontent.com
class AppConfig {
  static const _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// The OAuth "Web application" client ID. Google issues the ID token for
  /// this audience, and the backend must list it in GOOGLE_CLIENT_IDS.
  static const googleServerClientId =
      String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// The OAuth "iOS" client ID (only needed when running on iOS).
  static const googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Where the FastAPI backend lives. The defaults reach a backend running on
  /// the development machine from an emulator or simulator.
  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) return _apiBaseUrl;
    // The Android emulator reaches the host machine at 10.0.2.2.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }
    return 'http://localhost:8000';
  }
}
