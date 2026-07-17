import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:prime_web/cubit/get_setting_cubit.dart';
import 'package:prime_web/provider/navigation_bar_provider.dart';
import 'package:prime_web/provider/theme_provider.dart';
import 'package:prime_web/services/app_permissions_service.dart';
import 'package:prime_web/services/foodappi_fcm_service.dart';
import 'package:prime_web/services/notification_navigation_service.dart';
import 'package:prime_web/ui/widgets/widgets.dart';
import 'package:prime_web/utils/constants.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class LoadWebView extends StatefulWidget {
  const LoadWebView({this.url = '', super.key});

  final String url;

  @override
  State<LoadWebView> createState() => _LoadWebViewState();
}

class _LoadWebViewState extends State<LoadWebView>
    with SingleTickerProviderStateMixin {
  final webViewKey = GlobalKey();

  late PullToRefreshController _pullToRefreshController;
  CookieManager cookieManager = CookieManager.instance();
  InAppWebViewController? webViewController;
  double progress = 0;
  String url = '';
  int _previousScrollY = 0;
  bool isLoading = false;
  bool showErrorPage = false;
  bool slowInternetPage = false;
  bool noInternet = false;
  late Animation<double> animation;
  final expiresDate =
      DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch;
  List<ConnectivityResult> _connectionStatus = [ConnectivityResult.none];
  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  bool _validURL = false;
  bool canGoBack = false;
  bool _appLaunchPromoSignaled = false;
  String? _lastSyncedAuthToken;
  String? _printRestoreUrl;
  String? _pendingOrderPath;
  Timer? _authSyncTimer;

  @override
  void initState() {
    super.initState();
    NotificationNavigationService.onNavigateToOrder = _navigateToOrderPath;
    NoInternet.initConnectivity().then(
      (value) => setState(() {
        _connectionStatus = value;
      }),
    );
    _connectivitySubscription = _connectivity.onConnectivityChanged
        .listen((List<ConnectivityResult> result) {
      NoInternet.updateConnectionStatus(result).then((value) {
        _connectionStatus = value;
        if (_connectionStatus != [ConnectivityResult.none]) {
          setState(() {
            noInternet = false;
            webViewController?.reload();
          });
        }
      });
    });

    try {
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
            color: context.read<GetSettingCubit>().loadercolor()),
        onRefresh: () async {
          await webViewController!.loadUrl(
            urlRequest: URLRequest(url: await webViewController!.getUrl()),
          );
        },
      );
    } catch (e, stackTrace) {
      log('Error initializing PullToRefreshController: $e');
      log('StackTrace: $stackTrace');
    }

    context.read<ThemeProvider>().addListener(() {
      webViewController!.reload();
    });
  }

  @override
  void setState(fn) {
    if (mounted) super.setState(fn);
  }

  @override
  void dispose() {
    _authSyncTimer?.cancel();
    if (NotificationNavigationService.onNavigateToOrder ==
        _navigateToOrderPath) {
      NotificationNavigationService.onNavigateToOrder = null;
    }
    _connectivitySubscription.cancel();
    webViewController = null;
    super.dispose();
  }

  void _navigateToOrderPath(String path) {
    if (webViewController == null) {
      _pendingOrderPath = path;
      return;
    }

    final normalizedPath = path.startsWith('/') ? path : '/$path';
    _openOrderPathInWebView(normalizedPath);
  }

  Future<void> _flushPendingOrderNavigation() async {
    final pending =
        _pendingOrderPath ?? NotificationNavigationService.consumePendingPath();

    if (pending == null || pending.isEmpty) {
      return;
    }

    _pendingOrderPath = null;
    _navigateToOrderPath(pending);
  }

  Future<void> _openOrderPathInWebView(String normalizedPath) async {
    final controller = webViewController;
    if (controller == null) {
      _pendingOrderPath = normalizedPath;
      return;
    }

    // Prefer the in-page bridge added by the Laravel/Vue app. It routes without
    // reloading the WebView and also handles the logged-out case by stashing the
    // pending order until after login.
    try {
      final handled = await controller.evaluateJavascript(
        source: '''
          (function() {
            var path = ${jsonEncode(normalizedPath)};
            if (typeof window.__primeDeepLink === 'function') {
              window.__primeDeepLink(path);
              return true;
            }
            try {
              localStorage.setItem('prime_pending_deep_link', path);
            } catch (e) {}
            return false;
          })();
        ''',
      );

      if (handled == true || handled?.toString() == 'true') {
        return;
      }
    } catch (e, stackTrace) {
      log('Prime deep-link bridge failed: $e', stackTrace: stackTrace);
    }

    final baseUri = Uri.tryParse(widget.url);
    if (baseUri == null) {
      _pendingOrderPath = normalizedPath;
      return;
    }

    final basePath = baseUri.path.endsWith('/')
        ? baseUri.path.substring(0, baseUri.path.length - 1)
        : baseUri.path;
    final appBasePath = basePath.endsWith('/home')
        ? basePath.substring(0, basePath.length - '/home'.length)
        : basePath;

    final target = baseUri.replace(
      path: '$appBasePath$normalizedPath'.replaceAll('//', '/'),
      queryParameters: {
        'prime_deep_link': normalizedPath,
      },
    );

    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(target.toString())),
    );
  }

  Future<void> _restorePageAfterPrint(InAppWebViewController controller) async {
    final restoreUrl = _printRestoreUrl;
    _printRestoreUrl = null;
    if (restoreUrl == null || restoreUrl.isEmpty) {
      return;
    }

    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(restoreUrl)),
    );
  }

  Future<Map<String, bool>> _handlePrintReceipt(
    InAppWebViewController controller,
    List<dynamic> arguments,
  ) async {
    try {
      final html = arguments.isNotEmpty ? arguments.first?.toString() : null;
      if (html == null || html.isEmpty) {
        await controller.printCurrentPage();
        return {'ok': false};
      }

      final currentUrl = (await controller.getUrl())?.toString() ?? widget.url;
      _printRestoreUrl = currentUrl;

      await controller.loadData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf8',
        baseUrl: WebUri(currentUrl),
        historyUrl: WebUri(currentUrl),
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));

      final printJob = await controller.printCurrentPage();
      if (printJob != null) {
        printJob.onComplete = (bool completed, String? error) async {
          await _restorePageAfterPrint(controller);
        };
      } else {
        await Future<void>.delayed(const Duration(seconds: 2));
        await _restorePageAfterPrint(controller);
      }

      return {'ok': true};
    } catch (e, stackTrace) {
      log('primePrintReceipt failed: $e');
      log('StackTrace: $stackTrace');
      await _restorePageAfterPrint(controller);
      return {'ok': false};
    }
  }

  Future<void> _syncAuthFromWebView() async {
    if (webViewController == null) {
      return;
    }

    try {
      final raw = await webViewController!.evaluateJavascript(
        source: '''
          (function() {
            try {
              var stored = localStorage.getItem('vuex');
              if (!stored) return JSON.stringify({loggedIn:false, token:null});
              var data = JSON.parse(stored);
              var token = data.auth && data.auth.authToken ? data.auth.authToken : null;
              return JSON.stringify({loggedIn: !!token, token: token});
            } catch (e) {
              return JSON.stringify({loggedIn:false, token:null});
            }
          })();
        ''',
      );

      if (raw == null) {
        return;
      }

      var jsonString = raw.toString();
      if (jsonString.startsWith('"') && jsonString.endsWith('"')) {
        jsonString = jsonString.substring(1, jsonString.length - 1);
        jsonString = jsonString.replaceAll(r'\"', '"');
      }

      final loggedIn = jsonString.contains('"loggedIn":true') ||
          jsonString.contains('"loggedIn": true');
      final tokenMatch = RegExp(r'"token":"([^"]+)"').firstMatch(jsonString);
      final token = tokenMatch?.group(1);

      if (token != null && token.isNotEmpty && token != _lastSyncedAuthToken) {
        _lastSyncedAuthToken = token;
        await FoodappiFcmService.onAuthChanged(
          loggedIn: true,
          authToken: token,
        );
        return;
      }

      if (!loggedIn && _lastSyncedAuthToken != null) {
        await FoodappiFcmService.onAuthChanged(loggedIn: false);
        _lastSyncedAuthToken = null;
      }
    } catch (e, stackTrace) {
      log('Auth sync from WebView failed: $e');
      log('StackTrace: $stackTrace');
    }
  }

  void _startAuthSync() {
    _authSyncTimer?.cancel();
    _authSyncTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _syncAuthFromWebView(),
    );
    _syncAuthFromWebView();
  }

  final _inAppWebViewSettings = InAppWebViewSettings(
    useShouldOverrideUrlLoading: true,
    mediaPlaybackRequiresUserGesture: false,
    useOnDownloadStart: true,
    javaScriptCanOpenWindowsAutomatically: true,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    transparentBackground: true,
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
    allowsInlineMediaPlayback: true,
    geolocationEnabled: true,
  );
  @override
  Widget build(BuildContext context) {
    _validURL = Uri.tryParse(widget.url)?.isAbsolute ?? false;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, __) async {
        if (didPop) return;
        if (await _exitApp(context)) {
          context.read<GetSettingCubit>().showExitPopupScreen()
              ? showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Do you want to exit app?'),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text('No'),
                      ),
                      TextButton(
                        onPressed: () async {
                          SystemNavigator.pop();
                        },
                        child: const Text('Yes'),
                      ),
                    ],
                  ),
                )
              : SystemNavigator.pop();
        }
      },
      child: Stack(
        children: [
          if (_validURL)
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: _inAppWebViewSettings,
              pullToRefreshController:
                  context.read<GetSettingCubit>().pullToRefresh()
                      ? _pullToRefreshController
                      : null,
              gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              },
              onWebViewCreated: (controller) async {
                webViewController = controller;
                _startAuthSync();

                controller.addJavaScriptHandler(
                  handlerName: 'primePrintReceipt',
                  callback: (arguments) =>
                      _handlePrintReceipt(controller, arguments),
                );

                await cookieManager.setCookie(
                  url: WebUri(widget.url),
                  name: 'myCookie',
                  value: 'myValue',
                  // domain: ".flutter.dev",
                  expiresDate: expiresDate,
                  isHttpOnly: false,
                  isSecure: true,
                );

                await _flushPendingOrderNavigation();
              },
              onScrollChanged: (controller, x, y) async {
                final currentScrollY = y;
                final animationController =
                    context.read<NavigationBarProvider>().animationController;

                if (currentScrollY > _previousScrollY) {
                  _previousScrollY = currentScrollY;
                  if (!animationController.isAnimating) {
                    await animationController.forward();
                  }
                } else {
                  _previousScrollY = currentScrollY;

                  if (!animationController.isAnimating) {
                    await animationController.reverse();
                  }
                }
              },
              onLoadStart: (controller, url) async {
                setState(() {
                  isLoading = true;
                  progress = 0;
                  showErrorPage = false;
                  slowInternetPage = false;
                  this.url = url.toString();
                });
              },
              onPrintRequest: (controller, url, printJobController) async {
                return false;
              },
              onLoadStop: (controller, url) async {
                await _pullToRefreshController.endRefreshing();
                await _syncAuthFromWebView();

                setState(() {
                  this.url = url.toString();
                  if (progress >= 0.95 || progress == 0) {
                    isLoading = false;
                  }
                });

                await webViewController!.evaluateJavascript(
                  source: '''
                    window.__PRIME_WEB__ = true;
                    document.body.classList.add('prime-web-view');
                  ''',
                );

                await _flushPendingOrderNavigation();

                if (!_appLaunchPromoSignaled) {
                  _appLaunchPromoSignaled = true;
                  await webViewController!.evaluateJavascript(
                    source: '''
                      try {
                        sessionStorage.removeItem('promo_banner_shown');
                        sessionStorage.setItem('prime_app_launch', String(Date.now()));
                        window.dispatchEvent(new CustomEvent('prime-app-launch'));
                      } catch (e) {}
                    ''',
                  );
                }
                final mode = context.read<ThemeProvider>().isDarkMode
                    ? "\'dark\'"
                    : "\'light\'";
                final themeChange = """
                  let meta = document.querySelector('meta[name="color-scheme"]');
                  if (meta) {
                  meta.setAttribute('content', $mode); 
                  } else {
                  meta = document.createElement('meta');
                  meta.name = 'color-scheme';
                  meta.content = $mode;
                  document.head.appendChild(meta);
                  }""";
                await webViewController!
                    .evaluateJavascript(source: themeChange);

                // Removes header and footer from page
                if (context.read<GetSettingCubit>().hideHeader()) {
                  await webViewController!
                      .evaluateJavascript(
                        source:
                            "javascript:(function() { var head = document.getElementsByTagName('header')[0];head.parentNode.removeChild(head);})()",
                      )
                      .then(
                        (_) => debugPrint(
                          'Page finished loading Javascript',
                        ),
                      )
                      .catchError((Object e) => debugPrint('$e'));
                }

                if (context.read<GetSettingCubit>().hideFooter()) {
                  await webViewController!
                      .evaluateJavascript(
                        source:
                            "javascript:(function() { var footer = document.getElementsByTagName('footer')[0];footer.parentNode.removeChild(footer);})()",
                      )
                      .then(
                        (_) => debugPrint(
                          'Page finished loading Javascript',
                        ),
                      )
                      .catchError((Object e) => debugPrint('$e'));
                }
              },
              onReceivedError: (controller, request, error) async {
                print("onReceivedError Hear.......${error}");
                await _pullToRefreshController.endRefreshing();
                setState(() {
                  isLoading = false;
                  print('${request.url.origin} - ${widget.url}');
                  if (request.url.origin == widget.url &&
                      (error.type == WebResourceErrorType.HOST_LOOKUP ||
                          error.description == 'net::ERR_NAME_NOT_RESOLVED' ||
                          error.description == 'net::ERR_CONNECTION_CLOSED')) {
                    slowInternetPage = true;
                    return;
                  }
                  if (error.type ==
                          WebResourceErrorType.NOT_CONNECTED_TO_INTERNET ||
                      error.description == 'net::ERR_INTERNET_DISCONNECTED') {
                    noInternet = true;
                    return;
                  }
                });
              },
              onReceivedHttpError: (controller, request, response) {
                _pullToRefreshController.endRefreshing();
                print('=====${response}'); //

                final url = request.url.toString();
                final contentType = response.contentType ?? '';
                final statusCode = response.statusCode;

                if (statusCode == 400 &&
                    !(request.isForMainFrame ?? false) &&
                    contentType.contains("text/html") &&
                    url.contains("cspreport")) {
                  print("Silently ignoring CSP violation report: $url");
                  return;
                }
                if ([100, 299].contains(response.statusCode) ||
                    [400, 599].contains(response.statusCode)) {
                  setState(() {
                    showErrorPage = true;
                    isLoading = false;
                  });
                }
              },
              onReceivedServerTrustAuthRequest: (controller, challenge) async {
                return ServerTrustAuthResponse(
                  action: ServerTrustAuthResponseAction.PROCEED,
                );
              },
              onGeolocationPermissionsShowPrompt: (controller, origin) async {
                final granted =
                    await AppPermissionsService.ensureLocationForWebView();
                return GeolocationPermissionShowPromptResponse(
                  origin: origin,
                  allow: granted,
                  retain: granted,
                );
              },
              onPermissionRequest: (controller, request) async {
                final resources = <PermissionResourceType>[];
                bool needsLocation = false;

                for (final element in request.resources) {
                  if (element == PermissionResourceType.GEOLOCATION ||
                      element.toString().contains('GEOLOCATION')) {
                    needsLocation = true;
                    resources.add(element);
                  }
                }

                if (needsLocation) {
                  await AppPermissionsService.ensureLocationForWebView();
                }

                return PermissionResponse(
                  action: resources.isNotEmpty
                      ? PermissionResponseAction.GRANT
                      : PermissionResponseAction.DENY,
                  resources: resources,
                );
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  if (progress == 100) {
                    _pullToRefreshController.endRefreshing();
                    isLoading = false;
                  }
                  this.progress = progress / 100;
                });
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                var url = navigationAction.request.url.toString();
                final uri = Uri.parse(url);

                if (Platform.isIOS && url.contains('geo')) {
                  url = url.replaceFirst(
                    'geo://',
                    'http://maps.apple.com/',
                  );
                } else if (url.contains('tel:') ||
                    url.contains('mailto:') ||
                    url.contains('play.google.com') ||
                    url.contains('maps') ||
                    url.contains('messenger.com')) {
                  url = Uri.encodeFull(url);
                  try {
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    } else {
                      await launchUrl(uri);
                    }
                    return NavigationActionPolicy.CANCEL;
                  } catch (e) {
                    await launchUrl(uri);
                    return NavigationActionPolicy.CANCEL;
                  }
                } else if (![
                  'http',
                  'https',
                  'file',
                  'chrome',
                  'data',
                  'javascript',
                ].contains(uri.scheme)) {
                  if (await canLaunchUrl(uri)) {
                    // Launch the App
                    await launchUrl(
                      uri,
                    );
                    // and cancel the request
                    return NavigationActionPolicy.CANCEL;
                  }
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCloseWindow: (controller) async {},
              onDownloadStartRequest:
                  (controller, onDownloadStartRequest) async {
                  final url = onDownloadStartRequest.url.toString();

                  try {
                    final dio = Dio();
                    String fileName;
                    if (url.lastIndexOf('?') > 0) {
                      fileName = url.substring(
                        url.lastIndexOf('/') + 1,
                        url.lastIndexOf('?'),
                      );
                    } else {
                      fileName = url.substring(
                        url.lastIndexOf('/') + 1,
                      );
                    }
                    final savePath = await getFilePath(fileName);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Downloading file..'),
                      ),
                    );
                    await dio.download(
                      url,
                      savePath,
                      onReceiveProgress: (rec, total) {},
                    );

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Download Complete'),
                      ),
                    );
                  } on Exception catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Downloading failed'),
                      ),
                    );
                  }
              },
              onUpdateVisitedHistory: (controller, url, androidIsReload) async {
                print(
                    '************************$url - $androidIsReload****************************');
                setState(() {
                  this.url = url.toString();
                });
              },
            )
          else
            Center(
              child: Text(
                'Url is not valid',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          if (isLoading)
            if (Platform.isIOS)
              Center(
                child: CupertinoActivityIndicator(
                  radius: 18,
                  color: context.read<GetSettingCubit>().loadercolor(),
                ),
              )
            else
              Center(
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: context.read<GetSettingCubit>().loadercolor(),
                ),
              )
          else
            const SizedBox.shrink(),
          if (noInternet)
            const Center(
              child: NoInternetWidget(),
            )
          else
            const SizedBox.shrink(),
          if (showErrorPage)
            Center(
              child: NotFound(
                webViewController: webViewController!,
                url: url,
                title1: CustomStrings.pageNotFound1,
                title2: CustomStrings.pageNotFound2,
              ),
            )
          else
            const SizedBox.shrink(),
          if (slowInternetPage)
            Center(
              child: NotFound(
                webViewController: webViewController!,
                url: url,
                title1: CustomStrings.incorrectURL1,
                title2: CustomStrings.incorrectURL2,
              ),
            )
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  Future<bool> _exitApp(BuildContext context) async {
    if (mounted) {
      await context.read<NavigationBarProvider>().animationController.reverse();
    }
    if (!_validURL) {
      return true;
    }
    final originalUrl = widget.url;
    final currentUrl = url;
    print('$originalUrl ----------- $currentUrl');
    if (await webViewController!.canGoBack() && originalUrl != currentUrl) {
      await webViewController!.goBack();
      return false;
    } else {
      return true;
    }
  }

  Future<String> getFilePath(String uniqueFileName) async {
    String? dirPath;
    if (Platform.isAndroid) {
      // Use app-private Downloads directory — no storage permissions needed.
      final directory = await getExternalStorageDirectory();
      dirPath = directory?.path ?? (await getApplicationDocumentsDirectory()).path;
    } else if (Platform.isIOS) {
      dirPath =
          (await getApplicationDocumentsDirectory()).absolute.path;
    }

    return '$dirPath/$uniqueFileName';
  }
}
