import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api.dart';
import 'core/config.dart';
import 'core/app_config.dart';
import 'core/notifications.dart';
import 'core/push.dart';
import 'core/store.dart';
import 'ui/theme.dart';
import 'ui/splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // تهيئة الإشعارات قبل بناء الواجهة: الإعلان الذي يصل أثناء الإقلاع يجب
  // أن يجد قناة جاهزة، وإلا ضاع بلا أثر.
  Notifications.init();
  // الدفع بعدها: رسالة تصل والتطبيق مغلق لا يوقظها شيء محلي، وتهيئة
  // Firebase يجب أن تكون قبل أي طلب شبكة كي يستقبل المعالج الرمز.
  Push.init();
  runApp(const XApp());
}

class XApp extends StatefulWidget {
  const XApp({super.key});
  @override
  State<XApp> createState() => _XAppState();
}

class _XAppState extends State<XApp> {
  late final Future<Store> _store = Store.init();
  late final Api api;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_rebuild);
    ThemeController.instance.load();
    AppConfig.instance.load();
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Store>(
      future: _store,
      builder: (context, snap) {
        if (!snap.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(backgroundColor: XTheme.bg),
          );
        }
        api = Api(snap.data!);
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          theme: XTheme.theme(),
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: SplashScreen(api: api, store: snap.data!),
        );
      },
    );
  }
}
