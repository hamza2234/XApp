import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

/// إشعارات التطبيق — إعلانات المالك تصل إلى شريط الهاتف.
///
/// إذن الإشعارات في أندرويد 13+ لا يُمنح تلقائياً، ورفضه يعني ألا يرى
/// المستخدم أي إعلان أبداً بلا أي رسالة خطأ — يظن التطبيق معطّلاً. لذلك
/// نطلب الإذن صراحة مع شرح سبب الطلب قبل نافذة النظام، وهو ما يرفع نسبة
/// الموافقة ويحترم المستخدم في الوقت نفسه.
class Notifications {
  const Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _kAsked = 'x_notif_asked';
  static const _channelId = 'mapx_announcements';

  /// قناة الإعلانات — أهمية عالية حتى يظهر الإشعار كرأس منبثق.
  static const _channel = AndroidNotificationChannel(
    _channelId,
    'إعلانات MAPX',
    description: 'إشعارات إعلانات المالك والعروض الجديدة',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// تهيئة المكوّن مرة واحدة عند الإقلاع.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (_) {},
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
  }

  /// حالة الإذن الحالية.
  static Future<bool> get granted async {
    if (!Platform.isAndroid) return false;
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await impl?.areNotificationsEnabled() ?? false;
  }

  /// هل سبق أن شرحنا للمستخدم وطلبنا الإذن؟
  static Future<bool> get asked async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAsked) ?? false;
  }

  static Future<void> markAsked() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAsked, true);
  }

  /// يطلب الإذن من نظام أندرويد. يُعيد true إن مُنح.
  ///
  /// نستخدم طلب الحزمة نفسه بدل حزمة أذونات منفصلة: `requestNotificationsPermission`
  /// تفتح نافذة النظام على أندرويد 13+، وتُرجع null على النسخ الأقدم حيث
  /// الإذن ممنوح ضمناً.
  static Future<bool> request() async {
    if (!Platform.isAndroid) return false;
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final granted = await impl?.requestNotificationsPermission();
    return granted ?? await Notifications.granted;
  }

  /// يعرض إشعار إعلان جديد.
  static Future<void> showAnnouncement({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    if (!await granted) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'إعلانات MAPX',
        channelDescription: 'إشعارات إعلانات المالك والعروض الجديدة',
        importance: Importance.high,
        priority: Priority.high,
        // نمط كبير: الإعلان نصّي غالباً، ونعرضه كاملاً بدل سطر مقطوع.
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: 'MAPX',
        ),
        color: XTheme.accent,
        icon: '@mipmap/ic_launcher',
        ticker: title,
        category: AndroidNotificationCategory.message,
      ),
    );
    await _plugin.show(
      id: title.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}

/// حوار شرح إذن الإشعارات — يُعرض مرة واحدة قبل نافذة النظام.
///
/// لماذا حوار شرح قبل نافذة النظام؟ لأن رفض نافذة النظام يمنع طلبها مرة
/// ثانية في كثير من الأجهزة، فيخسر المستخدم الإعلانات للأبد. الشرح أولاً
/// يجعل الموافقة قراراً واعياً لا ردة فعل على نافذة مبهمة.
class NotificationPermissionDialog extends StatelessWidget {
  const NotificationPermissionDialog({super.key});

  /// يُعيد true إن وافق المستخدم وطُلب الإذن (أو مُنح).
  static Future<bool> show(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const NotificationPermissionDialog(),
    );
    if (ok != true) return false;
    final granted = await Notifications.request();
    await Notifications.markAsked();
    return granted;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: XTheme.gradient,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.notifications_active_outlined,
                color: Colors.white, size: 21),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('تفعيل الإشعارات',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      content: Text(
        'نرسل إشعارات قليلة ومهمة فقط:\n\n'
        '• إعلانات المالك والعروض الجديدة\n'
        '• تنبيهات مهمة عن التطبيق\n\n'
        'لا نرسل إعلانات تجارية من أطراف أخرى، ولا نستخدم الإشعارات '
        'لتتبّعك. يمكنك إيقافها في أي وقت من إعدادات الهاتف.',
        style: TextStyle(
            fontSize: 13.5, height: 1.7, color: XTheme.text.withOpacity(.9)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('ليس الآن', style: TextStyle(color: XTheme.textDim)),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
              gradient: XTheme.gradient,
              borderRadius: BorderRadius.circular(12)),
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('تفعيل',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}
