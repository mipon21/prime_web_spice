import 'dart:developer';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:prime_web/services/notification_navigation_service.dart';
import 'package:prime_web/utils/constants.dart';

@pragma('vm:entry-point')
Future<void> onBackgroundMessageLocal(NotificationResponse message) async {
  await Firebase.initializeApp();
}

class FirebaseInitialize {
  final _firebaseMessaging = FirebaseMessaging.instance;
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;
  late AndroidNotificationChannel channel;

  Future<void> initFirebaseState(BuildContext context) async {
    channel = const AndroidNotificationChannel(
      'order_notifications',
      'Order updates',
      description: 'Order status and delivery notifications',
      importance: Importance.high,
    );

    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    final initializationSettingsDarwin = DarwinInitializationSettings(
      requestBadgePermission: false,
      onDidReceiveLocalNotification:
          (int id, String? title, String? body, String? payload) async {},
      notificationCategories: [],
    );
    final initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    Future<void> onSelectNotification(String? payload) async {
      if (payload != null && payload.isNotEmpty) {
        NotificationNavigationService.onNavigateToOrder?.call(payload);
      }
    }

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse notificationResponse) {
        switch (notificationResponse.notificationResponseType) {
          case NotificationResponseType.selectedNotification:
            onSelectNotification(notificationResponse.payload);
          case NotificationResponseType.selectedNotificationAction:
            break;
        }
      },
      onDidReceiveBackgroundNotificationResponse: onBackgroundMessageLocal,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    Future<void> generateSimpleNotification(
      String title,
      String msg, {
      String? payload,
    }) async {
      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: notificationIcon,
      );

      final platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: const DarwinNotificationDetails(),
      );
      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        msg,
        platformChannelSpecifics,
        payload: payload,
      );
    }

    Future<String> downloadAndSaveFile(String url, String fileName) async {
      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final response = await http.get(Uri.parse(url));
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    }

    Future<void> generateImageNotification(
      String title,
      String msg,
      String image, {
      String? payload,
    }) async {
      final largeIconPath = await downloadAndSaveFile(image, 'largeIcon');
      final bigPicturePath = await downloadAndSaveFile(image, 'bigPicture');
      final bigPictureStyleInformation = BigPictureStyleInformation(
        FilePathAndroidBitmap(bigPicturePath),
        hideExpandedLargeIcon: true,
        contentTitle: title,
        htmlFormatContentTitle: true,
        summaryText: msg,
        htmlFormatSummaryText: true,
      );
      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: notificationIcon,
        largeIcon: FilePathAndroidBitmap(largeIconPath),
        styleInformation: bigPictureStyleInformation,
      );

      final platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);
      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        msg,
        platformChannelSpecifics,
        payload: payload,
      );
    }

    String? payloadFromMessage(RemoteMessage message) {
      final urlPath = message.data['url_path'];
      if (urlPath != null && urlPath.isNotEmpty) {
        return urlPath;
      }
      final orderId = message.data['order_id'];
      if (orderId != null && orderId.isNotEmpty) {
        return '/my-orders/$orderId';
      }
      return null;
    }

    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      NotificationNavigationService.handleMessage(initialMessage);
    }

    await _firebaseMessaging.getToken().then((value) {
      log('FCM token==$value');
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('${message.toMap()}');

      final notification = message.notification;
      final title = notification?.title ?? message.data['title'] ?? '';
      final body = notification?.body ?? message.data['body'] ?? '';
      final payload = payloadFromMessage(message);
      var image = '';

      if (notification != null) {
        image = defaultTargetPlatform == TargetPlatform.android
            ? notification.android?.imageUrl ?? ''
            : notification.apple?.imageUrl ?? '';
      }

      if (image.isNotEmpty) {
        generateImageNotification(title, body, image, payload: payload);
      } else {
        generateSimpleNotification(title, body, payload: payload);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      NotificationNavigationService.handleMessage(message);
    });
  }
}
