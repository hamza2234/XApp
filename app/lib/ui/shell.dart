import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/app_config.dart';
import '../core/notifications.dart';
import '../core/store.dart';
import 'theme.dart';
import 'nav_bar.dart';
import 'brand_logo.dart';
import 'chat_screen.dart';
import 'compat_screen.dart';
import 'schem_screen.dart';
import 'owner_gate.dart';
import 'splash.dart';
import 'external_link.dart';

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
  // العدّاد الموحّد: منحة يومية + رصيد عملات، مصدره /v1/me وحده.
  int _freeLeft = 0;
  int _freeLimit = 0;
  int _coins = 0;
  int _cardExpiry = 0;
  // الإعدادات المشتركة: رابط تيليجرام والباقات من مصدر واحد.
  AppConfig get _cfg => AppConfig.instance;

  /// فحص دوري للإعلانات الجديدة. لا دفع حقيقي (FCM) في هذا المشروع،
  /// فالاستقصاء هو الوسيلة المتاحة لإبلاغ الأجهزة الأخرى.
  Timer? _annTimer;

  /// ما تبقّى فعلاً = المجاني اليومي + العملات. رقم واحد يُعرض ويُخصم.
  int get _totalLeft => _freeLeft + _coins;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // إعادة البناء فوراً إن وصل تحديث للرابط أو الباقات.
    _cfg.addListener(_onConfigChanged);
    _refresh();
    // طلب إذن الإشعارات بعد استقرار الشاشة الأولى، لا أثناءها: نافذة
    // النظام فوق شاشة التهيئة تبدو خللاً، وتُرفض بلا قراءة.
    WidgetsBinding.instance.addPostFrameCallback((_) => _askNotifications());
    _annTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => _pollAnnouncements());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // العودة إلى التطبيق أهمّ لحظة: المستخدم ينظر إلى الشاشة الآن.
    if (state == AppLifecycleState.resumed) _pollAnnouncements();
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
    WidgetsBinding.instance.removeObserver(this);
    _cfg.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
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
      final m = results[0];
      // الخادم الجديد يرسل wallet؛ والقديم quota/cards/compatQuota. نقرأ
      // الجديد أولاً ونرجع للقديم عند غيابه كي لا يظهر صفر خاطئ.
      final w = m['wallet'] as Map?;
      if (!mounted) return;
      if (w != null) {
        setState(() {
          _freeLeft = (w['freeLeft'] as num?)?.toInt() ?? 0;
          _freeLimit = (w['freeLimit'] as num?)?.toInt() ?? 0;
          _coins = (w['coins'] as num?)?.toInt() ?? 0;
          _cardExpiry = (w['expiresAt'] as num?)?.toInt() ?? 0;
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
      });
    } catch (_) {}
  }

  void refreshQuota() => _refresh();

  @override
  Widget build(BuildContext context) {
    final user = widget.store.user;
    final isOwner = widget.store.isOwner;
    final isGuest = widget.store.isGuest;

    return Scaffold(
      appBar: AppBar(
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
      body: IndexedStack(
        index: _tab,
        children: [
          CompatScreen(api: widget.api, store: widget.store),
          SchemScreen(api: widget.api, onFileOpened: refreshQuota),
          ChatScreen(api: widget.api, store: widget.store),
        ],
      ),
      bottomNavigationBar: AnimatedNavBar(
        index: _tab,
        onSelect: (i) => setState(() => _tab = i),
        items: const [
          NavItem(
              icon: Icons.hub_outlined,
              activeIcon: Icons.hub,
              label: 'التوافقات'),
          NavItem(
              icon: Icons.schema_outlined,
              activeIcon: Icons.schema,
              label: 'المخططات'),
          NavItem(
              icon: Icons.forum_outlined,
              activeIcon: Icons.forum,
              label: 'الدردشة'),
        ],
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
