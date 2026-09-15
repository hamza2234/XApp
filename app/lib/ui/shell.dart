import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/store.dart';
import 'theme.dart';
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
      final b = await widget.api.bootstrap();
      if (mounted) {
        setState(() {
          _quotaUsed = (q?['used'] as num?)?.toInt() ?? 0;
          _quotaLimit = (q?['limit'] as num?)?.toInt() ?? -1;
          final s = b['settings'];
          if (s is Map && (s['telegramLink'] ?? '').toString().isNotEmpty) {
            _telegram = s['telegramLink'];
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
          if (isGuest && _quotaLimit > 0)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Chip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.bolt, size: 16, color: XTheme.gold),
                label: Text(
                    '${(_quotaLimit - _quotaUsed).clamp(0, _quotaLimit)}/$_quotaLimit',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                backgroundColor: XTheme.gold.withOpacity(.12),
                side: BorderSide.none,
              ),
            ),
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
              decoration: const BoxDecoration(gradient: XTheme.gradient),
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
            const Padding(
              padding: EdgeInsets.all(14),
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
}
