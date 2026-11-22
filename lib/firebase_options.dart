import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase client configuration is supplied at build time. These values are
/// identifiers, not server secrets. Secure access with the included rules.
class DefaultFirebaseOptions {
  static const _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const _projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const _messagingSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const _androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const _authDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');

  static bool get isConfigured => _apiKey.isNotEmpty &&
      _projectId.isNotEmpty && _messagingSenderId.isNotEmpty &&
      _storageBucket.isNotEmpty && _appIdForPlatform.isNotEmpty;

  static String get _appIdForPlatform {
    if (kIsWeb) return _webAppId;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _iosAppId;
      default:
        return _androidAppId;
    }
  }

  static FirebaseOptions get currentPlatform {
    if (!isConfigured) {
      throw StateError('Firebase build configuration is missing.');
    }
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: _appIdForPlatform,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      storageBucket: _storageBucket,
      authDomain: _authDomain.isEmpty ? null : _authDomain,
    );
  }
}
