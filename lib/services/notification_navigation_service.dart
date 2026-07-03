import 'dart:developer';

import 'package:firebase_messaging/firebase_messaging.dart';

typedef OrderNavigationCallback = void Function(String orderPath);

/// Routes notification taps to the Foodappi order screen inside the WebView.
class NotificationNavigationService {
  NotificationNavigationService._();

  static OrderNavigationCallback? onNavigateToOrder;
  static String? _pendingOrderPath;

  static void handleMessage(RemoteMessage? message) {
    if (message == null) {
      return;
    }

    final data = message.data;
    final orderId = data['order_id'];
    final urlPath = data['url_path'];

    if (urlPath != null && urlPath.isNotEmpty) {
      _navigate(urlPath);
      return;
    }

    if (orderId != null && orderId.isNotEmpty) {
      _navigate('/my-orders/$orderId');
    }
  }

  static void _navigate(String path) {
    final normalized = path.startsWith('/') ? path : '/$path';
    log('[FCM] Navigate to $normalized');
    final callback = onNavigateToOrder;
    if (callback == null) {
      _pendingOrderPath = normalized;
      return;
    }
    callback(normalized);
  }

  static String? consumePendingPath() {
    final pending = _pendingOrderPath;
    _pendingOrderPath = null;
    return pending;
  }
}
