import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/api.dart';
import 'core/store.dart';
import 'ui/theme.dart';
import 'ui/splash.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  Widget build(BuildContext context) {
    return FutureBuilder<Store>(
      future: _store,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(backgroundColor: XTheme.bg),
          );
        }
        api = Api(snap.data!);
        return MaterialApp(
          title: 'X',
          debugShowCheckedModeBanner: false,
          theme: XTheme.dark(),
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
