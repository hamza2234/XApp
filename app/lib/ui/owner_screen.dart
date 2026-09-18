import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/api.dart';
import '../core/app_config.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';
import 'biometric_gate.dart';
import 'brand_logo.dart';

/// نسخ معرّف الجهاز — يُستخدم من عدة تبويبات في لوحة المالك.
Future<void> copyDeviceId(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم نسخ معرّف الجهاز')));
}

/// لوحة تحكم المالك — تظهر فقط لحساب role=owner
/// التحكم: حصة الزائر، الإصدارات، المستخدمون، الطلبات، سجل الأمان، الإعلانات
class OwnerScreen extends StatefulWidget {
  const OwnerScreen({super.key, required this.api, required this.store});
  final Api api;
  final Store store;

  @override
  State<OwnerScreen> createState() => _OwnerScreenState();
}

class _OwnerScreenState extends State<OwnerScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('لوحة تحكم المالك'),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: XTheme.cyan,
            labelStyle:
                TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            tabs: [
              Tab(text: 'عام', icon: Icon(Icons.analytics_outlined, size: 18)),
              Tab(text: 'الإعدادات', icon: Icon(Icons.tune, size: 18)),
              Tab(text: 'المستخدمون', icon: Icon(Icons.people_outline, size: 18)),
              Tab(text: 'محافظ الزوار', icon: Icon(Icons.account_balance_wallet_outlined, size: 18)),
              Tab(text: 'الإعلانات', icon: Icon(Icons.campaign_outlined, size: 18)),
              Tab(text: 'الدردشة', icon: Icon(Icons.forum_outlined, size: 18)),
              Tab(text: 'الحظر', icon: Icon(Icons.gpp_bad_outlined, size: 18)),
              Tab(text: 'الأمان', icon: Icon(Icons.security, size: 18)),
            ],
          ),
        ),
        body: TabBarView(children: [
          _OverviewTab(api: widget.api),
          _SettingsTab(api: widget.api),
          _UsersTab(api: widget.api),
          _WalletsTab(api: widget.api),
          _AnnouncementsTab(api: widget.api),
          _ChatTab(api: widget.api),
          _BansTab(api: widget.api),
          _SecurityTab(api: widget.api),
        ]),
      ),
    );
  }
}

// ============ نظرة عامة ============

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.api});
  final Api api;
  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Map<String, dynamic>? _data;
  List<dynamic> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await widget.api.ownerOverview();
      final r = await widget.api.ownerRequests();
      if (mounted) {
        setState(() {
          _data = d;
          _requests = r;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return Center(
          child: CircularProgressIndicator(color: XTheme.accent));
    }
    final d = _data!;
    return RefreshIndicator(
      onRefresh: _load,
      color: XTheme.accent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _stat('التثبيتات', '${d['installs']}', Icons.download_rounded,
                  XTheme.accent),
              _stat('المستخدمون', '${d['users']}', Icons.people_alt_outlined,
                  XTheme.cyan),
              _stat('طلبات معلّقة', '${d['pendingRequests']}',
                  Icons.pending_actions, XTheme.gold),
              _stat('أحداث أمنية (24س)', '${d['securityEvents24h']}',
                  Icons.shield_outlined, XTheme.danger),
            ],
          ),
          const SizedBox(height: 16),
          if ((d['installsByVersion'] as List?)?.isNotEmpty == true) ...[
            const Text('التثبيتات حسب الإصدار',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            ...(d['installsByVersion'] as List).map((v) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Icon(Icons.phone_android,
                          size: 18, color: XTheme.textDim),
                      const SizedBox(width: 10),
                      Expanded(child: Text('إصدار ${v['v']}')),
                      Text('${v['c']}',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: XTheme.cyan)),
                    ]),
                  ),
                )),
          ],
          const SizedBox(height: 16),
          if (_requests.isNotEmpty) ...[
            const Text('طلبات إنشاء الحسابات',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            ..._requests.where((r) => r['status'] == 'pending').map((r) =>
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      Icon(Icons.person_add_alt,
                          color: XTheme.gold, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r['username'] ?? '',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              if ((r['note'] ?? '').toString().isNotEmpty)
                                Text(r['note'],
                                    style: TextStyle(
                                        color: XTheme.textDim, fontSize: 12)),
                              Text('جهاز: ${r['device_id'] ?? '—'}',
                                  style: TextStyle(
                                      color: XTheme.textDim, fontSize: 10)),
                            ]),
                      ),
                      if ((r['device_id'] ?? '').toString().isNotEmpty)
                        IconButton(
                            tooltip: 'نسخ معرّف الجهاز',
                            onPressed: () =>
                                copyDeviceId(context, '${r['device_id']}'),
                            icon: Icon(Icons.copy_rounded,
                                size: 18, color: XTheme.cyan)),
                      IconButton(
                          onPressed: () => _act(r['id'], 'approve'),
                          icon: Icon(Icons.check_circle,
                              color: XTheme.ok)),
                      IconButton(
                          onPressed: () => _act(r['id'], 'reject'),
                          icon:
                              Icon(Icons.cancel, color: XTheme.danger)),
                    ]),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _act(String id, String action) async {
    try {
      await widget.api.requestAction(id, action);
      _load();
    } catch (_) {}
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w900)),
          Text(label,
              style:
                  TextStyle(color: XTheme.textDim, fontSize: 12)),
        ],
      ),
    );
  }
}

// ============ الإعدادات ============

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.api});
  final Api api;
  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  XSettings? _s;
  bool _saving = false;
  String? _msg;
  final _telegram = TextEditingController();
  final _minVer = TextEditingController();
  final _blockVer = TextEditingController();
  final _updMsg = TextEditingController();
  final _updUrl = TextEditingController();
  final _updImg = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.ownerSettings();
      if (mounted) {
        setState(() {
          _s = XSettings.fromJson(r['settings']);
          _telegram.text = _s!.telegramLink;
          _minVer.text = '${_s!.minVersion}';
          _updMsg.text = _s!.updateMessage;
          _updUrl.text = _s!.updateUrl;
          _updImg.text = _s!.updateImageUrl;
        });
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      _s!.telegramLink = _telegram.text.trim();
      _s!.minVersion = int.tryParse(_minVer.text.trim()) ?? 1;
      _s!.updateMessage = _updMsg.text.trim();
      _s!.updateUrl = _updUrl.text.trim();
      _s!.updateImageUrl = _updImg.text.trim();
      final r = await widget.api.saveSettings(_s!.toJson());
      final saved = XSettings.fromJson(r['settings']);
      // تُطبَّق فوراً على التطبيق كله بلا انتظار دورة تحديث.
      await AppConfig.instance.applyOwnerSettings(
        telegram: saved.telegramLink,
        packages: saved.packages
            .map((p) => {
                  'cards': p.cards,
                  'price': p.price,
                  'days': p.days,
                  'desc': p.desc,
                })
            .toList(),
        dailyFree: saved.dailyFreeQuota,
      );
      setState(() {
        _s = saved;
        _msg = 'تم الحفظ';
      });
    } catch (_) {
      setState(() => _msg = 'فشل الحفظ');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_s == null) {
      return Center(
          child: CircularProgressIndicator(color: XTheme.accent));
    }
    final s = _s!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.bolt, color: XTheme.gold, size: 20),
                SizedBox(width: 8),
                Text('المنحة اليومية للجميع',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 6),
              Text(
                  'عدد العمليات المجانية يومياً لكل مستخدم — زائر ومسجّل ومشترك. '
                  'عدّاد واحد يُخصم منه فتح المخططات ودخول الشركات في التوافقات.',
                  style: TextStyle(color: XTheme.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Slider(
                    value: s.dailyFreeQuota.toDouble().clamp(0, 50),
                    max: 50,
                    divisions: 50,
                    onChanged: (v) =>
                        setState(() => s.dailyFreeQuota = v.round()),
                  ),
                ),
                Container(
                  width: 52,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                      color: XTheme.gold.withOpacity(.12),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('${s.dailyFreeQuota}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: XTheme.gold,
                          fontSize: 17)),
                ),
              ]),
              if (s.dailyFreeQuota == 0)
                Text('صفر يعني بلا منحة مجانية — العملات وحدها تعمل',
                    style: TextStyle(color: XTheme.danger, fontSize: 11.5)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.system_update_alt,
                    color: XTheme.cyan, size: 20),
                SizedBox(width: 8),
                Text('التحكم بالإصدارات',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _minVer,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'أدنى إصدار مسموح (versionCode)',
                    isDense: true),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _blockVer,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'إيقاف إصدار محدد', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () {
                    final v = int.tryParse(_blockVer.text.trim());
                    if (v != null && !s.blockedVersions.contains(v)) {
                      setState(() {
                        s.blockedVersions.add(v);
                        _blockVer.clear();
                      });
                    }
                  },
                  icon: const Icon(Icons.block, size: 18),
                  style: IconButton.styleFrom(
                      backgroundColor: XTheme.danger.withOpacity(.15),
                      foregroundColor: XTheme.danger),
                ),
              ]),
              if (s.blockedVersions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: s.blockedVersions
                      .map((v) => Chip(
                            label: Text('v$v'),
                            deleteIcon:
                                const Icon(Icons.close, size: 16),
                            onDeleted: () => setState(
                                () => s.blockedVersions.remove(v)),
                            backgroundColor:
                                XTheme.danger.withOpacity(.12),
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(children: [
            _switch('قفل المخططات عن الزوار',
                'الزائر يحتاج حساباً مفعّلاً لعرض المخططات',
                s.schematicsLocked,
                (v) => setState(() => s.schematicsLocked = v)),
            const Divider(height: 20),
            _switch('قفل التوافقات عن الزوار',
                'الزائر يحتاج حساباً مفعّلاً لعرض التوافقات',
                s.compatLocked,
                (v) => setState(() => s.compatLocked = v)),
            const Divider(height: 20),
            // ثمن دخول الشركة — نفس عملة المنحة والعملات، يضبطه المالك.
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ثمن دخول الشركة',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          s.compatSearchCost == 0
                              ? 'مجاني — بلا خصم'
                              : 'يُخصم ${s.compatSearchCost} من العملات عند دخول شركة '
                                  'بعد نفاد المنحة اليومية',
                          style: TextStyle(
                              color: XTheme.textDim, fontSize: 12)),
                    ]),
              ),
              IconButton(
                onPressed: s.compatSearchCost <= 0
                    ? null
                    : () => setState(() => s.compatSearchCost--),
                icon: const Icon(Icons.remove_circle_outline, size: 20),
              ),
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                    color: XTheme.gold.withOpacity(.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Text('${s.compatSearchCost}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: XTheme.gold,
                        fontSize: 16)),
              ),
              IconButton(
                onPressed: s.compatSearchCost >= 100
                    ? null
                    : () => setState(() => s.compatSearchCost++),
                icon: const Icon(Icons.add_circle_outline, size: 20),
              ),
            ]),
            const Divider(height: 20),
            _switch('قفل التطبيق كلياً',
                'إيقاف التطبيق لجميع المستخدمين (صيانة)', s.appLocked,
                (v) => setState(() => s.appLocked = v)),
          ]),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.new_releases_outlined,
                    color: XTheme.gold, size: 20),
                SizedBox(width: 8),
                Text('شاشة التحديث الإجباري',
                    style: TextStyle(fontWeight: FontWeight.w900)),
              ]),
              const SizedBox(height: 6),
              Text(
                  'تظهر للمستخدمين عند إيقاف إصدارهم أو رفع الحد الأدنى',
                  style: TextStyle(color: XTheme.textDim, fontSize: 12)),
              const SizedBox(height: 12),
              TextField(
                controller: _updMsg,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'رسالة التحديث', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _updUrl,
                decoration: const InputDecoration(
                    labelText: 'رابط زر التحديث (APK/متجر)',
                    isDense: true),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _updImg,
                decoration: const InputDecoration(
                    labelText: 'رابط صورة التحديث (اختياري)',
                    isDense: true),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // محرر باقات البطاقات — السعر والصلاحية والوصف والعدد
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const CoinIcon(size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('باقات بطاقات المخططات',
                      style:
                          TextStyle(fontWeight: FontWeight.w900)),
                ),
                IconButton(
                  tooltip: 'إضافة باقة',
                  icon: Icon(Icons.add_circle,
                      color: XTheme.cyan, size: 22),
                  onPressed: () => _packageDialog(-1),
                ),
              ]),
              Text('تظهر للمستخدم عند ضغط زر + لشراء البطاقات',
                  style: TextStyle(
                      color: XTheme.textDim, fontSize: 11)),
              const SizedBox(height: 6),
              ...s.packages.asMap().entries.map((e) {
                final i = e.key;
                final p = e.value;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CoinIcon(size: 18),
                  title: Text('${p.cards} بطاقة — ${p.price}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 13.5)),
                  subtitle: Text(
                      '${p.days > 0 ? '${p.days} يوم' : 'بلا انتهاء'}${p.desc.isNotEmpty ? ' • ${p.desc}' : ''}',
                      style: TextStyle(
                          color: XTheme.textDim, fontSize: 11)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: Icon(Icons.edit_outlined,
                              size: 19, color: XTheme.accent),
                          onPressed: () => _packageDialog(i)),
                      IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 19, color: XTheme.danger),
                          onPressed: () =>
                              setState(() => s.packages.removeAt(i))),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: TextField(
            controller: _telegram,
            decoration: const InputDecoration(
                labelText: 'رابط تيليجرام المالك',
                prefixIcon: Icon(Icons.send_rounded)),
            textDirection: TextDirection.ltr,
          ),
        ),
        const SizedBox(height: 18),
        if (_msg != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_msg!,
                textAlign: TextAlign.center,
                style: TextStyle(color: XTheme.ok)),
          ),
        _OwnerPanelSecurity(),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
                gradient: XTheme.gradient,
                borderRadius: BorderRadius.circular(XTheme.rMd),
                boxShadow: XTheme.glow(XTheme.accent, strength: .6)),
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(XTheme.rMd)),
              ),
              child: Text(_saving ? 'جاري الحفظ…' : 'حفظ الإعدادات',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ),
        ),
      ],
    );
  }

  /// حوار تحرير/إضافة باقة — index -1 = باقة جديدة
  void _packageDialog(int index) {
    final p = index >= 0 ? _s!.packages[index] : XPackage();
    final cards = TextEditingController(text: index >= 0 ? '${p.cards}' : '');
    final price = TextEditingController(text: p.price);
    final days = TextEditingController(text: index >= 0 ? '${p.days}' : '');
    final desc = TextEditingController(text: p.desc);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(index >= 0 ? 'تحرير باقة' : 'باقة جديدة',
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: cards,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'عدد البطاقات')),
            const SizedBox(height: 10),
            TextField(
                controller: price,
                decoration: const InputDecoration(
                    labelText: 'السعر (مثال: 3\$)')),
            const SizedBox(height: 10),
            TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'الصلاحية بالأيام (0 = بلا انتهاء)')),
            const SizedBox(height: 10),
            TextField(
                controller: desc,
                decoration: const InputDecoration(
                    labelText: 'الوصف (مثال: صالحة شهرين)')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: XTheme.accent,
                foregroundColor: Colors.white),
            onPressed: () {
              final c = int.tryParse(cards.text) ?? 0;
              if (c <= 0) return;
              final np = XPackage(
                  cards: c,
                  price: price.text.trim(),
                  days: int.tryParse(days.text) ?? 0,
                  desc: desc.text.trim());
              setState(() {
                if (index >= 0) {
                  _s!.packages[index] = np;
                } else {
                  _s!.packages.add(np);
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Widget _switch(
      String title, String sub, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub,
          style: TextStyle(color: XTheme.textDim, fontSize: 11)),
      value: value,
      onChanged: onChanged,
      activeColor: XTheme.cyan,
    );
  }
}

// ============ المستخدمون ============

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.api});
  final Api api;
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<dynamic>? _users;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await widget.api.ownerUsers();
      if (mounted) setState(() => _users = u);
    } catch (_) {}
  }

  Future<void> _act(String id, String action, {int? days}) async {
    try {
      await widget.api.userAction(id, action, days: days);
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _addUserDialog() {
    final user = TextEditingController();
    final pass = TextEditingController();
    final name = TextEditingController();
    final days = TextEditingController(text: '30');
    final cards = TextEditingController(text: '150');
    final cardDays = TextEditingController(text: '60');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('إنشاء حساب مشترك',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: user,
              decoration:
                  const InputDecoration(labelText: 'اسم المستخدم'),
              textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextField(
              controller: pass,
              decoration:
                  const InputDecoration(labelText: 'كلمة المرور'),
              textDirection: TextDirection.ltr),
          const SizedBox(height: 10),
          TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: 'الاسم (اختياري)')),
          const SizedBox(height: 10),
          TextField(
              controller: days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'مدة الاشتراك بالأيام (0 = بلا انتهاء)')),
          const SizedBox(height: 10),
          TextField(
              controller: cards,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'عدد بطاقات المخططات')),
          const SizedBox(height: 10),
          TextField(
              controller: cardDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'صلاحية البطاقات بالأيام (0 = بلا انتهاء)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: XTheme.accent,
                foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await widget.api.createUser(
                    user.text.trim(), pass.text, name.text.trim(),
                    int.tryParse(days.text) ?? 0,
                    cards: int.tryParse(cards.text) ?? 0,
                    cardDays: int.tryParse(cardDays.text) ?? 0);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } on ApiException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addUserDialog,
        backgroundColor: XTheme.accent,
        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
        label: const Text('حساب جديد',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: _users == null
          ? Center(
              child: CircularProgressIndicator(color: XTheme.accent))
          : _users!.isEmpty
              ? Center(
                  child: Text('لا يوجد مستخدمون',
                      style: TextStyle(color: XTheme.textDim)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: XTheme.accent,
                  child: _list(),
    ));
  }

  /// حوار شحن بطاقات مخططات لمستخدم — يُنفَّذ في السيرفر فقط
  void _quotaDialog(Map<String, dynamic> u) {
    final cards = TextEditingController(text: '150');
    final days = TextEditingController(text: '60');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('شحن بطاقات — ${u['username']}',
            style: const TextStyle(
                fontWeight: FontWeight.w900, fontSize: 16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('الرصيد الحالي: ${u['quota_balance'] ?? 0} بطاقة',
              style: TextStyle(color: XTheme.textDim, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(
              controller: cards,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'عدد البطاقات المضافة')),
          const SizedBox(height: 10),
          TextField(
              controller: days,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'صلاحية البطاقات بالأيام (0 = بلا انتهاء)')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: XTheme.accent,
                foregroundColor: Colors.white),
            onPressed: () async {
              try {
                await widget.api.grantQuota(
                    u['id'],
                    int.tryParse(cards.text) ?? 0,
                    int.tryParse(days.text) ?? 0);
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } on ApiException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('شحن'),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    return ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _users!.length,
        itemBuilder: (context, i) {
          final u = _users![i];
          final active = u['active'] == 1;
          final isOwner = u['role'] == 'owner';
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor:
                      (active ? XTheme.ok : XTheme.danger).withOpacity(.14),
                  child: Icon(
                      isOwner ? Icons.shield : Icons.person,
                      color: active ? XTheme.ok : XTheme.danger,
                      size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u['username'] ?? '',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800)),
                        Text(
                            '${u['role']} • ${active ? 'مفعّل' : 'موقوف'} • جهاز: ${u['device_id'] ?? '—'}',
                            style: TextStyle(
                                color: XTheme.textDim, fontSize: 11)),
                        if (!isOwner)
                          Text(
                            'بطاقات: ${u['quota_balance'] ?? 0}'
                            '${(u['quota_expires_at'] ?? 0) > 0 ? ' • حتى ${DateTime.fromMillisecondsSinceEpoch(u['quota_expires_at']).toLocal().toString().split(' ').first}' : ''}',
                            style: TextStyle(
                                color: XTheme.cyan, fontSize: 11)),
                      ]),
                ),
                if ((u['device_id'] ?? '').toString().isNotEmpty)
                  IconButton(
                      tooltip: 'نسخ معرّف الجهاز',
                      onPressed: () =>
                          copyDeviceId(context, '${u['device_id']}'),
                      icon: Icon(Icons.copy_rounded,
                          size: 18, color: XTheme.cyan)),
                if (!isOwner)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        color: XTheme.textDim),
                    color: XTheme.surface2,
                    onSelected: (a) {
                      if (a == 'extend') {
                        _act(u['id'], 'extend', days: 30);
                      } else if (a == 'quota') {
                        _quotaDialog(u);
                      } else {
                        _act(u['id'], a);
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: active ? 'deactivate' : 'activate',
                          child: Text(active ? 'إيقاف' : 'تفعيل')),
                      const PopupMenuItem(
                          value: 'quota',
                          child: Text('شحن بطاقات مخططات')),
                      const PopupMenuItem(
                          value: 'extend',
                          child: Text('تمديد 30 يوم')),
                      const PopupMenuItem(
                          value: 'reset-device',
                          child: Text('فك ربط الجهاز')),
                      const PopupMenuItem(
                          value: 'delete', child: Text('حذف')),
                    ],
                  ),
              ]),
            ),
          );
        },
      );
  }
}

// ============ سجل الأمان ============

class _SecurityTab extends StatefulWidget {
  const _SecurityTab({required this.api});
  final Api api;
  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  List<dynamic>? _events;

  /// افتراضياً تُعرض الهجمات فقط؛ التبديل يكشف الأحداث الروتينية عند الحاجة.
  bool _attacksOnly = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final e = await widget.api.ownerSecurity(all: !_attacksOnly);
      if (mounted) setState(() => _events = e);
    } catch (_) {}
  }

  static const _labels = {
    'bad_signature': ('توقيع مزوّر', XTheme.danger),
    'missing_signature': ('طلب بلا توقيع', XTheme.danger),
    'stale_signature': ('توقيع منتهي', XTheme.gold),
    'rate_limited': ('هجوم طلبات مكثفة', XTheme.danger),
    'device_mismatch': ('حساب من جهاز غريب', XTheme.gold),
    'device_farm': ('مزرعة أجهزة', XTheme.danger),
    'bad_login': ('دخول فاشل', XTheme.gold),
    'bad_owner_key': ('مفتاح مالك خاطئ', XTheme.danger),
    'ip_hardban': ('حظر IP تلقائي', XTheme.danger),
    'non_owner_admin_attempt': ('محاولة وصول للوحة', XTheme.danger),
    'guest_token_device_mismatch': ('توكن زائر مسروق', XTheme.danger),
    'banned_ip_hit': ('وصول من IP محظور', XTheme.danger),
    'banned_device_hit': ('وصول من جهاز محظور', XTheme.danger),
    'device_banned': ('حظر جهاز', XTheme.danger),
    'ip_banned': ('حظر IP', XTheme.danger),
  };

  Future<void> _copy(String value, String what) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تم نسخ $what')));
    }
  }

  Future<void> _ban(String? deviceId, String? addr, String reason) async {
    try {
      if (deviceId != null && deviceId.isNotEmpty) {
        await widget.api.banDevice(deviceId, 'ban_from_security:$reason');
      }
      if (addr != null && addr.isNotEmpty) {
        await widget.api.banIp(addr, 'ban_from_security:$reason');
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم الحظر')));
      }
    } on ApiException catch (ex) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ex.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Row(children: [
            Expanded(
              child: Text('الهجمات ومحاولات التجاوز فقط',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: XTheme.textDim)),
            ),
            Switch(
              value: _attacksOnly,
              activeColor: XTheme.accent,
              onChanged: (v) {
                setState(() => _attacksOnly = v);
                _load();
              },
            ),
            Text('هجمات فقط',
                style: TextStyle(fontSize: 12, color: XTheme.textDim)),
          ]),
        ),
        Expanded(child: _list()),
      ],
    );
  }

  Widget _list() {
    if (_events == null) {
      return Center(child: CircularProgressIndicator(color: XTheme.accent));
    }
    if (_events!.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.verified_user, size: 48, color: XTheme.ok),
          const SizedBox(height: 10),
          Text(_attacksOnly ? 'لا توجد هجمات مسجّلة' : 'لا توجد أحداث',
              style: TextStyle(color: XTheme.textDim)),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: XTheme.accent,
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        itemCount: _events!.length,
        itemBuilder: (context, i) => _eventCard(_events![i]),
      ),
    );
  }

  Widget _eventCard(dynamic e) {
    final reason = e['reason']?.toString() ?? '?';
    final meta = _labels[reason] ?? (reason, XTheme.gold);
    final deviceId = (e['device_id'] ?? '').toString();
    final addr = (e['ip'] ?? '').toString();
    final at = e['at']?.toString() ?? '';
    final detail = (e['detail'] ?? '').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.gpp_maybe_rounded, color: meta.$2, size: 20),
            const SizedBox(width: 9),
            Expanded(
              child: Text(meta.$1,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: meta.$2,
                      fontSize: 13.5)),
            ),
            Text(at.length >= 19 ? at.substring(0, 19).replaceAll('T', ' ') : at,
                style: TextStyle(color: XTheme.textDim, fontSize: 10.5)),
          ]),
          const SizedBox(height: 10),
          if (addr.isNotEmpty && addr != 'unknown')
            _field('IP', addr, XTheme.cyan, () => _ban(null, addr, reason)),
          if (deviceId.isNotEmpty)
            _field('معرّف الجهاز', deviceId, XTheme.accent,
                () => _ban(deviceId, null, reason)),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(detail,
                  style: TextStyle(
                      color: XTheme.textDim, fontSize: 11, height: 1.5)),
            ),
          const SizedBox(height: 10),
          Row(children: [
            if (deviceId.isNotEmpty || (addr.isNotEmpty && addr != 'unknown'))
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _ban(
                      deviceId.isEmpty ? null : deviceId,
                      (addr.isEmpty || addr == 'unknown') ? null : addr,
                      reason),
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('حظر الجهاز و IP'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: XTheme.danger,
                    side: BorderSide(color: XTheme.danger.withOpacity(.5)),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }

  /// سطر حقل حسّاس مع زر نسخ — المالك يحتاج نقل الـID/IP لمنعهما.
  Widget _field(String label, String value, Color color, VoidCallback onBan) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(
            width: 82,
            child: Text(label,
                style: TextStyle(color: XTheme.textDim, fontSize: 11.5)),
          ),
          Expanded(
            child: SelectableText(value,
                maxLines: 1,
                style: TextStyle(
                    fontSize: 11.5,
                    color: color,
                    fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'نسخ $label',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.copy_rounded, size: 16, color: XTheme.textDim),
            onPressed: () => _copy(value, label),
          ),
          IconButton(
            tooltip: 'حظر $label',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.gpp_bad_rounded, size: 18, color: XTheme.danger),
            onPressed: onBan,
          ),
        ]),
      );
}

// ============ الإعلانات ============

class _AnnouncementsTab extends StatefulWidget {
  const _AnnouncementsTab({required this.api});
  final Api api;
  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  List<dynamic>? _ads;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await widget.api.ownerAnnouncements();
      if (mounted) setState(() => _ads = a);
    } catch (_) {
      if (mounted) setState(() => _ads = []);
    }
  }

  void _compose() {
    final title = TextEditingController();
    final subtitle = TextEditingController();
    final link = TextEditingController();
    String? b64;
    String? ext;
    String? previewName;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          margin: const EdgeInsets.all(14),
          padding: EdgeInsets.only(
              left: 22, right: 22, top: 22,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 22),
          decoration: BoxDecoration(
              color: XTheme.surface,
              borderRadius: BorderRadius.circular(26)),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('نشر إعلان جديد',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 14),
              TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'العنوان *')),
              const SizedBox(height: 10),
              TextField(
                  controller: subtitle,
                  decoration:
                      const InputDecoration(labelText: 'النص الفرعي')),
              const SizedBox(height: 10),
              TextField(
                  controller: link,
                  decoration: const InputDecoration(
                      labelText: 'رابط عند الضغط (اختياري)'),
                  textDirection: TextDirection.ltr),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await ImagePicker().pickImage(
                      source: ImageSource.gallery, maxWidth: 1600);
                  if (picked != null) {
                    final bytes = await picked.readAsBytes();
                    if (bytes.length > 4 * 1024 * 1024) return;
                    setSheet(() {
                      b64 = base64Encode(bytes);
                      ext = picked.name.split('.').last.toLowerCase();
                      previewName = picked.name;
                    });
                  }
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(previewName ?? 'اختيار صورة الإعلان'),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: XTheme.gradient,
                      borderRadius: BorderRadius.circular(16)),
                  child: ElevatedButton(
                    onPressed: _posting
                        ? null
                        : () async {
                            if (title.text.trim().isEmpty) return;
                            setSheet(() => _posting = true);
                            try {
                              await widget.api.createAnnouncement(
                                  title.text.trim(),
                                  subtitle.text.trim(),
                                  link.text.trim(),
                                  imageB64: b64,
                                  imageExt: ext);
                              if (ctx.mounted) Navigator.pop(ctx);
                              _load();
                            } catch (_) {}
                            setSheet(() => _posting = false);
                          },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(
                        _posting ? 'جاري النشر…' : 'نشر الإعلان',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        backgroundColor: XTheme.accent2,
        icon: const Icon(Icons.add_photo_alternate_outlined,
            color: Colors.white),
        label: const Text('إعلان جديد',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.w800)),
      ),
      body: _ads == null
          ? Center(
              child: CircularProgressIndicator(color: XTheme.accent))
          : _ads!.isEmpty
              ? Center(
                  child: Text('لا إعلانات — انشر أول إعلان',
                      style: TextStyle(color: XTheme.textDim)))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: XTheme.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: _ads!.length,
                    itemBuilder: (context, i) {
                      final a = _ads![i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(children: [
                            Icon(Icons.campaign,
                                color: XTheme.gold, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(a['title'] ?? '',
                                        style: const TextStyle(
                                            fontWeight:
                                                FontWeight.w800)),
                                    if ((a['subtitle'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text(a['subtitle'],
                                          style: TextStyle(
                                              color: XTheme.textDim,
                                              fontSize: 12)),
                                    if ((a['imageUrl'] ?? '')
                                        .toString()
                                        .isNotEmpty)
                                      Text('مع صورة',
                                          style: TextStyle(
                                              color: XTheme.cyan,
                                              fontSize: 11)),
                                  ]),
                            ),
                            IconButton(
                              onPressed: () async {
                                await widget.api
                                    .deleteAnnouncement(a['id']);
                                _load();
                              },
                              icon: Icon(Icons.delete_outline,
                                  color: XTheme.danger),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// ============ حظر الأجهزة ============

class _BansTab extends StatefulWidget {
  const _BansTab({required this.api});
  final Api api;
  @override
  State<_BansTab> createState() => _BansTabState();
}

class _BansTabState extends State<_BansTab> {
  List<dynamic>? _bans;
  final _dev = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.api.ownerBans();
      if (mounted) setState(() => _bans = b);
    } catch (_) {
      if (mounted) setState(() => _bans = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _dev,
                decoration: const InputDecoration(
                    hintText: 'معرّف الجهاز للحظر النهائي',
                    isDense: true),
                textDirection: TextDirection.ltr,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () async {
                if (_dev.text.trim().isEmpty) return;
                await widget.api
                    .banDevice(_dev.text.trim(), 'manual-owner');
                _dev.clear();
                _load();
              },
              icon: const Icon(Icons.block, size: 18),
              style: IconButton.styleFrom(
                  backgroundColor: XTheme.danger.withOpacity(.2),
                  foregroundColor: XTheme.danger),
            ),
          ]),
        ),
      ),
      Expanded(
        child: _bans == null
            ? Center(
                child: CircularProgressIndicator(color: XTheme.accent))
            : _bans!.isEmpty
                ? Center(
                    child: Text('لا أجهزة محظورة',
                        style: TextStyle(color: XTheme.textDim)))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: XTheme.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                      itemCount: _bans!.length,
                      itemBuilder: (context, i) {
                        final b = _bans![i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(children: [
                              Icon(Icons.phonelink_erase,
                                  color: XTheme.danger, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(b['id'] ?? '',
                                          style: const TextStyle(
                                              fontWeight:
                                                  FontWeight.w700,
                                              fontSize: 13)),
                                      Text(
                                          '${b['reason'] ?? ''} • ${b['at']?.toString().substring(0, 10) ?? ''}',
                                          style: TextStyle(
                                              color: XTheme.textDim,
                                              fontSize: 11)),
                                    ]),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await widget.api
                                      .unbanDevice(b['id']);
                                  _load();
                                },
                                child: Text('فك الحظر',
                                    style: TextStyle(
                                        color: XTheme.ok,
                                        fontSize: 12)),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}

// ============ محافظ الزوار ============

/// محافظ الزوار: عملات تُشحن لجهاز بلا حساب.
///
/// الزائر لم يكن له رصيد إطلاقاً، فكانت حصته المجانية إن نفدت يتوقف تماماً
/// حتى لو دفع. هذه الشاشة تمنحه رصيداً بمفتاح الجهاز — نفس المفتاح الذي
/// يعتمد عليه الخادم في الخصم.
class _WalletsTab extends StatefulWidget {
  const _WalletsTab({required this.api});
  final Api api;
  @override
  State<_WalletsTab> createState() => _WalletsTabState();
}

class _WalletsTabState extends State<_WalletsTab> {
  List<dynamic>? _rows;
  final _dev = TextEditingController();
  final _coins = TextEditingController(text: '5');
  final _days = TextEditingController(text: '30');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dev.dispose();
    _coins.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final w = await widget.api.ownerWallets();
      if (mounted) setState(() => _rows = w);
    } catch (_) {
      if (mounted) setState(() => _rows = []);
    }
  }

  Future<void> _grant() async {
    final dev = _dev.text.trim();
    final coins = int.tryParse(_coins.text.trim()) ?? 0;
    if (dev.isEmpty || coins <= 0) return;
    final days = int.tryParse(_days.text.trim()) ?? 0;
    try {
      await widget.api.grantWallet(dev, coins, days);
      _dev.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل الشحن: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(14),
        child: GlassCard(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(
              'شحن عملات لزائر بمعرّف جهازه. الزائر بلا حساب، فيُعرَّف بجهازه — '
              'انسخ المعرّف من تبويب «الحظر» أو من طلبات الشراء.',
              style: TextStyle(color: XTheme.textDim, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dev,
              decoration: const InputDecoration(
                  hintText: 'معرّف الجهاز', isDense: true),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _coins,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'عدد العملات', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _days,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      hintText: 'أيام الصلاحية (0=بلا حد)', isDense: true),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _grant,
                icon: const Icon(Icons.add_card, size: 18),
                label: const Text('شحن الرصيد'),
              ),
            ),
          ]),
        ),
      ),
      Expanded(
        child: _rows == null
            ? Center(child: CircularProgressIndicator(color: XTheme.accent))
            : _rows!.isEmpty
                ? Center(
                    child: Text('لا محافظ بعد',
                        style: TextStyle(color: XTheme.textDim)))
                : RefreshIndicator(
                    onRefresh: _load,
                    color: XTheme.accent,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                      itemCount: _rows!.length,
                      itemBuilder: (context, i) {
                        final w = _rows![i];
                        final bal = (w['balance'] as num?)?.toInt() ?? 0;
                        final exp = (w['expires_at'] as num?)?.toInt() ?? 0;
                        final expired =
                            exp > 0 && exp <= DateTime.now().millisecondsSinceEpoch;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            child: Row(children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  color: bal > 0 ? XTheme.gold : XTheme.textDim,
                                  size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${w['device_id']}',
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700),
                                      textDirection: TextDirection.ltr,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      expired
                                          ? 'منتهية الصلاحية'
                                          : exp > 0
                                              ? 'صالحة حتى ${DateTime.fromMillisecondsSinceEpoch(exp).toLocal().toString().split(' ').first}'
                                              : 'بلا تاريخ انتهاء',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: expired
                                              ? XTheme.danger
                                              : XTheme.textDim),
                                    ),
                                  ],
                                ),
                              ),
                              Text('$bal',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: bal > 0
                                          ? XTheme.gold
                                          : XTheme.danger)),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'نسخ معرّف الجهاز',
                                onPressed: () =>
                                    copyDeviceId(context, '${w['device_id']}'),
                                icon: const Icon(Icons.copy_rounded, size: 18),
                              ),
                              IconButton(
                                tooltip: 'شحن 5 عملات',
                                onPressed: () async {
                                  await widget.api.grantWallet(
                                      '${w['device_id']}', 5, 0);
                                  _load();
                                },
                                icon: const Icon(Icons.add, size: 18),
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}

// ============ الدردشة ============

/// إشراف المالك على الدردشة: الرسائل، الأقسام، الكتم والطرد.
///
/// كل الإجراءات تُسجَّل في سجل الأمان، والمالك لا يمكن تقييده. الأقسام
/// تُحفظ ضمن إعدادات التطبيق نفسها، فتبقى بعد إعادة النشر.
class _ChatTab extends StatefulWidget {
  const _ChatTab({required this.api});
  final Api api;

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() => setState(() {}));

  List<dynamic>? _messages;
  List<ChatAction>? _actions;
  XSettings? _settings;
  bool _saving = false;
  String? _msg;
  String _room = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.ownerChatMessages(room: _room),
        widget.api.ownerChatActions(),
        widget.api.ownerSettings(),
      ]);
      if (!mounted) return;
      setState(() {
        _messages = results[0] as List;
        _actions = results[1] as List<ChatAction>;
        _settings = XSettings.fromJson(
            (results[2] as Map)['settings'] as Map<String, dynamic>);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _messages = _messages ?? [];
          _actions = _actions ?? [];
        });
      }
    }
  }

  List<ChatRoom> get _rooms => _settings?.chatRooms ?? const [];

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: XTheme.surface2,
      ));
  }

  /// حفظ إعدادات الدردشة وحدها — لا يمس بقية الإعدادات.
  Future<void> _saveChat({String? msg}) async {
    final s = _settings;
    if (s == null) return;
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final r = await widget.api.saveSettings({
        'chatEnabled': s.chatEnabled,
        'chatReadOnly': s.chatReadOnly,
        'chatTheme': s.chatTheme,
        'chatWelcome': s.chatWelcome,
        'chatMaxLength': s.chatMaxLength,
        'chatImagesEnabled': s.chatImagesEnabled,
        'chatWriteScope': s.chatWriteScope,
        'chatMediaScope': s.chatMediaScope,
        'chatMaxMediaMb': s.chatMaxMediaMb,
        'chatMediaSeconds': s.chatMediaSeconds,
        'chatPollMs': s.chatPollMs,
        'chatRooms': s.chatRooms
            .map((r) => {'id': r.id, 'name': r.name, 'icon': r.icon})
            .toList(),
      });
      if (!mounted) return;
      setState(() {
        _settings =
            XSettings.fromJson(r['settings'] as Map<String, dynamic>);
        _msg = msg ?? 'تم الحفظ';
      });
    } catch (_) {
      if (mounted) setState(() => _msg = 'فشل الحفظ');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_settings == null) {
      return Center(child: CircularProgressIndicator(color: XTheme.accent));
    }
    return Column(children: [
      TabBar(
        controller: _tabs,
        labelColor: XTheme.accent,
        unselectedLabelColor: XTheme.textDim,
        indicatorColor: XTheme.accent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
        tabs: const [
          Tab(text: 'الرسائل'),
          Tab(text: 'الأعضاء المقيّدون'),
          Tab(text: 'الإعدادات'),
        ],
      ),
      if (_msg != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(_msg!,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _msg == 'تم الحفظ' ? XTheme.ok : XTheme.danger)),
        ),
      Expanded(
        child: TabBarView(
          controller: _tabs,
          children: [_messagesView(), _restrictionsView(), _settingsView()],
        ),
      ),
    ]);
  }

  // ── الرسائل: مراجعة وحذف ──

  Widget _messagesView() {
    final list = _messages ?? const [];
    return Column(children: [
      Container(
        height: 40,
        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: ListView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          children: [
            _roomChip('', 'الكل'),
            for (final r in _rooms) _roomChip(r.id, r.name),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text('لا رسائل',
                    style: TextStyle(color: XTheme.textDim)))
            : RefreshIndicator(
                onRefresh: _load,
                color: XTheme.accent,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _messageCard(list[i]),
                ),
              ),
      ),
    ]);
  }

  Widget _roomChip(String id, String name) => Padding(
        padding: const EdgeInsets.only(left: 8),
        child: GestureDetector(
          onTap: () async {
            setState(() => _room = id);
            await _load();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: _room == id ? XTheme.gradient : null,
              color: _room == id ? null : XTheme.surface2,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _room == id ? Colors.white : XTheme.text,
                )),
          ),
        ),
      );

  Widget _messageCard(dynamic m) {
    final kind = '${m['kind'] ?? 'text'}';
    final media = '${m['mediaUrl'] ?? ''}';
    final deleted = m['deleted'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Icon(
            kind == 'image'
                ? Icons.image_outlined
                : (kind == 'audio'
                    ? Icons.mic_none
                    : (kind == 'video'
                        ? Icons.videocam_outlined
                        : Icons.chat_bubble_outline)),
            size: 19,
            color: deleted ? XTheme.textDim : XTheme.cyan,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['nickname']?.toString().isNotEmpty == true
                    ? m['nickname']
                    : (m['username'] ?? 'عضو'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(
                  deleted
                      ? 'محذوفة'
                      : (media.isNotEmpty
                          ? 'وسيط ($kind)'
                          : (m['body'] ?? '').toString()),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: deleted ? XTheme.textDim : XTheme.text),
                ),
                if ('${m['roomId']}'.isNotEmpty)
                  Text('قسم: ${m['roomId']}',
                      style: TextStyle(
                          fontSize: 10, color: XTheme.textDim)),
              ],
            ),
          ),
          // أزرار الإشراف على كاتب الرسالة
          PopupMenuButton<String>(
            tooltip: 'إجراء',
            icon: Icon(Icons.more_vert, size: 18, color: XTheme.textDim),
            onSelected: (v) async {
              final uid = '${m['userId']}';
              if (v == 'delete') {
                await widget.api.ownerDeleteChatMessage('${m['id']}');
                await _load();
                return;
              }
              await _restrictDialog(uid,
                  kind: v == 'mute' ? 'mute' : 'kick');
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'mute', child: Text('كتم العضو')),
              const PopupMenuItem(value: 'kick', child: Text('طرد من الدردشة')),
              if (!deleted)
                const PopupMenuItem(value: 'delete', child: Text('حذف الرسالة')),
            ],
          ),
        ]),
      ),
    );
  }

  /// حوار كتم/طرد: نطاق (كل الأقسام أو قسم)، مدة، وسبب يُعرض للعضو.
  Future<void> _restrictDialog(String userId, {required String kind}) async {
    String room = '';
    String reason = '';
    int minutes = 0;
    final isMute = kind == 'mute';
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: XTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(isMute ? 'كتم عضو' : 'طرد من الدردشة',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isMute
                    ? 'المكتوم لا يستطيع الكتابة، ويمكنه القراءة.'
                    : 'المطرود لا يستطيع الكتابة في القسم المحدد.',
                style: TextStyle(fontSize: 12, color: XTheme.textDim),
              ),
              const SizedBox(height: 12),
              Text('النطاق',
                  style: TextStyle(fontSize: 11.5, color: XTheme.textDim)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: room,
                items: [
                  const DropdownMenuItem(value: '', child: Text('كل الأقسام')),
                  for (final r in _rooms)
                    DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (v) => setD(() => room = v ?? ''),
              ),
              const SizedBox(height: 12),
              Text('المدة',
                  style: TextStyle(fontSize: 11.5, color: XTheme.textDim)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final opt in const [
                  (0, 'دائم'),
                  (60, 'ساعة'),
                  (1440, 'يوم'),
                  (10080, 'أسبوع'),
                ])
                  ChoiceChip(
                    label: Text(opt.$2,
                        style: const TextStyle(fontSize: 11.5)),
                    selected: minutes == opt.$1,
                    onSelected: (_) => setD(() => minutes = opt.$1),
                  ),
              ]),
              const SizedBox(height: 12),
              TextField(
                maxLength: 120,
                decoration: const InputDecoration(
                  hintText: 'سبب (يظهر للعضو)',
                  isDense: true,
                  counterText: '',
                ),
                onChanged: (v) => reason = v,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(color: XTheme.textDim)),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await widget.api.ownerChatAction(
                    userId: userId,
                    kind: kind,
                    room: room,
                    reason: reason.trim(),
                    minutes: minutes,
                  );
                  await _load();
                  _toast(isMute ? 'تم الكتم' : 'تم الطرد');
                } catch (e) {
                  _toast('فشل الإجراء: $e');
                }
              },
              style: FilledButton.styleFrom(
                  backgroundColor:
                      isMute ? XTheme.accent : XTheme.danger),
              child: Text(isMute ? 'كتم' : 'طرد'),
            ),
          ],
        ),
      ),
    );
  }

  // ── الأعضاء المقيّدون ──

  Widget _restrictionsView() {
    final list = _actions ?? const <ChatAction>[];
    if (list.isEmpty) {
      return Center(
          child: Text('لا عقوبات مسجّلة',
              style: TextStyle(color: XTheme.textDim)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: XTheme.accent,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final a = list[i];
          final color = a.active
              ? (a.isMute ? XTheme.accent : XTheme.danger)
              : XTheme.textDim;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Icon(a.isMute ? Icons.volume_off : Icons.block,
                    size: 19, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a.username.isEmpty ? a.userId : a.username} • '
                        '${a.isMute ? 'كتم' : 'طرد'}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${a.roomId.isEmpty ? 'كل الأقسام' : a.roomId} • '
                        '${a.isPermanent ? 'دائم' : 'حتى ${_untilText(a.until)}'}',
                        style: TextStyle(
                            fontSize: 11, color: XTheme.textDim),
                      ),
                      if (a.reason.isNotEmpty)
                        Text(a.reason,
                            style: TextStyle(
                                fontSize: 11, color: XTheme.textDim)),
                    ],
                  ),
                ),
                StatusPill(a.active ? 'سارٍ' : 'منتهي', color: color),
                IconButton(
                  tooltip: 'رفع العقوبة',
                  onPressed: () async {
                    await widget.api.ownerClearChatAction(a.userId,
                        kind: a.kind);
                    await _load();
                  },
                  icon: Icon(Icons.undo, size: 18, color: XTheme.ok),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  static String _untilText(int until) {
    final d = DateTime.fromMillisecondsSinceEpoch(until);
    final left = d.difference(DateTime.now());
    if (left.isNegative) return 'منتهية';
    if (left.inDays >= 1) return '${left.inDays} يوم';
    if (left.inHours >= 1) return '${left.inHours} ساعة';
    return '${left.inMinutes} دقيقة';
  }

  // ── إعدادات الدردشة ──

  Widget _settingsView() {
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('حالة الدردشة', icon: Icons.tune),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تشغيل الدردشة',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('إيقافها يخفيها عن كل الأعضاء فوراً',
                    style: TextStyle(color: XTheme.textDim, fontSize: 11)),
                value: s.chatEnabled,
                activeColor: XTheme.cyan,
                onChanged: (v) => setState(() => s.chatEnabled = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('القراءة فقط',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('يمنع الكتابة عن الجميع عدا المالك',
                    style: TextStyle(color: XTheme.textDim, fontSize: 11)),
                value: s.chatReadOnly,
                activeColor: XTheme.cyan,
                onChanged: (v) => setState(() => s.chatReadOnly = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('السماح برفع الصور',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('الصور متاحة لكل من يستطيع الكتابة',
                    style: TextStyle(color: XTheme.textDim, fontSize: 11)),
                value: s.chatImagesEnabled,
                activeColor: XTheme.cyan,
                onChanged: (v) => setState(() => s.chatImagesEnabled = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('من يشارك', icon: Icons.group_outlined),
              Text('من يستطيع الكتابة',
                  style: TextStyle(fontSize: 11.5, color: XTheme.textDim)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: s.chatWriteScope,
                decoration: const InputDecoration(isDense: true),
                items: const [
                  DropdownMenuItem(
                      value: 'all', child: Text('الجميع (زوار ومسجّلون)')),
                  DropdownMenuItem(
                      value: 'registered', child: Text('المسجّلون فقط')),
                  DropdownMenuItem(
                      value: 'subscribers', child: Text('المشتركون فقط')),
                ],
                onChanged: (v) =>
                    setState(() => s.chatWriteScope = v ?? 'registered'),
              ),
              const SizedBox(height: 12),
              Text('من يرسل الصوت والفيديو',
                  style: TextStyle(fontSize: 11.5, color: XTheme.textDim)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: s.chatMediaScope,
                decoration: const InputDecoration(isDense: true),
                items: const [
                  DropdownMenuItem(
                      value: 'subscribers', child: Text('المشتركون فقط')),
                  DropdownMenuItem(value: 'none', child: Text('موقوف')),
                ],
                onChanged: (v) =>
                    setState(() => s.chatMediaScope = v ?? 'subscribers'),
              ),
              const SizedBox(height: 14),
              _numField('أقصى طول للرسالة (حرف)', s.chatMaxLength, (v) {
                setState(() => s.chatMaxLength = v);
              }),
              _numField('أقصى حجم للوسيط (MB)', s.chatMaxMediaMb, (v) {
                setState(() => s.chatMaxMediaMb = v);
              }),
              _numField('أقصى مدة مقطع (ثانية)', s.chatMediaSeconds, (v) {
                setState(() => s.chatMediaSeconds = v);
              }),
              _numField('زمن التحديث (مللي ثانية)', s.chatPollMs, (v) {
                setState(() => s.chatPollMs = v);
              }),
              const SizedBox(height: 6),
              Text(
                'زمن التحديث يحدد كل كم يطلب التطبيق الرسائل الجديدة. القيمة '
                'الأكبر توفّر بطارية وشبكة، والأصغر تجعل الوصول أسرع.',
                style: TextStyle(fontSize: 11, color: XTheme.textDim),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle('المظهر والترحيب', icon: Icons.palette_outlined),
              DropdownButtonFormField<String>(
                initialValue: s.chatTheme,
                decoration: const InputDecoration(
                    labelText: 'سمة الفقاعات', isDense: true),
                items: const [
                  DropdownMenuItem(value: 'bubble', child: Text('فقاعات')),
                  DropdownMenuItem(value: 'classic', child: Text('كلاسيكي')),
                  DropdownMenuItem(value: 'neon', child: Text('نيون')),
                  DropdownMenuItem(value: 'dark', child: Text('داكن')),
                ],
                onChanged: (v) => setState(() => s.chatTheme = v ?? 'bubble'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: s.chatWelcome)
                  ..selection = TextSelection.collapsed(
                      offset: s.chatWelcome.length),
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'رسالة ترحيب تظهر أعلى الدردشة',
                  isDense: true,
                ),
                onChanged: (v) => s.chatWelcome = v,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle('أقسام الدردشة',
                  icon: Icons.forum_outlined,
                  trailing: IconButton(
                    tooltip: 'إضافة قسم',
                    onPressed: _addRoomDialog,
                    icon: Icon(Icons.add_circle, color: XTheme.cyan),
                  )),
              if (s.chatRooms.isEmpty)
                Text('لا أقسام — أضف قسماً ليظهر للأعضاء',
                    style: TextStyle(fontSize: 12, color: XTheme.textDim)),
              for (var i = 0; i < s.chatRooms.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Icon(Icons.drag_indicator,
                        size: 18, color: XTheme.textDim),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${s.chatRooms[i].name}  ·  '
                          '${s.chatRooms[i].id}',
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'تعديل',
                      onPressed: () => _addRoomDialog(index: i),
                      icon: Icon(Icons.edit_outlined,
                          size: 17, color: XTheme.cyan),
                    ),
                    IconButton(
                      tooltip: 'حذف',
                      onPressed: () => setState(() {
                        s.chatRooms.removeAt(i);
                      }),
                      icon: Icon(Icons.delete_outline,
                          size: 17, color: XTheme.danger),
                    ),
                  ]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : () => _saveChat(),
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('حفظ إعدادات الدردشة',
                style: TextStyle(fontWeight: FontWeight.w900)),
            style: FilledButton.styleFrom(
              backgroundColor: XTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(XTheme.rMd)),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _numField(String label, int value, ValueChanged<int> onChanged) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextFormField(
          initialValue: '$value',
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label, isDense: true),
          onChanged: (v) => onChanged(int.tryParse(v.trim()) ?? value),
        ),
      );

  /// إضافة قسم أو تعديله. المعرّف لاتيني قصير لأنه يُخزَّن في كل رسالة.
  Future<void> _addRoomDialog({int? index}) async {
    final s = _settings!;
    final existing = index == null ? null : s.chatRooms[index];
    final id = TextEditingController(text: existing?.id ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    var icon = existing?.icon ?? 'chat';
    final icons = const {
      'chat': 'محادثة',
      'build': 'صيانة',
      'memory': 'قطع',
      'store': 'بيع وشراء',
      'help': 'مساعدة',
      'sell': 'عروض',
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: XTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(index == null ? 'قسم جديد' : 'تعديل القسم',
              style: const TextStyle(fontWeight: FontWeight.w900)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(
                    labelText: 'اسم القسم', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: id,
                enabled: index == null,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'المعرّف (a-z، بلا مسافات)',
                  isDense: true,
                  helperText: 'يُستخدم داخلياً ويظهر في الروابط',
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: icon,
                decoration: const InputDecoration(
                    labelText: 'الأيقونة', isDense: true),
                items: [
                  for (final e in icons.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setD(() => icon = v ?? 'chat'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: TextStyle(color: XTheme.textDim)),
            ),
            FilledButton(
              onPressed: () {
                final rid = id.text.trim().toLowerCase();
                final rname = name.text.trim();
                if (rname.isEmpty ||
                    !RegExp(r'^[a-z0-9_]{2,20}$').hasMatch(rid)) {
                  setD(() {});
                  return;
                }
                setState(() {
                  final room = ChatRoom(id: rid, name: rname, icon: icon);
                  if (index == null) {
                    // منع التكرار: معرّف مكرر يجعل رسائل قسمين تختلط.
                    if (!s.chatRooms.any((r) => r.id == rid)) {
                      s.chatRooms.add(room);
                    }
                  } else {
                    s.chatRooms[index] = room;
                  }
                });
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: XTheme.accent),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ أمان اللوحة ============

/// قسم أمان لوحة المالك — قفل البصمة وإنهاء جلسة اللوحة.
///
/// الجلسة هنا منفصلة تماماً عن جلسة المستخدم العادي، ولها سرّها المستقل في
/// الخادم. «إنهاء الجلسة» يمحو الرمز المحلي وختم الفتح معاً، فلا يبقى أثر
/// يصلح لفتح اللوحة إن فُقد الهاتف.
class _OwnerPanelSecurity extends StatefulWidget {
  const _OwnerPanelSecurity();

  @override
  State<_OwnerPanelSecurity> createState() => _OwnerPanelSecurityState();
}

class _OwnerPanelSecurityState extends State<_OwnerPanelSecurity> {
  bool? _available;
  bool _enabled = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final available = await BiometricLock.available;
    final enabled = await BiometricLock.enabled;
    if (!mounted) return;
    setState(() {
      _available = available;
      _enabled = enabled;
    });
  }

  Future<void> _toggle(bool v) async {
    if (v) {
      // لا نفعّل القفل بلا تحقق ناجح أولاً — وإلا أقفل المالك نفسه خارج
      // اللوحة إن لم تكن بصمته مسجّلة فعلاً.
      final ok = await BiometricLock.authenticate(
          reason: 'تأكيد تفعيل قفل البصمة على لوحة المالك');
      if (!ok) {
        setState(() => _msg = 'لم ينجح التحقق — لم يُفعَّل القفل');
        return;
      }
    }
    await BiometricLock.setEnabled(v);
    if (!mounted) return;
    setState(() {
      _enabled = v;
      _msg = v ? 'قفل البصمة مفعّل' : 'قفل البصمة موقوف';
    });
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إنهاء جلسة اللوحة؟',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: const Text(
            'ستحتاج اسم المستخدم وكلمة المرور للدخول مرة أخرى. '
            'لا يتأثر حسابك العادي ولا اشتراكك.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إنهاء')),
        ],
      ),
    );
    if (ok != true) return;
    await Store.clearOwnerSession();
    if (!mounted) return;
    // نعود لبوابة الدخول: اللوحة الحالية صارت بلا جلسة صالحة.
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final available = _available ?? false;
    return GlassCard(
      accent: XTheme.cyan,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('أمان اللوحة', icon: Icons.shield_moon_outlined),
          Text(
            'جلسة اللوحة منفصلة عن حسابك العادي، وكل ردودها مشفّرة بمفتاح '
            'مشتق من الجلسة نفسها.',
            style:
                TextStyle(color: XTheme.textDim, fontSize: 11.5, height: 1.6),
          ),
          const SizedBox(height: 4),
          if (available)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('قفل بالبصمة',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: Text('يُطلب عند كل فتح للوحة',
                  style: TextStyle(color: XTheme.textDim, fontSize: 11)),
              value: _enabled,
              onChanged: _toggle,
              activeColor: XTheme.cyan,
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'لا توجد بصمة مسجّلة على هذا الجهاز — سجّلها في إعدادات '
                'الهاتف ثم أعد المحاولة.',
                style: TextStyle(color: XTheme.textDim, fontSize: 11.5),
              ),
            ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(_msg!,
                  style: const TextStyle(color: XTheme.ok, fontSize: 12)),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('إنهاء جلسة اللوحة',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              style: OutlinedButton.styleFrom(
                foregroundColor: XTheme.danger,
                side: BorderSide(color: XTheme.danger.withOpacity(.45)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(XTheme.rMd)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

