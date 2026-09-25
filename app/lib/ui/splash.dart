import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/api.dart';
import '../core/app_config.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/media_proxy.dart';
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
  static const _maxAutoRetries = 2;

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
      // هوية التوقيع أولاً: لا يمكن توقيع أي طلب قبل وجود مفتاح مسجَّل،
      // و`/v1/install/key` هو المسار الوحيد المسموح بلا توقيع. لو فشل
      // التسجيل (شبكة) نُكمل: الإقلاع نفسه سيُعيد المحاولة، وطلبات لاحقة
      // تُفشل بتوقيع مفقود فيُعاد الإقلاع — أوضح من شاشة عالقة.
      // هوية التوقيع تُهيَّأ بسرعة محليّاً؛ تسجيلها على الخادم يتم ضمن
      // الاتصال الأول ولا يُوقِّف الإقلاع بشاشة خاصة.
      await widget.api.initSigningKey();
      if (!mounted) return;

      final boot = await widget.api.bootstrap();
      // تُحدَّث الإعدادات المشتركة (رابط تيليجرام والباقات) من نفس الردّ.
      await AppConfig.instance.applyBootstrap(boot);
      final settings =
          XSettings.fromJson(boot['settings'] as Map<String, dynamic>? ?? {});

      // بوابة الإصدار — يتحكم بها المالك من لوحته.
      //
      // الإعدادات تُقرأ من `bootstrap` الذي يبقى متاحاً حتى والتطبيق
      // مقفول، وإلا وصل القفل بلا رسالته: التطبيق يرى 503 من كل مسار
      // آخر فيعرض «تعذر الاتصال» ولا يفهم المستخدم أن المالك أوقفه.
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
        unawaited(_registerInstall());
      }

      // استعادة الجلسة أو دخول كزائر صامت
      if (widget.store.hasSession) {
        try {
          final me = await widget.api.me();
          await widget.store.setUser(me['user'] as Map<String, dynamic>?);
        } on ApiException catch (e) {
          if (e.status != 401) rethrow;
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

  Future<void> _registerInstall() async {
    try {
      await widget.api.registerInstall();
      await widget.store.markInstallSent();
    } catch (_) {}
  }

  void _retry() {
    setState(() {
      _blocked = false;
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
                child: Center(
                  child: Text(kAppName,
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
              const SizedBox(height: 8),
              // القفل يقع على الخادم ويرفع نفسه بنفسه عند انتهاء الصيانة،
              // فلا نعرض زر دخول ولا تحديثاً — بل إعادة محاولة فقط، كي لا
              // يظن المستخدم أن التطبيق انتهى أو أن عليه إعادة التثبيت.
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'سنعاود العمل تلقائياً عند انتهاء الصيانة. لا حاجة لإعادة '
                  'التثبيت.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.5),
                ),
              ),
              const SizedBox(height: 16),
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
Future<void> logoutToGuest(BuildContext context, Api api, Store store) async {
  MediaProxy.instance.clear();
  // سحب وسم «جهاز المالك» من الخادم قبل مسح الرمز: بدونه يبقى الخادم
  // يعتبر هذا التثبيت جهاز مالك فيفتح كل دورة مقفلة رغم خروجه. يحتاج
  // رمز المالك لذلك يسبق clearSession. الفشل (لا رمز، لا شبكة) لا يمنع
  // الخروج المحلي — لكنه يُحاول دائماً ولا يُتخطّى.
  try {
    await api.ownerReleaseDevice();
  } catch (_) {}
  await store.clearSession();
  api.clearMediaSignatures();
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => SplashScreen(api: api, store: store)),
    (route) => false,
  );
}

Future<void> openAuth(BuildContext context, Api api, Store store) {
  return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(api: api, store: store)));
}
