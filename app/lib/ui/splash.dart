import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/api.dart';
import '../core/app_config.dart';
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
  bool _offline = false;
  int _attempt = 0;

  /// أقصى عدد محاولات تلقائية قبل إظهار زر إعادة المحاولة — بدل حلقة
  /// صامتة لا تنتهي كانت تُظهر «تعذر الاتصال» بلا مخرج عند أول تشغيل.
  static const _maxAutoRetries = 5;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// الاستثناءات المتعلقة بالشبكة وحدها تستحق إعادة المحاولة.
  /// `http.ClientException` هو ما يغلّف به package:http انقطاع الاتصال
  /// وفشل DNS — وهو الحالة الأكثر شيوعاً عند أول تشغيل بلا إنترنت.
  static bool _isNetworkError(Object e) =>
      e is http.ClientException ||
      e is SocketException ||
      e is HttpException ||
      e is TimeoutException ||
      e is HandshakeException;

  Future<void> _boot() async {
    try {
      setState(() {
        _status = _attempt == 0
            ? 'الاتصال بالخادم…'
            : 'إعادة المحاولة (${_attempt + 1}/$_maxAutoRetries)…';
        _offline = false;
      });
      final boot = await widget.api.bootstrap();
      // تُحدَّث الإعدادات المشتركة (رابط تيليجرام والباقات) من نفس الردّ.
      await AppConfig.instance.applyBootstrap(boot);
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
      if (!mounted) return;
      _attempt++;
      final retriable = (_isNetworkError(e) ||
              // 429 و5xx أخطاء مؤقتة من الخادم: كانت تُعرض «تعذر الاتصال
              // تحقق من الإنترنت» بلا محاولة ثانية، فيظن المستخدم أن شبكته
              // معطلة ويرفض إعادة المحاولة يدوياً.
              (e is ApiException &&
                  (e.status == 429 || e.status >= 500))) &&
          _attempt < _maxAutoRetries;
      setState(() {
        _offline = !retriable;
        // خطأ الخادم الحقيقي (403 حظر، 401 جلسة) يجب أن يظهر بنصه:
        // إخفاؤه خلف «تحقق من الإنترنت» يجعل المحظور يظن أن شبكته معطلة
        // ويعيد المحاولة بلا فائدة بدل التواصل مع المالك.
        _status = retriable
            ? 'إعادة المحاولة (${_attempt + 1}/$_maxAutoRetries)…'
            : (e is ApiException && e.message.trim().isNotEmpty)
                ? e.message
                : 'تعذر الاتصال بالخادم — تحقق من الإنترنت ثم أعد المحاولة';
      });
      if (retriable) {
        // تراجع تدريجي: يمنح الشبكة الضعيفة عند أول تشغيل وقتاً للاستقرار.
        await Future.delayed(Duration(milliseconds: 600 * _attempt));
        if (mounted) _boot();
      }
    }
  }

  void _retry() {
    setState(() {
      _attempt = 0;
      _offline = false;
    });
    _boot();
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
                  child: Text('MAPX',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
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
            ] else if (_offline) ...[
              Icon(Icons.cloud_off_rounded,
                  size: 42, color: XTheme.danger.withOpacity(.85)),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(_status,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: XTheme.text, fontSize: 15)),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('إعادة المحاولة'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: XTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 12)),
              ),
              const SizedBox(height: 10),
              // المالك قد يكون جهازه محظوراً أو جلسته منتهية: بدون هذا الزر
              // لا يجد طريقاً للوحة التحكم لإلغاء الحظر، فيبقى خارج تطبيقه.
              TextButton.icon(
                onPressed: () => openAuth(context, widget.api, widget.store)
                    .then((_) {
                  if (mounted) _retry();
                }),
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: const Text('دخول المالك'),
                style: TextButton.styleFrom(foregroundColor: XTheme.gold),
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
