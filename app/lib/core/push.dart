import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'config.dart';
import 'notifications.dart';

/// الدفع عبر Firebase — قناة الإشعارات التي تصل والتطبيق مغلق.
///
/// إشعارات `flutter_local_notifications` محلية: تظهر فقط والتطبيق يعمل،
/// لأنها تُبنى داخل العملية نفسها. الرسالة التي تصل والمستخدم خارج التطبيق
/// لا يوقظه شيء محلي. FCM هو الطرف الذي يوقظ الجهاز من خارج العملية،
/// فهذا الملف هو ما يجعل «والتطبيق مغلق» صحيحاً.
///
/// البناء بنيوي: كل ما هنا صامت إن لم تُهيّأ Firebase. تطبيق بلا
/// `google-services.json` لا ينكسر — يعمل بالمسار المحلي وحده.
class Push {
  const Push._();

  static bool _ready = false;
  static String _token = '';

  /// آخر رمز جهاز حصلنا عليه — يُستخدم لإلغاء التسجيل عند الخروج.
  static String get token => _token;

  /// يهيّئ Firebase ويربط قنوات الرسائل.
  ///
  /// يُستدعى مرة عند الإقلاع. أي فشل هنا لا يتصاعد: الدفع إضافة، لا شرط
  /// لعمل التطبيق.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    try {
      await Firebase.initializeApp();
      // معالج الخلفية يجب أن يُسجَّل في العزل الأعلى، قبل أي شيء آخر.
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

      // الإشعارات والواجهة مغلقة تماماً تمرّ من هنا عند ضغط المستخدم.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleRemote);
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleRemote(initial);

      // التطبيق في المقدمة: نعرض الإشعار بأنفسنا كي يحمل القناة العربية
      // والوجهة التي يفكّها التطبيق، بدل إشعار Firebase الافتراضي.
      FirebaseMessaging.onMessage.listen(_handleForeground);

      _ready = true;
      await refreshToken();
    } catch (e) {
      debugPrint('push init skipped: $e');
    }
  }

  /// هل الدفع مهيّأ فعلاً في هذا التثبيت؟
  static bool get ready => _ready;

  /// يجلب الرمز ويرسله للخادم، ويستمع لتغيّره.
  ///
  /// الرمز يُبطل ويرمّز من جديد عند إعادة تثبيت التطبيق أو استعادة النسخ
  /// الاحتياطي أو مسح البيانات، فلا بدّ من تحديثه لا الاكتفاء بجلبه مرة.
  static Future<void> refreshToken() async {
    if (!_ready) return;
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null && t.isNotEmpty) _token = t;
      FirebaseMessaging.instance.onTokenRefresh.listen((fresh) {
        _token = fresh;
        final api = Api.current;
        if (api != null) _register(api, fresh);
      });
    } catch (e) {
      debugPrint('push token failed: $e');
    }
  }

  /// يسجّل الرمز عند الخادم تحت المستخدم الحالي.
  ///
  /// يُستدعى بعد كل دخول لأن الرمز يخصّ الجهاز لا الحساب: من سجّل بحساب
  /// آخر على الجهاز نفسه يجب أن يستقبل إشعاراته هو، لا إشعارات السابق.
  static Future<void> registerWith(Api api) async {
    if (!_ready) return;
    if (_token.isEmpty) await refreshToken();
    if (_token.isEmpty) return;
    await _register(api, _token);
  }

  static Future<void> _register(Api api, String token) async {
    try {
      final r = await api.post('/v1/push/register', {
        'token': token,
        'platform': 'android',
      });
      // الخادم يخبرنا إن كان الدفع مهيّأ عنده؛ بغيره لا معنى للرمز.
      debugPrint('push registered: ${r['push']}');
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  /// يلغي تسجيل الرمز — عند تسجيل الخروج.
  static Future<void> unregister(Api api) async {
    if (!_ready || _token.isEmpty) return;
    try {
      await api.post('/v1/push/unregister', {'token': _token});
    } catch (_) {}
  }

  /// رسالة وصلت والتطبيق في المقدمة: نعرضها بأنفسنا.
  static void _handleForeground(RemoteMessage m) {
    final target = _targetOf(m);
    if (target == null) return;
    final title = m.data['title']?.toString() ?? kAppName;
    final body = m.data['body']?.toString() ?? '';
    if (body.isEmpty) return;
    Notifications.showRemote(title: title, body: body, target: target);
  }

  static void _handleRemote(RemoteMessage m) {
    final target = _targetOf(m);
    if (target != null) Notifications.deliver(target);
  }

  /// يفكّ حمولة الوجهة، ويرفض ما لا يعرفه بدل فتح شاشة عشوائية.
  static NotificationTarget? _targetOf(RemoteMessage m) {
    final raw = m.data['target']?.toString() ?? '';
    if (raw.isEmpty) return NotificationTarget.ads;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      switch (j['k']) {
        case 'ad':
          return NotificationTarget.ads;
        case 'chat':
          final room = j['r']?.toString() ?? '';
          if (room.isEmpty) return null;
          return NotificationTarget.chat(room);
      }
    } catch (_) {}
    return null;
  }
}

/// معالج الخلفية: يعمل في عزل منفصل بعد قتل العملية.
///
/// لا يبني إشعاراً ولا يلمس الواجهة — `setBackgroundMessageHandler` في
/// firebase_messaging يمنع عرض إشعار بنفسه، فالعرض هنا مسؤوليتنا. نعرضه
/// بالمكوّن المحلي ثم نخرج فوراً، فالعزل قصير العمر ولا يُنتظر منه أكثر.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage m) async {
  final raw = m.data['target']?.toString() ?? '';
  final title = m.data['title']?.toString() ?? kAppName;
  final body = m.data['body']?.toString() ?? '';
  if (body.isEmpty) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  await plugin.show(
    id: 9002,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        'x_push_chat',
        'رسائل $kAppName',
        channelDescription: 'رسائل وإعلانات تصل والتطبيق مغلق',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body,
            contentTitle: title, summaryText: kAppName),
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: raw.isEmpty ? null : raw,
  );
}