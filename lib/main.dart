import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:prime_web/firebase_options.dart';
import 'package:prime_web/services/fcm_background_handler.dart';
import 'package:prime_web/services/foodappi_fcm_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prime_web/cubit/fcm_cubit.dart';
import 'package:prime_web/cubit/get_onboarding_cubit.dart';
import 'package:prime_web/cubit/get_setting_cubit.dart';
import 'package:prime_web/provider/navigation_bar_provider.dart';
import 'package:prime_web/provider/theme_provider.dart';
import 'package:prime_web/ui/screens/setting_screens/settings_screen.dart';
import 'package:prime_web/ui/screens/splash_screen.dart';
import 'package:prime_web/ui/widgets/admob_service.dart';
import 'package:prime_web/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final navigatorKey = GlobalKey<NavigatorState>();
late SharedPreferences pref;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pref = await SharedPreferences.getInstance();

  await SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top],
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,

    /// NOTE: Uncomment below 2 lines to enable landscape mode
    // DeviceOrientation.landscapeLeft,
    // DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  unawaited(FoodappiFcmService.initialize().catchError((e) {
    print('[FCM] Background initialization error: $e');
  }));
  AdMobService.initialize();

  await SharedPreferences.getInstance().then((prefs) {
    final bool isDarkTheme;
    if (prefs.getBool('isDarkTheme') ?? ThemeMode.system == ThemeMode.dark) {
      isDarkTheme = true;
    } else {
      isDarkTheme = false;
    }

    return runApp(
      ChangeNotifierProvider<ThemeProvider>(
        child: const MyApp(),
        create: (BuildContext context) {
          return ThemeProvider(isDarkTheme: isDarkTheme);
        },
      ),
    );
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NavigationBarProvider>(
          create: (_) => NavigationBarProvider(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, value, child) {
          return MultiProvider(
            providers: [
              BlocProvider(
                create: (context) => GetSettingCubit(),
              ),
              BlocProvider(
                create: (context) => GetOnboardingCubit(),
              ),
              BlocProvider(
                create: (context) => SetFcmCubit(),
              ),
            ],
            child: MaterialApp(
              title: appName,
              debugShowCheckedModeBanner: false,
              themeMode: value.getTheme(),
              theme: AppThemes.lightTheme,
              darkTheme: AppThemes.darkTheme,
              navigatorKey: navigatorKey,
              onGenerateRoute: (RouteSettings settings) {
                return switch (settings.name) {
                  'settings' => CupertinoPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  _ => null,
                };
              },
              home: const SplashScreen(),
            ),
          );
        },
      ),
    );
  }
}
