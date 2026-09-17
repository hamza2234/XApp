import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/store.dart';
import 'theme.dart';
import 'brand_logo.dart';
import 'compat_screen.dart';
import 'schem_screen.dart';
import 'owner_screen.dart';
import 'splash.dart';

/// الهيكل الرئيسي: شريط تنقل سفلي + قائمة جانبية
class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, required this.store});
  final Api api;
  final Store store;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  int _quotaUsed = 0;
  int _quotaLimit = -1;
  int? _cards;
  int _cardExpiry = 0;
  List<dynamic> _packages = const [];
  String _telegram = 'https://t.me/phonex6';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final m = await widget.api.me();
      final q = m['quota'] as Map?;
      final c = m['cards'] as Map?;
      final b = await widget.api.bootstrap();
      if (mounted) {
        setState(() {
          _quotaUsed = (q?['used'] as num?)?.toInt() ?? 0;
          _quotaLimit = (q?['limit'] as num?)?.toInt() ?? -1;
          _cards = c == null ? null : (c['balance'] as num?)?.toInt() ?? 0;
          _cardExpiry = (c?['expiresAt'] as num?)?.toInt() ?? 0;
          final s = b['settings'];
          if (s is Map) {
            if ((s['telegramLink'] ?? '').toString().isNotEmpty) {
              _telegram = s['telegramLink'];
            }
            if (s['packages'] is List) _packages = s['packages'];
          }
        });
      }
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
          child: const Text('X',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white)),
        ),
        actions: [
          // شريحة الحصة/البطاقات — قابلة للضغط لفتح الباقات
          if (isGuest && _quotaLimit > 0)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _showPackages,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const CoinIcon(size: 17),
                  label: Text(
                      '${(_quotaLimit - _quotaUsed).clamp(0, _quotaLimit)}/$_quotaLimit',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  backgroundColor: XTheme.gold.withOpacity(.12),
                  side: BorderSide.none,
                ),
              ),
            ),
          if (!isGuest && !isOwner && _cards != null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _showCardsInfo,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const CoinIcon(size: 17),
                  label: Text('$_cards',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  backgroundColor: XTheme.gold.withOpacity(.14),
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
          CompatScreen(api: widget.api),
          SchemScreen(api: widget.api, onFileOpened: refreshQuota),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.hub_outlined),
              selectedIcon: Icon(Icons.hub),
              label: 'التوافقات'),
          NavigationDestination(
              icon: Icon(Icons.schema_outlined),
              selectedIcon: Icon(Icons.schema),
              label: 'المخططات'),
        ],
      ),
    );
  }

  Drawer _drawer(Map<String, dynamic>? user, bool isOwner, bool isGuest) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(gradient: XTheme.gradient),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isGuest
                        ? 'زائر'
                        : (user?['displayName']?.toString().isNotEmpty == true
                            ? user!['displayName']
                            : user?['username'] ?? ''),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white),
                  ),
                  Text(
                    isGuest ? 'تصفح محدود' : (user?['role'] ?? ''),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (isOwner)
              _item(Icons.dashboard_customize_outlined, 'لوحة تحكم المالك', () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        OwnerScreen(api: widget.api, store: widget.store)));
              }, highlight: true),
            _item(Icons.send_rounded, 'تواصل مع المالك', () async {
              final uri = Uri.parse(_telegram);
              if (await canLaunchUrl(uri)) launchUrl(uri);
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
            const SizedBox(height: 8),
            // تبديل الثيم — أسود / أبيض
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: AnimatedBuilder(
                animation: ThemeController.instance,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: XTheme.surface2,
                    borderRadius: BorderRadius.circular(14),
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
            const Divider(height: 1),
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
              child: Text('X • إصدار 1.0.0',
                  style: TextStyle(color: XTheme.textDim, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, VoidCallback? onTap,
      {bool highlight = false}) {
    return ListTile(
      leading: Icon(icon,
          color: highlight ? XTheme.cyan : XTheme.textDim, size: 22),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: highlight ? XTheme.cyan : XTheme.text)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          Icon(Icons.confirmation_number_outlined, color: XTheme.cyan),
          const SizedBox(width: 8),
          const Text('بطاقاتك',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('$_cards',
              style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: expired || (_cards ?? 0) <= 0
                      ? XTheme.danger
                      : XTheme.cyan)),
          Text('بطاقة عرض مخططات',
              style: TextStyle(color: XTheme.textDim, fontSize: 12)),
          const SizedBox(height: 10),
          Text(
            exp == null
                ? 'بلا تاريخ انتهاء'
                : (expired
                    ? 'انتهت الصلاحية في ${exp.toLocal().toString().split(' ').first}'
                    : 'صالحة حتى ${exp.toLocal().toString().split(' ').first}'),
            style: TextStyle(
                color: expired ? XTheme.danger : XTheme.textDim,
                fontSize: 12),
          ),
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
            if (_packages.isEmpty)
              Text('لا توجد باقات معروضة حالياً',
                  style: TextStyle(color: XTheme.textDim)),
            ..._packages.map((p) {
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
    final msg = Uri.encodeComponent(
        'مرحباً، أنا المشترك $username — أريد شحن باقة $cards بطاقة مخططات بسعر $price');
    final uri = Uri.parse('$_telegram?text=$msg');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
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
                        final msg = Uri.encodeComponent(
                            'مرحباً، أنا ${user.text.trim()} — طلبت حساباً في تطبيق X وأريد باقة $cards بطاقة مخططات بسعر $price');
                        final uri = Uri.parse('$_telegram?text=$msg');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
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
