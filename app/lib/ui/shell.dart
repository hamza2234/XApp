import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/app_config.dart';
import '../core/notifications.dart';
import '../core/push.dart';
import '../core/store.dart';
import 'theme.dart';
import 'nav_bar.dart';
import 'brand_logo.dart';
import 'chat_screen.dart';
import 'compat_screen.dart';
import 'courses_screen.dart';
import 'gift_screen.dart';
import 'schem_screen.dart';
import 'owner_gate.dart';
import 'splash.dart';
import 'external_link.dart';
import 'update_screen.dart';

/// الهيكل الرئيسي: شريط تنقل سفلي + قائمة جانبية
class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.store});
  final Api api;
  final Store store;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int _tab = 0;

  /// آخر تبويب غير الدردشة — نعود إليه عند الخروج من الدردشة.
  ///
  /// الرجوع إلى تبويب ثابت (التوافقات) يفقد المستخدم مكانه إن كان يتنقل
  /// بين المخططات والدردشة، فيبدو الرجوع كأنه نقلة عشوائية.
  int _lastNonChatTab = 0;

  /// تبويبات الشريط الظاهرة الآن، بترتيبها. **وهي مصدر الحقيقة الوحيد**:
  /// عناصر الشريط في `build` تُبنى منها عبر [_tabItems]، فلا ينفصل عددهما.
  ///
  /// كان هذا الانفصال عطلاً حقيقياً: حُذف تبويب الهديّة من هنا وبقي عنصرها
  /// في الشريط، فصار عدد العناصر خمسة والتبويبات أربعة — أيقونة الدردشة في
  /// الموضع الخامس تقرأ `_navTabs[4]` فينفتح `RangeError` عند كل ضغطة.
  ///
  /// الدورات تُحذف كلياً حين يوقف المالك عرض الفيديوهات: المطلوب إخفاء
  /// شاشات العرض لا إيقاف التشغيل فقط، فلا يبقى تبويب يفتح على فراغ.
  /// الهديّة ليست تبويباً: تُفتح من أيقونتها في الشريط العلوي وحدها، فالشريط
  /// السفلي يبقى للتنقّل الأساسي ولا يزدحم بزرّ يوميّ.
  List<int> get _navTabs =>
      _cfg.videosHidden ? const [0, 1, 3] : const [0, 1, 2, 3];

  /// عنصر شريط لكل تبويب في [_navTabs] — نفس الطول ونفس الترتيب بالبناء.
  /// إضافة تبويب أو حذفه تُحدّث الاثنين معاً بلا خطوة ثانية تُنسى.
  List<NavItem> get _tabItems => [
        const NavItem(
            icon: Icons.hub_outlined, activeIcon: Icons.hub, label: 'التوافقات'),
        const NavItem(
            icon: Icons.schema_outlined,
            activeIcon: Icons.schema,
            label: 'المخططات'),
        if (!_cfg.videosHidden)
          const NavItem(
              icon: Icons.play_lesson_outlined,
              activeIcon: Icons.play_lesson,
              label: 'الدورات'),
        const NavItem(
            icon: Icons.forum_outlined,
            activeIcon: Icons.forum,
            label: 'الدردشة'),
      ];

  /// موضع التبويب الحالي داخل الشريط الظاهر، مع الرجوع للأول إن غاب تبويبه.
  int get _navIndex {
    final at = _navTabs.indexOf(_tab);
    return at < 0 ? 0 : at;
  }

  /// خروج من الدردشة — والعودة إلى آخر تبويب غير الدردشة.
  bool get _chatOpen => _tab == _chatTab;
  int get _chatTab => 3;

  /// الخروج من الدردشة يعيد الشريطين ويعود للتبويب السابق.
  void _exitChat() {
    setState(() => _tab = _lastNonChatTab);
  }
  // العدّاد الموحّد: منحة يومية + رصيد عملات، مصدره /v1/me وحده.
  int _freeLeft = 0;
  int _freeLimit = 0;
  int _coins = 0;

  /// هديّة اليوم: تُقرأ من الإعدادات (المبلغ) ومن حالة الشريط (هل استُلمت).
  bool _giftEnabled = false;
  bool _giftClaimed = false;
  /// لحظة فتح هديّة الغد (ms). صفر = الخادم لم يُخبرنا، فلا نعرض عدّاداً.
  int _giftNextAt = 0;
  int _cardExpiry = 0;
  // الإعدادات المشتركة: رابط تيليجرام والباقات ومبلغ الهديّة من مصدر واحد.
  AppConfig get _cfg => AppConfig.instance;

  /// غلاف لتبويب الهديّة: يحوّل ردّ الخادم إلى نتيجة يفهمها راسم العجلة.
  ///
  /// لا يُعاد المبلغ من العميل أبداً — الخادم هو من يقرّره، وهذا الغلاف ينقله
  /// كما وصل. العجلة شكل فقط ولا تملك قرار الجائزة.
  Future<GiftClaimResult> _claimGiftForWheel() async {
    try {
      final r = await widget.api.claimGift();
      final amount = (r['amount'] as num?)?.toInt() ?? 0;
      if (mounted) setState(() => _giftClaimed = true);
      // نجلب موعد هديّة الغد فوراً ليظهر العدّاد التنازلي.
      unawaited(_refresh());
      return GiftClaimResult(
        ok: true,
        amount: amount,
        message: r['message']?.toString() ?? '',
      );
    } on ApiException catch (e) {
      // 409 = استُلمت اليوم: نُثبّت الحالة ونجلب موعد الغد بدل ترك الزر متاحاً.
      if (e.status == 409) {
        if (mounted) setState(() => _giftClaimed = true);
        unawaited(_refresh());
      }
      return GiftClaimResult(ok: false, message: e.message);
    } catch (_) {
      return const GiftClaimResult(
          ok: false, message: 'تعذّر استلام الهديّة — تحقّق من الاتصال');
    }
  }

  /// فحص دوري للإعلانات الجديدة. لا دفع حقيقي (FCM) في هذا المشروع،
  /// فالاستقصاء هو الوسيلة المتاحة لإبلاغ الأجهزة الأخرى.
  Timer? _annTimer;

  /// قسم مطلوب فتحه — يأتي من ضغط إشعار دردشة، ويُمرَّر للدردشة.
  String _openRoomId = '';

  /// القسم المعروض في تبويب الدردشة الآن — يمنع الإشعار عن قسم يراه المستخدم.
  String _activeRoomId = '';

  /// وجهة إشعار محفوظة السحب (ضغط والتطبيق مغلق أو قبل جاهزية الواجهة).
  bool _pendingRouteDrained = false;

  /// نبضة إشعارات الدردشة — منفصلة عن نبضة الإعلانات لأن دورها أطول:
  /// الإعلان حدث نادر، والرسالة قد تصل كل ثانية في قسم نشِط.
  Timer? _chatTimer;

  /// نبضة الإعدادات: تغييرات لوحة المالك (رابط التواصل، الباقات، الإعلان،
  /// إغلاق التطبيق) يجب أن تصل للتطبيق المفتوح، لا عند إعادة تشغيله فقط.
  /// دورة أطول من نبضة الدردشة لأن الإعدادات تتغير نادراً.
  Timer? _settingsTimer;

  /// آخر ختم زمني رأيناه لكل قسم — أساس تمييز الجديد عن القديم.
  final Map<String, int> _chatLastSeen = {};

  /// عدد الرسائل غير المقروءة لكل قسم منذ آخر إشعار.
  final Map<String, int> _chatUnread = {};

  /// ما تبقّى فعلاً = المجاني اليومي + العملات. رقم واحد يُعرض ويُخصم.
  int get _totalLeft => _freeLeft + _coins;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // إعادة البناء فوراً إن وصل تحديث للرابط أو الباقات.
    _cfg.addListener(_onConfigChanged);
    // قفل الإصدار أثناء الاستعمال: المالك قد يوقف إصداراً والتطبيق مفتوح،
    // وبدون هذا المستمع يبقى يعمل بشاشات تفشل طلباتها بلا سبب مفهوم.
    VersionLock.instance.addListener(_onVersionLocked);
    _refresh();
    // طلب إذن الإشعارات بعد استقرار الشاشة الأولى، لا أثناءها: نافذة
    // النظام فوق شاشة التهيئة تبدو خللاً، وتُرفض بلا قراءة.
    WidgetsBinding.instance.addPostFrameCallback((_) => _askNotifications());
    // الوجهة الأولى تُسحب بعد أول إطار: الضغط قد يكون فتح التطبيق من الصفر،
    // والشجرة لم تكن جاهزة لحظة قراءتها.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drainPendingRoute());
    Notifications.listen(_route);
    _annTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _pollAnnouncements());
    // 30 ثانية لا 20: الدورة تجلب الرسائل لكل قسم، ورقم أصغر يضاعف
    // الطلبات بلا فائدة — الإشعار لا يحتاج دقة الثواني هذه.
    _chatTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _pollChatMessages());
    // الإعدادات والحصة معاً: تغيير المالك للحصص أو رابط التواصل يظهر
    // خلال دقيقة بلا إغلاق التطبيق.
    _settingsTimer = Timer.periodic(
        const Duration(seconds: 60), (_) => _pollSettings());
  }

  /// يوجّه ضغط الإشعار إلى الشاشة الصحيحة.
  void _route(NotificationTarget t) {
    if (!mounted) return;
    switch (t.kind) {
      case 'chat':
        setState(() {
          _openRoomId = t.roomId;
          _lastNonChatTab = _tab;
          _tab = _chatTab;
        });
      case 'ad':
        // الإعلانات تُعرض في تبويب التوافقات أعلى الشاشة.
        setState(() => _tab = 0);
    }
  }

  /// يقرأ وجهة ضغط سابقة قبل جاهزية الواجهة، إن وُجدت.
  Future<void> _drainPendingRoute() async {
    if (_pendingRouteDrained) return;
    _pendingRouteDrained = true;
    final t = Notifications.takePending();
    if (t != null) _route(t);
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // العودة إلى التطبيق أهمّ لحظة: المستخدم ينظر إلى الشاشة الآن.
    if (state == AppLifecycleState.resumed) {
      _pollAnnouncements();
      _pollChatMessages();
    }
  }

  /// يجلب الإعلانات ويُنبّه عن الجديد منها على هذا الجهاز.
  Future<void> _pollAnnouncements() async {
    if (!mounted) return;
    try {
      final boot = await widget.api.bootstrap();
      final anns = boot['announcements'];
      if (anns is List) await Notifications.notifyNewAnnouncements(anns);
    } catch (_) {
      // فشل الشبكة لا يستحق إزعاج المستخدم — تُعاد المحاولة في الدورة التالية.
    }
  }

  /// يفحص أقسام الدردشة وينبّه عن الرسائل الجديدة.
  ///
  /// لا دفع حقيقي (FCM) في هذا المشروع، فالاستقصاء هو الوسيلة المتاحة: كل
  /// نبضة تسأل كل قسم عن الجديد بعد آخر ختم رأيناه. أول نبضة لكل قسم
  /// **تؤسّس** الختم ولا تُنبّه، وإلا وصل إشعار بكل تاريخ المحادثة لحظة
  /// التثبيت — وهو أسوأ عطل ممكن في هذه الميزة.
  ///
  /// أما القسم المفتوح أمام المستخدم فلا يُنبَّه عنه: هو يراه بعينه.
  Future<void> _pollChatMessages() async {
    if (!mounted) return;
    // الدردشة المفتوحة تستطلع بنفسها (شاشة الدردشة)، فاستقصاء الغلاف فوقها
    // لا يضيف شيئاً ويسحب طلبات مضاعفة على القسم نفسه.
    if (_chatOpen) return;
    try {
      final state = await widget.api.chatState();
      if (!mounted) return;
      if (!state.enabled) return;

      // القسم مفتوح أمام المستخدم فقط إن كان تبويب الدردشة هو المعروض.
      final openRoom = _chatOpen ? _activeRoomId : '';
      for (final room in state.rooms) {
        // القسم الذي فتحه المستخدم من الإشعار ليس بعد في `_openRoomId`
        // بعد، فيُترك بلا إشعار — وهو المطلوب.
        final last = _chatLastSeen[room.id];
        final page = await widget.api.chatMessages(room.id, limit: 20);
        if (!mounted) return;
        final newest = page.messages.isEmpty
            ? 0
            : page.messages.map((m) => m.at).reduce((a, b) => a > b ? a : b);

        if (last == null) {
          // أول رؤية لهذا القسم: نؤسّس ولا نُنبّه.
          _chatLastSeen[room.id] = newest;
          continue;
        }

        final fresh = page.messages.where((m) => m.at > last).toList();
        if (fresh.isEmpty) continue;
        _chatLastSeen[room.id] = newest;

        // رسالة واحدة تكفي للقرار: رسالتي أنا لا تُنبَّه، والقسم المفتوح لا.
        final latest = fresh.last;
        final notify = ChatNotifyGate.shouldNotify(
          chatEnabled: state.enabled,
          notifyEnabled: state.notify,
          mine: latest.mine,
          roomId: room.id,
          openRoomId: openRoom,
        );
        if (!notify) {
          _chatUnread[room.id] = 0;
          continue;
        }

        // نعدّ الجديد غير المقروء التراكمي في القسم، لا رسائل هذه النبضة
        // وحدها، فيرى المستخدم حجم ما ينتظره فعلاً.
        final count = (_chatUnread[room.id] ?? 0) +
            fresh.where((m) => !m.mine).length;
        _chatUnread[room.id] = count;

        await Notifications.notifyChatMessage(
          roomId: room.id,
          roomName: room.name,
          author: latest.author.label,
          preview: latest.preview,
          count: count,
        );
      }
    } catch (_) {
      // فشل الشبكة لا يستحق إزعاج المستخدم — تُعاد المحاولة في الدورة التالية.
    }
  }

  /// يشرح للمستخدم ثم يطلب الإذن — مرة واحدة في عمر التثبيت.
  ///
  /// لا يُعاد الطلب بعد ذلك أبداً: تكرار نافذة النظام يُنفّر المستخدم،
  /// ورفضها قد يمنع طلبها مجدداً في كثير من الأجهزة على أي حال.
  Future<void> _askNotifications() async {
    if (!mounted) return;
    if (await Notifications.asked) return;
    if (await Notifications.granted) {
      await Notifications.markAsked();
      return;
    }
    if (!mounted) return;
    await NotificationPermissionDialog.show(context);
  }

  @override
  void dispose() {
    _annTimer?.cancel();
    _chatTimer?.cancel();
    _settingsTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _cfg.removeListener(_onConfigChanged);
    VersionLock.instance.removeListener(_onVersionLocked);
    super.dispose();
  }

  /// الإصدار أُوقف والتطبيق مفتوح: ننتقل لشاشة التحديث فوراً.
  void _onVersionLocked() {
    if (!mounted) return;
    final msg = VersionLock.instance.message;
    if (msg == null) return;
    final u = AppConfig.instance;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => UpdateScreen(
                message: msg,
                url: u.updateUrl,
                imageUrl: u.updateImageUrl,
                apiBase: kApiBase,
              )),
      (r) => false,
    );
  }

  void _onConfigChanged() {
    if (!mounted) return;
    // الإيقاف قد يقع والمستخدم داخل الدورات؛ بقاؤه على تبويب أُزيل من
    // الشريط يتركه على شاشة لا مخرج لها.
    if (_cfg.videosHidden && _tab == 2) _tab = 0;
    setState(() {});
  }

  /// دورة الإعدادات: تجلب الحصة والإعدادات بلا إظهار أخطاء.
  ///
  /// _refresh تُظهر فشلاً للمستخدم حين تُستدعى من إجراء مباشر؛ الاستقصاء
  /// الدوري يجب أن يفشل بصمت كي لا يرى المستخدم تنبيهاً كل دقيقة عند
  /// انقطاع الشبكة.
  void _pollSettings() {
    if (!mounted) return;
    _refresh();
  }

  /// رسالة جاهزة على رابط تيليجرام — يتعامل مع رابط فيه استعلام مسبقاً.
  String _tgWithText(String msg) {
    final base = _cfg.telegram;
    final sep = base.contains('?') ? '&' : '?';
    return '$base${sep}text=${Uri.encodeComponent(msg)}';
  }

  Future<void> _refresh() async {
    try {
      // الإعدادات المشتركة تُجلب في التوازي مع الحصة.
      final results = await Future.wait<Map<String, dynamic>>([
        widget.api.me(),
        widget.api.bootstrap(),
      ]);
      await _cfg.applyBootstrap(results[1]);
      // تسجيل رمز الدفع بعد نجاح المصادقة: الرمز يخصّ الجهاز لكن الربط
      // يخصّ المستخدم، فتسجيله قبل ظهور الجلسة يخزّنه بلا صاحب.
      Push.registerWith(widget.api);
      final m = results[0];
      // الخادم الجديد يرسل wallet؛ والقديم quota/cards/compatQuota. نقرأ
      // الجديد أولاً ونرجع للقديم عند غيابه كي لا يظهر صفر خاطئ.
      final w = m['wallet'] as Map?;
      // حالة الهديّة تأتي جاهزة من الخادم: الاستلام لا يُستنتج من ردّ خطأ.
      final g = m['gift'] as Map?;
      if (!mounted) return;
      if (w != null) {
        setState(() {
          _freeLeft = (w['freeLeft'] as num?)?.toInt() ?? 0;
          _freeLimit = (w['freeLimit'] as num?)?.toInt() ?? 0;
          _coins = (w['coins'] as num?)?.toInt() ?? 0;
          _cardExpiry = (w['expiresAt'] as num?)?.toInt() ?? 0;
          _giftEnabled = _cfg.hasGift;
          if (g != null) {
            _giftClaimed = g['claimed'] == true;
            _giftNextAt = (g['nextAt'] as num?)?.toInt() ?? 0;
          }
        });
        return;
      }
      final q = m['quota'] as Map?;
      final c = m['cards'] as Map?;
      setState(() {
        final limit = (q?['limit'] as num?)?.toInt() ?? 0;
        final used = (q?['used'] as num?)?.toInt() ?? 0;
        _freeLimit = limit < 0 ? 0 : limit;
        _freeLeft = limit < 0 ? 0 : (limit - used).clamp(0, limit);
        _coins = (c?['balance'] as num?)?.toInt() ?? 0;
        _cardExpiry = (c?['expiresAt'] as num?)?.toInt() ?? 0;
        _giftEnabled = _cfg.hasGift;
        if (g != null) {
          _giftClaimed = g['claimed'] == true;
          _giftNextAt = (g['nextAt'] as num?)?.toInt() ?? 0;
        }
      });
    } catch (_) {}
  }

  void refreshQuota() => _refresh();

  /// الهديّة كنافذة منبثقة لا كتبويب.
  ///
  /// الرصيد المعروض هنا هو محفظة المستخدم نفسها التي يعرضها الشريط العلوي:
  /// الحصّة المجانية المتبقية + العملات المشحونة. المالك قد يفتح رصيداً
  /// باشتراك أو بالعدد، وفي الحالتين نعرض المجموع المتاح الآن بدل رقم
  /// قديم محفوظ داخل الشاشة.
  Future<void> _openGift() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Container(
          decoration: BoxDecoration(
            color: XTheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: XTheme.surface2,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Row(children: [
                  const Icon(Icons.card_giftcard,
                      color: XTheme.gold, size: 20),
                  const SizedBox(width: 8),
                  const Text('هديّة اليوم',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              GiftScreen(
                amount: _cfg.dailyGift,
                claimed: _giftClaimed,
                nextAt: _giftNextAt,
                balance: _totalLeft,
                onClaim: () async {
                  final r = await _claimGiftForWheel();
                  // الرصيد الجديد يصل للشريط العلوي وللنافذة معاً: استلام
                  // الهديّة في تكرار مشابه كان يُظهر الرصيد قديماً حتى إغلاق
                  // الشاشة وإعادة فتحها.
                  await _refresh();
                  if (mounted) setSheet(() {});
                  return r;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.store.user;
    final isOwner = widget.store.isOwner;
    final isGuest = widget.store.isGuest;

    return PopScope(
      // في الدردشة يخرج زر الرجوع النظامي إلى الشرائط بدل إغلاق التطبيق،
      // وإلا بدا للمستخدم أن التطبيق أُغلق فجأة.
      canPop: !_chatOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _chatOpen) _exitChat();
      },
      child: Scaffold(
      // الدردشة تعمل بملء الشاشة تلقائياً: يُخفي الشريطين لتتسع مساحة
      // الرسائل، والرجوع يُعيدهما.
      appBar: _chatOpen
          ? null
          : AppBar(
        title: ShaderMask(
          shaderCallback: (b) =>
              XTheme.gradient.createShader(Rect.fromLTWH(0, 0, 120, 40)),
          child: const Text(kAppName,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                  color: Colors.white)),
        ),
        actions: [
          // العدّاد الموحّد — رقم واحد للجميع (زائر ومسجّل ومشترك): ما تبقّى
          // من المنحة اليومية + العملات. كان هناك ثلاثة عدّادات (توافقات،
          // مخططات، عملات) فيرى المستخدم أرقاماً متضاربة؛ الآن مرجع واحد لما
          // يُعرض وما يُخصم.
          if (!isOwner)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _showCardsInfo,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const CoinIcon(size: 17),
                  label: Text('$_totalLeft',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  backgroundColor: XTheme.gold.withOpacity(
                      _totalLeft > 0 ? .14 : .06),
                  side: BorderSide.none,
                ),
              ),
            ),
          // زر الهديّة: بجانب عدّاد العملات لأنه يزيده، ويفتح شاشة العجلة
          // مباشرة. الهديّة بلا تبويب في الشريط السفلي، فهذا هو مدخلها الوحيد.
          // مخفي عن المالك (رصيده مفتوح أصلاً) ويظهر لغيره.
          if (!isOwner && _giftEnabled)
            IconButton(
              tooltip: 'هديّة اليوم',
              icon: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    color: XTheme.gold.withOpacity(.16),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  _giftClaimed ? Icons.redeem : Icons.card_giftcard,
                  color: _giftClaimed ? XTheme.textDim : XTheme.gold,
                  size: 18,
                ),
              ),
              onPressed: _openGift,
            ),
          // زر + لشراء باقة — متاح للجميع (الزائر يُوجَّه لطلب حساب أولاً)
          IconButton(
            tooltip: 'شراء بطاقات',
            icon: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                  gradient: XTheme.gradient,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.add, color: Colors.white, size: 18),
            ),
            onPressed: _showPackages,
          ),
          const SizedBox(width: 6),
        ],
      ),
      drawer: _drawer(user, isOwner, isGuest),
      // بلا شريط علوي يتمدّد المحتوى تحت شريط الحالة، فنُزاح بمقدار الحافة
      // العليا في الدردشة وحدها.
      body: SafeArea(
        top: _chatOpen,
        bottom: false,
        child: IndexedStack(
          index: _tab,
          children: [
            CompatScreen(api: widget.api, store: widget.store, onCharged: refreshQuota),
            SchemScreen(api: widget.api, onFileOpened: refreshQuota),
            if (_cfg.videosHidden)
              const SizedBox.shrink()
            else
              CoursesScreen(api: widget.api),
            ChatScreen(
              api: widget.api,
              store: widget.store,
              onExit: _exitChat,
              openRoomId: _openRoomId,
              onRoomOpened: () {
                if (_openRoomId.isNotEmpty) setState(() => _openRoomId = '');
              },
              onRoomChanged: (id) {
                _activeRoomId = id;
                // فتح القسم يعني أن المستخدم رأى ما فيه، فيعود عدّاد
                // الإشعارات إلى الصفر بلا انتظار النبضة التالية.
                _chatUnread[id] = 0;
              },
            ),
          ],
        ),
      ),
      bottomNavigationBar: _chatOpen
          ? null
          : AnimatedNavBar(
              index: _navIndex,
              onSelect: (i) {
                // الضغط يعطي موضعاً داخل الشريط لا رقم التبويب: مع غياب
                // تبويب تنزاح الأرقام، والتحويل هنا يمنع فتح الشاشة الخطأ.
                final t = _navTabs[i];
                setState(() {
                  if (t != _chatTab) _lastNonChatTab = t;
                  _tab = t;
                });
              },
              items: _tabItems,
            ),
      ),
    );
  }

  Drawer _drawer(Map<String, dynamic>? user, bool isOwner, bool isGuest) {
    final name = isGuest
        ? 'زائر'
        : (user?['displayName']?.toString().isNotEmpty == true
            ? user!['displayName']
            : user?['username'] ?? '');
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // رأس الدرج: تدرّج الهوية + هالة ضوئية خفيفة تعطي عمقاً بدل
            // مستطيل ملوّن مسطّح.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              decoration: BoxDecoration(
                gradient: XTheme.gradient,
                boxShadow: XTheme.glow(XTheme.accent, strength: .8),
              ),
              child: Stack(
                children: [
                  // دائرة ضوئية باهتة — تلميح عمق بلا صورة خلفية ثقيلة
                  Positioned(
                    top: -46, left: -30,
                    child: Container(
                      width: 130, height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(.10),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.20),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(.45),
                                  width: 2),
                            ),
                            child: Icon(
                                isOwner
                                    ? Icons.shield_moon_outlined
                                    : (isGuest
                                        ? Icons.person_outline
                                        : Icons.person),
                                color: Colors.white,
                                size: 29),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white)),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(.22),
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                  child: Text(
                                    isOwner
                                        ? 'المالك'
                                        : (isGuest
                                            ? 'تصفح محدود'
                                            : (user?['role'] ?? 'مشترك')),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            if (isOwner)
              _item(Icons.dashboard_customize_outlined, 'لوحة تحكم المالك', () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        OwnerGate(api: widget.api, store: widget.store)));
              }, highlight: true),
            _item(Icons.send_rounded, 'تواصل مع المالك', () {
              openExternal(context, _cfg.telegram, label: 'تيليجرام');
            }),
            if (isGuest)
              _item(Icons.workspace_premium_outlined, 'اشترك — تصفح بلا حدود',
                  () {
                Navigator.pop(context);
                openAuth(context, widget.api, widget.store)
                    .then((_) => _refresh());
              }, highlight: true),
            if (!isGuest && !isOwner)
              _item(Icons.verified_user_outlined, 'حساب مفعّل', null),
            _deviceIdTile(),
            const SizedBox(height: 10),
            // تبديل الثيم — أسود / أبيض
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: AnimatedBuilder(
                animation: ThemeController.instance,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: XTheme.surface2,
                    borderRadius: BorderRadius.circular(XTheme.rMd),
                    border: Border.all(
                        color: XTheme.textDim.withOpacity(.14)),
                  ),
                  child: Row(
                    children: [
                      _themeBtn(false, Icons.dark_mode_rounded, 'داكن'),
                      _themeBtn(true, Icons.light_mode_rounded, 'فاتح'),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            Divider(height: 1, color: XTheme.textDim.withOpacity(.18)),
            _item(Icons.logout, isGuest ? 'تسجيل الدخول' : 'تسجيل الخروج',
                () async {
              Navigator.pop(context);
              if (isGuest) {
                await openAuth(context, widget.api, widget.store);
                _refresh();
                return;
              }
              await widget.store.clearSession();
              final g = await widget.api.guest();
              await widget.store.setToken(g['token']);
              await widget.store.setUser(g['user']);
              setState(() {});
            }),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('$kAppName • إصدار $kAppVersionName',
                  style: TextStyle(color: XTheme.textDim, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback? onTap,
      {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: ListTile(
        dense: true,
        // أيقونة في مربّع ملوّن — تعطي العنصر ثقلاً بصرياً بدل أيقونة عائمة
        leading: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient: highlight ? XTheme.gradient : null,
            color: highlight ? null : XTheme.surface2,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon,
              color: highlight ? Colors.white : XTheme.textDim, size: 18),
        ),
        title: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: highlight ? XTheme.accent : XTheme.text)),
        trailing: onTap == null
            ? null
            : Icon(Icons.chevron_left_rounded,
                size: 20, color: XTheme.textDim.withOpacity(.6)),
        onTap: onTap,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(XTheme.rMd)),
      ),
    );
  }

  /// معرّف الجهاز: يُعرض للجميع (زائر ومسجّل ومالك) لأنه الهوية التي
  /// يُطلب إرسالها للمالك عند تفعيل الحساب أو شحن البطاقات. زر النسخ
  /// يجعل إرساله في تيليجرام بلا أخطاء كتابة.
  Widget _deviceIdTile() {
    final id = widget.store.deviceId;
    if (id.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: InkWell(
        onTap: () => _copyDeviceId(id),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          decoration: BoxDecoration(
            color: XTheme.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: XTheme.textDim.withOpacity(.18)),
          ),
          child: Row(children: [
            Icon(Icons.phone_android, size: 19, color: XTheme.cyan),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('معرّف جهازك',
                      style: TextStyle(
                          fontSize: 12, color: XTheme.textDim)),
                  const SizedBox(height: 3),
                  Text(id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: XTheme.text,
                          letterSpacing: .3)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.copy_rounded, size: 18, color: XTheme.cyan),
          ]),
        ),
      ),
    );
  }

  Future<void> _copyDeviceId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ معرّف الجهاز')),
    );
  }

  /// معلومات رصيد البطاقات + تاريخ الصلاحية
  void _showCardsInfo() {
    final exp = _cardExpiry > 0
        ? DateTime.fromMillisecondsSinceEpoch(_cardExpiry)
        : null;
    final expired = exp != null && exp.isBefore(DateTime.now());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(Icons.account_balance_wallet_outlined, color: XTheme.cyan),
          const SizedBox(width: 8),
          const Text('رصيدك',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          // الرقم الكبير هو ما تبقّى فعلاً، لأن الخصم يقع على المجاني أولاً
          // ثم على العملات — فلا يفاجأ المستخدم بأن رصيده أكبر مما يُخصم.
          Text('$_totalLeft',
              style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: expired || _totalLeft <= 0
                      ? XTheme.danger
                      : XTheme.cyan)),
          Text('عملية متبقية',
              style: TextStyle(color: XTheme.textDim, fontSize: 12)),
          const SizedBox(height: 12),
          _walletRow('منحة اليوم', '$_freeLeft / $_freeLimit', XTheme.accent),
          const SizedBox(height: 6),
          _walletRow('عملات مشحونة', '$_coins',
              _coins > 0 ? XTheme.gold : XTheme.textDim),
          const SizedBox(height: 10),
          Text(
            exp == null
                ? 'عملاتك بلا تاريخ انتهاء'
                : (expired
                    ? 'انتهت صلاحية العملات في ${exp.toLocal().toString().split(' ').first}'
                    : 'عملاتك صالحة حتى ${exp.toLocal().toString().split(' ').first}'),
            style: TextStyle(
                color: expired ? XTheme.danger : XTheme.textDim,
                fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text('المنحة تتجدد كل يوم — تُخصم من المخططات والتوافقات معاً',
              textAlign: TextAlign.center,
              style: TextStyle(color: XTheme.textDim, fontSize: 11)),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: XTheme.accent,
                foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _showPackages();
            },
            child: const Text('شراء باقة'),
          ),
        ],
      ),
    );
  }

  Widget _walletRow(String label, String value, Color color) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: XTheme.textDim, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      );

  /// باقات البطاقات — الشراء عبر تيليجرام برسالة جاهزة
  void _showPackages() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: XTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
                left: 20, right: 20, top: 20,
                bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: XTheme.textDim.withOpacity(.4),
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 16),
            const Text('باقات بطاقات المخططات',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text('كل بطاقة = فتح مخطط واحد • الشراء عبر تيليجرام',
                style: TextStyle(color: XTheme.textDim, fontSize: 12)),
            const SizedBox(height: 16),
            if (_cfg.packages.isEmpty)
              Text('لا توجد باقات معروضة حالياً',
                  style: TextStyle(color: XTheme.textDim)),
            ..._cfg.packages.map((p) {
              final cards = (p['cards'] as num?)?.toInt() ?? 0;
              final price = p['price']?.toString() ?? '';
              final days = (p['days'] as num?)?.toInt() ?? 0;
              final desc = p['desc']?.toString() ?? '';
              final period = desc.isNotEmpty
                  ? desc
                  : days >= 365
                      ? 'صالحة سنة كاملة'
                      : days >= 150
                          ? 'صالحة 5 أشهر'
                          : 'صالحة شهرين';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GlassCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(
                      width: 52, height: 52,
                      decoration: BoxDecoration(
                          gradient: XTheme.gradient,
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: Text('$cards',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$cards بطاقة',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            Text('صالحة لغاية $period',
                                style: TextStyle(
                                    color: XTheme.textDim, fontSize: 11.5)),
                          ]),
                    ),
                    Column(children: [
                      Text(price,
                          style: TextStyle(
                              color: XTheme.gold,
                              fontWeight: FontWeight.w900,
                              fontSize: 16)),
                      const SizedBox(height: 4),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: XTheme.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            minimumSize: Size.zero),
                        onPressed: () => _buyPackage(cards, price),
                        child: const Text('شراء',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5)),
                      ),
                    ]),
                  ]),
                ),
              );
            }),
          ]),
          ),
        ),
      ),
    );
  }

  /// شراء باقة — مشترك: تيليجرام مباشرة باسم حسابه؛ زائر: طلب حساب ثم تيليجرام
  Future<void> _buyPackage(int cards, String price) async {
    if (widget.store.isGuest) {
      _registerAndBuy(cards, price);
      return;
    }
    final username = widget.store.user?['username']?.toString() ?? '';
    await openExternal(
        context,
        _tgWithText(
            'مرحباً، أنا المشترك $username — أريد شحن باقة $cards بطاقة مخططات بسعر $price'),
        label: 'تيليجرام');
  }

  /// الزائر: يطلب حساباً أولاً ثم يُوجَّه لتيليجرام برسالة تتضمن طلبه + الباقة
  void _registerAndBuy(int cards, String price) {
    final user = TextEditingController();
    final pass = TextEditingController();
    final name = TextEditingController();
    bool sending = false;
    showDialog(
      context: context,
      barrierDismissible: !sending,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: XTheme.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22)),
          title: const Text('طلب حساب + باقة',
              style:
                  TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                'ستطلب حساباً وباقة $cards بطاقة بسعر $price — يوافق عليها المالك',
                style: TextStyle(color: XTheme.textDim, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
                controller: user,
                decoration:
                    const InputDecoration(labelText: 'اسم المستخدم'),
                textDirection: TextDirection.ltr),
            const SizedBox(height: 10),
            TextField(
                controller: pass,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'كلمة المرور'),
                textDirection: TextDirection.ltr),
            const SizedBox(height: 10),
            TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'الاسم (اختياري)')),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: XTheme.accent,
                  foregroundColor: Colors.white),
              onPressed: sending
                  ? null
                  : () async {
                      setD(() => sending = true);
                      try {
                        await widget.api.register(
                            user.text.trim(),
                            pass.text,
                            name.text.trim(),
                            'طلب باقة $cards بطاقة — $price');
                        if (ctx.mounted) Navigator.pop(ctx);
                        await openExternal(
                            context,
                            _tgWithText(
                                'مرحباً، أنا ${user.text.trim()} — طلبت حساباً في تطبيق X وأريد باقة $cards بطاقة مخططات بسعر $price'),
                            label: 'تيليجرام');
                      } on ApiException catch (e) {
                        setD(() => sending = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.message)));
                        }
                      }
                    },
              child: sending
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('إرسال الطلب'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _themeBtn(bool light, IconData icon, String label) {
    final active = ThemeController.instance.isLight == light;
    return Expanded(
      child: GestureDetector(
        onTap: () => ThemeController.instance.setLight(light),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: active ? XTheme.gradient : null,
            borderRadius: BorderRadius.circular(11),
            boxShadow:
                active ? XTheme.glow(XTheme.accent, strength: .5) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: active ? Colors.white : XTheme.textDim),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : XTheme.textDim)),
            ],
          ),
        ),
      ),
    );
  }
}
