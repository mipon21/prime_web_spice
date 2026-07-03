import 'dart:developer';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:prime_web/services/foodappi_api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Registers and maintains FCM tokens against the Foodappi Laravel API.
class FoodappiFcmService {
  FoodappiFcmService._();

  static const _guestSessionKey = 'foodappi_guest_session';
  static const _lastFcmTokenKey = 'foodappi_last_fcm_token';
  static const _lastAuthTokenKey = 'foodappi_last_auth_token';

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    await _ensureGuestSession();
    await registerCurrentToken();

    _messaging.onTokenRefresh.listen((token) async {
      log('[FCM] Token refreshed.');
      await _persistAndUpload(token);
    });
  }

  static Future<String> guestSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    var session = prefs.getString(_guestSessionKey);
    if (session == null || session.isEmpty) {
      session = const Uuid().v4();
      await prefs.setString(_guestSessionKey, session);
    }
    return session;
  }

  static Future<void> registerCurrentToken({String? authToken}) async {
    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _persistAndUpload(token, authToken: authToken);
  }

  static Future<void> onAuthChanged({
    required bool loggedIn,
    String? authToken,
  }) async {
    if (loggedIn && authToken != null && authToken.isNotEmpty) {
      await registerCurrentToken(authToken: authToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastAuthTokenKey, authToken);
      return;
    }

    await unregisterCurrentToken(authToken: await _lastStoredAuthToken());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastAuthTokenKey);
    await registerCurrentToken();
  }

  static Future<void> unregisterCurrentToken({String? authToken}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_lastFcmTokenKey);
    if (token == null || token.isEmpty) {
      return;
    }

    try {
      if (authToken != null && authToken.isNotEmpty) {
        await FoodappiApiClient.delete(
          'frontend/device-token',
          queryParameters: {'token': token},
          bearerToken: authToken,
        );
      }
    } catch (e, st) {
      log('[FCM] Failed to remove token on logout: $e', stackTrace: st);
    }
  }

  static Future<String?> _lastStoredAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastAuthTokenKey);
  }

  static Future<void> _ensureGuestSession() async {
    await guestSessionId();
  }

  static Future<void> _persistAndUpload(
    String token, {
    String? authToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastFcmTokenKey, token);

    final guestSession = await guestSessionId();
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : 'unknown';

    try {
      if (authToken != null && authToken.isNotEmpty) {
        await FoodappiApiClient.post(
          'frontend/device-token/mobile',
          bearerToken: authToken,
          body: {
            'token': token,
            'platform': platform,
            'guest_session': guestSession,
          },
        );
        log('[FCM] Token registered for authenticated user.');
      } else {
        await FoodappiApiClient.post(
          'frontend/device-token/guest',
          body: {
            'token': token,
            'platform': platform,
            'guest_session': guestSession,
          },
        );
        log('[FCM] Token registered for guest session.');
      }
    } catch (e, st) {
      log('[FCM] Token upload failed: $e', stackTrace: st);
    }
  }
}
