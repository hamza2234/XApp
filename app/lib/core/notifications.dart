import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

/// وجهة الإشعار — ما يُفتح عند ضغط المستخدم عليه.
///
/// الضغط بلا وجهة إشعار ميّت: يفتح التطبيق على آخر شاشة كان عليها المستخدم،
/// فيظنّ أن الضغط لم يعمل. لذلك نضع الوجهة في `payload` ونحملها معنا عبر
/// مسارات الإشعار الثلاثة (التطبيق مفتوح، في الخلفية، مغلق).
class NotificationTarget {
  const NotificationTarget._(this.kind, this.roomId);

  /// `ad` إعلان · `chat` رسالة في قسم.
  final String kind;
  final String roomId;

  static const NotificationTarget ads = NotificationTarget._('ad', '');

  static NotificationTarget chat(String roomId) =>
      NotificationTarget._('chat', roomId);

  String encode() => jsonEncode({'k': kind, if (roomId.isNotEmpty) 'r': roomId});

  /// يفكّ الحمولة، ويرفض ما لا يعرفه بدل أن يفتح شاشة عشوائية.
  static NotificationTarget? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
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
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

/// بوّابة قرار إظهار إشعار الدردشة — منطق صافٍ بلا منصة، فيُختبر مباشرة.
///
/// ثلاثة شروط تمنع الإشعار المزعج أو الكاذب:
///   - الدردشة موقوفة من الإعدادات، أو المستخدم كاتم الإشعارات.
///   - الرسالة رسالتي: إشعاري عن رسالتي أنا ضجيج محض.
///   - القسم مفتوح أمام المستخدم الآن: هو يراه بعينه، والإشعار تكرار.
class ChatNotifyGate {
  const ChatNotifyGate._();

  static bool shouldNotify({
    required bool chatEnabled,
    required bool notifyEnabled,
    required bool mine,
    required String roomId,
    required String openRoomId,
  }) {
    if (!chatEnabled || !notifyEnabled) return false;
    if (mine) return false;
    if (roomId.isEmpty) return false;
    return roomId != openRoomId;
  }
}

/// إشعارات التطبيق — إعلانات المالك ورسائل الدردشة تصل إلى شريط الهاتف.
///
/// إذن الإشعارات في أندرويد 13+ لا يُمنح تلقائياً، ورفضه يعني ألا يرى
/// المستخدم أي إشعار أبداً بلا أي رسالة خطأ — يظن التطبيق معطّلاً. لذلك
/// نطلب الإذن صراحة مع شرح سبب الطلب قبل نافذة النظام، وهو ما يرفع نسبة
/// الموافقة ويحترم المستخدم في الوقت نفسه.
class Notifications {
  const Notifications._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _kAsked = 'x_notif_asked';
  static const _kSeenAnns = 'x_seen_announcements';
  static const _kPendingKey = 'x_notif_pending';

  /// وجهة إشعار ضُغط بينما التطبيق لم يكن جاهزاً بعد.
  ///
  /// الضغط من شريط الهاتف يقع قبل بناء الواجهة، فلو أكملنا الوجهة مباشرة
  /// ضاعت في الفراغ. نحفظها هنا ويسحبها الغلاف عند أول إطار.
  static NotificationTarget? _pending;

  static void Function(NotificationTarget target)? _listener;

  /// يسجّل مستمعاً للضغط على الإشعار.
  static void listen(void Function(NotificationTarget target) cb) {
    _listener = cb;
  }

  /// يسحب وجهة معلّقة إن وُجدت (يُستدعى عند أول إطار بعد الإقلاع).
  static NotificationTarget? takePending() {
    final t = _pending;
    _pending = null;
    return t;
  }

  /// يوجّه الوجهة إلى الواجهة إن كانت جاهزة، وإلا يخزّنها للاحقاً.
  static void _deliver(NotificationTarget? target) {
    if (target == null) return;
    final cb = _listener;
    if (cb == null) {
      _pending = target;
      return;
    }
    cb(target);
  }

  /// قناة الإعلانات — أهمية عالية حتى يظهر الإشعار كرأس منبثق.
  static const _annChannelId = 'mapx_announcements';

  /// قناة الدردشة منفصلة عن الإعلانات.
  ///
  /// الفصل مقصود: من وجد الإعلانات مزعجة يكتم قناتها وحدها فيبقى يعرف أن
  /// أحداً ناداه في الدردشة. قناة واحدة تخلط النوعين تجبره على الاختيار بين
  /// الضجيج والعزلة.
  static const _chatChannelId = 'mapx_chat';

  static const _annChannel = AndroidNotificationChannel(
    _annChannelId,
    'إعلانات MAPX',
    description: 'إشعارات إعلانات المالك والعروض الجديدة',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const _chatChannel = AndroidNotificationChannel(
    _chatChannelId,
    'رسائل الدردشة',
    description: 'إشعارات الرسائل الجديدة في أقسام الدردشة',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  /// معالجة الضغط داخل معزل الخلفية.
  ///
  /// لازم منفصلة ومعلَّمة `vm:entry-point`: حين يكون التطبيق مغلقاً تماماً
  /// يبدأ أندرويد معزلاً جديداً بلا شجرة واجهة، ولا سبيل فيه لنداء مستمع
  /// الواجهة. نكتب الوجهة في التخزين ليقرأها التطبيق عند نهوضه.
  @pragma('vm:entry-point')
  static void _onBackgroundTap(NotificationResponse response) {
    final t = NotificationTarget.decode(response.payload);
    if (t == null) return;
    // معزل الخلفية قد لا تكون مكوّنات الإضافة مسجّلة فيه على بعض الأجهزة؛
    // فشل الكتابة يجب ألّا يُسقط التطبيق — الوجهة تُستعاد عندها من تفاصيل
    // الإطلاق التي يحملها المكوّن نفسه.
    SharedPreferences.getInstance()
        .then((p) => p.setString(_kPendingKey, t.encode()))
        .catchError((_) => false);
  }

  /// تهيئة المكوّن مرة واحدة عند الإقلاع.
  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          _deliver(NotificationTarget.decode(response.payload)),
      onDidReceiveBackgroundNotificationResponse: _onBackgroundTap,
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_annChannel);
    await android?.createNotificationChannel(_chatChannel);

    // ضغط أغلق التطبيق ثم فتحه: الوجهة إمّا في التخزين (كتبها معزل الخلفية)
    // أو في تفاصيل الإطلاق التي يحملها المكوّن نفسه.
    final p = await SharedPreferences.getInstance();
    final stored = p.getString(_kPendingKey);
    if (stored != null) {
      await p.remove(_kPendingKey);
      _pending = NotificationTarget.decode(stored);
    }
    if (_pending == null) {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _pending =
            NotificationTarget.decode(launch?.notificationResponse?.payload);
      }
    }
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
        _annChannelId,
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
      id: 9001,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload ?? NotificationTarget.ads.encode(),
    );
  }

  /// الإعلانات التي رأى صاحب الجهاز إشعارها بالفعل.
  static Future<Set<String>> _seen() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kSeenAnns) ?? const []).toSet();
  }

  /// يُنشئ إشعاراً محلياً لكل إعلان جديد لم يُنبَّه عنه على هذا الجهاز.
  ///
  /// الحدّ المعروف: هذا ليس دفعاً حقيقياً (FCM). الإعلان يصل حين يفتح
  /// المستخدم التطبيق أو يعود إليه، لا وهو مغلق تماماً. الدفع الحقيقي يحتاج
  /// مشروع Firebase وملف `google-services.json`، وليسا معدّين في هذا المستودع.
  ///
  /// نعرض إشعاراً واحداً عند وجود إعلانات جديدة مهما كان عددها — ثلاثة
  /// إشعارات دفعة واحدة تُنفّر، وواحد يلفت النظر بلا إزعاج.
  static Future<int> notifyNewAnnouncements(List<dynamic> anns) async {
    if (!Platform.isAndroid) return 0;
    if (anns.isEmpty) return 0;
    if (!await granted) return 0;

    final seen = await _seen();
    final fresh = <Map>[
      for (final a in anns)
        if (a is Map && !seen.contains('${a['id']}')) a,
    ];
    if (fresh.isEmpty) return 0;

    await _plugin.show(
      // معرّف ثابت: يتحدّث الإشعار بدل تكديس نسخ.
      id: 9001,
      title: fresh.length == 1
          ? '${fresh.first['title'] ?? 'إعلان جديد'}'
          : '${fresh.length} إعلانات جديدة',
      body: fresh.length == 1
          ? '${fresh.first['subtitle'] ?? ''}'
          : '${fresh.first['title'] ?? ''} و${fresh.length - 1} غيرها',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _annChannelId,
          'إعلانات MAPX',
          channelDescription: 'إشعارات إعلانات المالك والعروض الجديدة',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            fresh
                .map((a) => '• ${a['title'] ?? ''}\n${a['subtitle'] ?? ''}')
                .join('\n\n'),
            contentTitle: 'إعلانات MAPX',
            summaryText: 'MAPX',
          ),
          color: XTheme.accent,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: NotificationTarget.ads.encode(),
    );

    // تُحفظ بعد العرض الناجح فقط — إخفاق الإشعار يجب ألّا يمنع المحاولة لاحقاً.
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
        _kSeenAnns, {...seen, ...fresh.map((a) => '${a['id']}')}.toList());
    return fresh.length;
  }

  /// يعرض إشعار رسالة دردشة جديدة، والضغط عليه يفتح القسم نفسه.
  ///
  /// معرّف الإشعار مشتقّ من القسم، فرسائل القسم الواحد تُحدِّث إشعاراً واحداً
  /// بدل أن تصير عشرة صفوف في الشريط. و[count] عدد الرسائل المنتظرة في القسم
  /// فيرى المستخدم حجم ما ينتظره بلا فتح التطبيق.
  static Future<void> notifyChatMessage({
    required String roomId,
    required String roomName,
    required String author,
    required String preview,
    int count = 1,
  }) async {
    if (!Platform.isAndroid) return;
    if (roomId.isEmpty) return;
    if (!await granted) return;

    final title = count > 1 ? '$roomName • $count رسائل' : roomName;
    final body =
        preview.trim().isEmpty ? '$author أرسل مرفقاً' : '$author: $preview';

    await _plugin.show(
      // نطاق 10000+ يمنع تصادم معرّف القسم مع معرّف الإعلان الثابت 9001.
      id: 10000 + (roomId.hashCode.abs() % 100000),
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _chatChannelId,
          'رسائل الدردشة',
          channelDescription: 'إشعارات الرسائل الجديدة في أقسام الدردشة',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: 'MAPX',
          ),
          color: XTheme.accent,
          icon: '@mipmap/ic_launcher',
          ticker: roomName,
          category: AndroidNotificationCategory.message,
          // تجميع حسب القسم: كل أقسام الدردشة تحت عنوان واحد في الشريط.
          groupKey: 'mapx_chat_group',
        ),
      ),
      payload: NotificationTarget.chat(roomId).encode(),
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
