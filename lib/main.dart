import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/common/widgets/custom_toast.dart';
import 'package:pilipala/http/init.dart';
import 'package:pilipala/models/common/color_type.dart';
import 'package:pilipala/models/common/theme_type.dart';
import 'package:pilipala/pages/search/index.dart';
import 'package:pilipala/pages/video/detail/index.dart';
import 'package:pilipala/router/app_pages.dart';
import 'package:pilipala/pages/main/view.dart';
import 'package:pilipala/services/service_locator.dart';
import 'package:pilipala/utils/app_scheme.dart';
import 'package:pilipala/utils/data.dart';
import 'package:pilipala/utils/debug_bridge.dart';
import 'package:pilipala/utils/global_data_cache.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:pilipala/utils/download_logger.dart';
import 'package:pilipala/utils/startup_permissions.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pilipala/utils/recommend_filter.dart';
import 'package:catcher_2/catcher_2.dart';
import './services/loggeer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await GStrorage.init();
  clearLogs();
  Request();
  await Request.setCookie();

  PiliSchame.init();
  await GlobalDataCache().initialize();

  // 冷启动即创建下载日志文件（downloadlog_DD_HH_MM_SS.txt），
  // 保证之后任意时刻触发下载都有完整链路日志可查
  DownloadLogger.log('[app] cold start, log file: ${DownloadLogger.filePath}');

  // 调试桥（仅 debug 构建；release 由 kDebugMode 与 native BuildConfig.DEBUG 双重门控）
  // 用法文档见 E:\BILIGAI\adb_injecting.md
  if (Platform.isAndroid && kDebugMode) {
    DebugBridge.instance.init();
  }

  // 异常捕获 logo记录
  final Catcher2Options releaseConfig = Catcher2Options(
    SilentReportMode(),
    [FileHandler(await getLogsPath())],
  );

  Catcher2(
    releaseConfig: releaseConfig,
    runAppFunction: () {
      runApp(const MyApp());
    },
  );

  // 小白条、导航栏沉浸
  if (Platform.isAndroid) {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    if (androidInfo.version.sdkInt >= 29) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarColor: Colors.transparent,
    ));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    Box setting = GStrorage.setting;
    // 主题色
    Color defaultColor =
        colorThemeTypes[setting.get(SettingBoxKey.customColor, defaultValue: 0)]
            ['color'];
    Color brandColor = defaultColor;
    // 主题模式
    ThemeType currentThemeValue = ThemeType.values[setting
        .get(SettingBoxKey.themeMode, defaultValue: ThemeType.system.code)];
    // 是否动态取色
    bool isDynamicColor =
        setting.get(SettingBoxKey.dynamicColor, defaultValue: true);
    // 字体缩放大小
    double textScale =
        setting.get(SettingBoxKey.defaultTextScale, defaultValue: 1.0);

    // 强制设置高帧率
    if (Platform.isAndroid) {
      try {
        late List modes;
        FlutterDisplayMode.supported.then((value) {
          modes = value;
          var storageDisplay = setting.get(SettingBoxKey.displayMode);
          DisplayMode f = DisplayMode.auto;
          if (storageDisplay != null) {
            f = modes.firstWhere((e) => e.toString() == storageDisplay);
          }
          DisplayMode preferred = modes.toList().firstWhere((el) => el == f);
          FlutterDisplayMode.setPreferredMode(preferred);
        });
      } catch (_) {}
    }

    if (Platform.isAndroid) {
      return AndroidApp(
        brandColor: brandColor,
        isDynamicColor: isDynamicColor,
        currentThemeValue: currentThemeValue,
        textScale: textScale,
      );
    } else {
      return OtherApp(
        brandColor: brandColor,
        currentThemeValue: currentThemeValue,
        textScale: textScale,
      );
    }
  }
}

class AndroidApp extends StatelessWidget {
  const AndroidApp({
    super.key,
    required this.brandColor,
    required this.isDynamicColor,
    required this.currentThemeValue,
    required this.textScale,
  });

  final Color brandColor;
  final bool isDynamicColor;
  final ThemeType currentThemeValue;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: ((ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme? lightColorScheme;
        ColorScheme? darkColorScheme;
        if (lightDynamic != null && darkDynamic != null && isDynamicColor) {
          // dynamic取色成功
          lightColorScheme = lightDynamic.harmonized();
          darkColorScheme = darkDynamic.harmonized();
        } else {
          // dynamic取色失败，采用品牌色
          lightColorScheme = ColorScheme.fromSeed(
            seedColor: brandColor,
            brightness: Brightness.light,
          );
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: brandColor,
            brightness: Brightness.dark,
          );
        }
        return BuildMainApp(
          lightColorScheme: lightColorScheme,
          darkColorScheme: darkColorScheme,
          currentThemeValue: currentThemeValue,
          textScale: textScale,
        );
      }),
    );
  }
}

class OtherApp extends StatelessWidget {
  const OtherApp({
    super.key,
    required this.brandColor,
    required this.currentThemeValue,
    required this.textScale,
  });

  final Color brandColor;
  final ThemeType currentThemeValue;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return BuildMainApp(
      lightColorScheme: ColorScheme.fromSeed(
        seedColor: brandColor,
        brightness: Brightness.light,
      ),
      darkColorScheme: ColorScheme.fromSeed(
        seedColor: brandColor,
        brightness: Brightness.dark,
      ),
      currentThemeValue: currentThemeValue,
      textScale: textScale,
    );
  }
}

class BuildMainApp extends StatelessWidget {
  const BuildMainApp({
    super.key,
    required this.lightColorScheme,
    required this.darkColorScheme,
    required this.currentThemeValue,
    required this.textScale,
  });

  final ColorScheme lightColorScheme;
  final ColorScheme darkColorScheme;
  final ThemeType currentThemeValue;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final SnackBarThemeData snackBarTheme = SnackBarThemeData(
      actionTextColor: lightColorScheme.primary,
      backgroundColor: lightColorScheme.secondaryContainer,
      closeIconColor: lightColorScheme.secondary,
      contentTextStyle: TextStyle(color: lightColorScheme.secondary),
      elevation: 20,
    );

    return GetMaterialApp(
      title: '温柔の时间',
      theme: ThemeData(
        colorScheme: currentThemeValue == ThemeType.dark
            ? darkColorScheme
            : lightColorScheme,
        snackBarTheme: snackBarTheme,
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: ZoomPageTransitionsBuilder(
              allowEnterRouteSnapshotting: false,
            ),
          },
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: currentThemeValue == ThemeType.light
            ? lightColorScheme
            : darkColorScheme,
        snackBarTheme: snackBarTheme,
      ),
      localizationsDelegates: const [
        GlobalCupertinoLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      locale: const Locale("zh", "CN"),
      supportedLocales: const [Locale("zh", "CN"), Locale("en", "US")],
      fallbackLocale: const Locale("zh", "CN"),
      getPages: Routes.getPages,
      home: const MainApp(),
      onReady: () async {
        RecommendFilter();
        Data.init();
        setupServiceLocator();
      },
      // 首帧渲染完成后预申请通知/存储权限（提前到打开 APP 时，
      // 而不是等用户点下载才弹授权）
      builder: (BuildContext context, Widget? child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          StartupPermissions.ensureAll();
        });
        return FlutterSmartDialog(
          toastBuilder: (String msg) => CustomToast(msg: msg),
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        );
      },
      navigatorObservers: [
        VideoDetailPage.routeObserver,
        SearchPage.routeObserver,
      ],
    );
  }
}
