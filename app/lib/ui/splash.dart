import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';
import 'auth_screen.dart';
import 'shell.dart';
import 'update_screen.dart';

/// شاشة البداية: bootstrap + تسجيل التثبيت + فحص الإصدار + استعادة الجلسة
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.api, required this.store});
  final Api api;
  final Store store;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();
  String _status = 'جاري التهيئة…';
  bool _blocked = false;
  String _blockMsg = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      setState(() => _status = 'الاتصال بالخادم…');
      final boot = await widget.api.bootstrap();
      final settings =
          XSettings.fromJson(boot['settings'] as Map<String, dynamic>? ?? {});

      // بوابة الإصدار — يتحكم بها المالك من لوحته
      if (settings.appLocked) {
        setState(() {
          _blocked = true;
          _blockMsg = settings.lockMessage.isEmpty
              ? 'التطبيق متوقف مؤقتاً للصيانة'
              : settings.lockMessage;
        });
        return;
      }
      if (kAppVersion < settings.minVersion ||
          settings.blockedVersions.contains(kAppVersion)) {
        if (!mounted) return;
        final u = boot['update'] as Map<String, dynamic>? ?? {};
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => UpdateScreen(
                  message: u['message']?.toString(),
                  url: u['url']?.toString(),
                  imageUrl: u['imageUrl']?.toString(),
                  apiBase: kApiBase,
                )));
        return;
      }

      // تسجيل التثبيت مرة واحدة
      if (!widget.store.installSent) {
        try {
          await widget.api.registerInstall();
          await widget.store.markInstallSent();
        } catch (_) {}
      }

      // استعادة الجلسة أو دخول كزائر صامت
      if (widget.store.hasSession) {
        try {
          await widget.api.me();
        } catch (_) {
          await widget.store.clearSession();
        }
      }
      if (!widget.store.hasSession) {
        setState(() => _status = 'تجهيز جلسة التصفح…');
        final g = await widget.api.guest();
        await widget.store.setToken(g['token']);
        await widget.store.setUser(g['user']);
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (_) => Shell(api: widget.api, store: widget.store)),
      );
    } catch (e) {
      setState(() => _status = 'تعذر الاتصال — تحقق من الإنترنت');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _boot();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RotationTransition(
              turns: _c,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  gradient: XTheme.gradient,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                        color: XTheme.accent.withOpacity(.4),
                        blurRadius: 40,
                        spreadRadius: 2)
                  ],
                ),
                child: const Center(
                  child: Text('X',
                      style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 36),
            if (_blocked) ...[
              Icon(Icons.lock_outline, color: XTheme.gold, size: 40),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(_blockMsg,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: XTheme.text, fontSize: 16)),
              ),
            ] else ...[
              Text(_status,
                  style: TextStyle(color: XTheme.textDim, fontSize: 14)),
              const SizedBox(height: 14),
              SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: XTheme.accent)),
            ],
          ],
        ),
      ),
    );
  }
}

/// بعد الدخول كزائر يمكن الترقية لحساب من شاشة الدخول
Future<void> openAuth(BuildContext context, Api api, Store store) {
  return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(api: api, store: store)));
}
