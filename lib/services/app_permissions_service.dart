import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests native permissions on app startup and exposes helpers for WebView.
class AppPermissionsService {
  AppPermissionsService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Call once when the home screen loads (same timing as notifications).
  static Future<void> requestStartupPermissions() async {
    await requestNotificationPermissions();
    await requestLocationPermissions();
  }

  static Future<void> requestNotificationPermissions() async {
    await _messaging.requestPermission();

    if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  static Future<void> requestLocationPermissions() async {
    if (Platform.isIOS) {
      await Permission.locationWhenInUse.request();
      return;
    }

    await Permission.locationWhenInUse.request();
    await Permission.location.request();
  }

  static Future<bool> isLocationGranted() async {
    final whenInUse = await Permission.locationWhenInUse.status;
    if (whenInUse.isGranted || whenInUse.isLimited) {
      return true;
    }

    final location = await Permission.location.status;
    return location.isGranted || location.isLimited;
  }

  /// Ensures location is granted; requests again if the user denied at startup.
  static Future<bool> ensureLocationForWebView() async {
    if (await isLocationGranted()) {
      return true;
    }
    await requestLocationPermissions();
    return isLocationGranted();
  }
}
