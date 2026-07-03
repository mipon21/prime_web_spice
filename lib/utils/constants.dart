import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prime_web/cubit/get_setting_cubit.dart';
import 'package:prime_web/utils/icons.dart';

export '../ui/styles/colors.dart';
export 'icons.dart';
export 'strings.dart';

const String androidPackageName = 'com.spice.box.skylonit';

/// DO NOT ADD / AT THE END OF URL
String baseurl = 'https://app.spiceboxscunthorpe.com';

String databaseUrl = '$baseurl/api/';

/// Foodappi Laravel API (single source of truth for transactional push).
/// Set to your Foodappi public URL — often the same host as the WebView site.
String foodappiBaseUrl = "https://spiceboxscunthorpe.co.uk";

String foodappiApiUrl = '$foodappiBaseUrl/api/';

/// Must match Foodappi `.env` → `VITE_API_KEY` / `config('app.vite_api_key')`.
String foodappiApiKey = 'ht8vvd2m-x89z-lc00-asoa-8vegh6mzjlyo';

const appName = 'SPICE BOX';

// Here is for only reference you have to change it from panel

String webInitialUrl = '';

//Force Update
String forceUpdatee = '1.0.0'; //OFF

String message = '';
final shareAppMessage = '$message : $storeUrl';

String storeUrl = Platform.isAndroid ? '' : '';

bool showBottomNavigationBar = true;

/// Ad Ids
String interstitialAdId = Platform.isAndroid ? '' : '';
String bannerAdId = Platform.isAndroid ? '' : '';
String openAdId = Platform.isAndroid ? '' : '';

//icon to set when get firebase messages
const String notificationIcon = '@mipmap/launcher_icon';

//turn on/off enable storage permission
const bool isStoragePermissionEnabled = true;

List<Map<String, String>> navigationTabs(BuildContext context) => [
      {
        'url': context.read<GetSettingCubit>().primaryUrl(),
        'label': context.read<GetSettingCubit>().firstBottomNavWeb(),
        'icon': CustomIcons.homeIcon(Theme.of(context).brightness),
      },
      {
        'url': context.read<GetSettingCubit>().secondaryUrl(),
        'label': context.read<GetSettingCubit>().secondBottomNavWeb(),
        'icon': CustomIcons.demoIcon(Theme.of(context).brightness),
      },
    ];
