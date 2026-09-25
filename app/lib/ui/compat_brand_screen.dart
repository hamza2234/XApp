import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/compat_catalog.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'subscribe_dialog.dart';
import 'theme.dart';

/// بيانات كل نوع قطعة: الاسم والأيقونة واللون وترتيب العرض.
class CompatTypeMeta {
  const CompatTypeMeta(this.label, this.icon, this.color, this.rank);

  final String label;
  final IconData icon;
  final Color color;
  final int rank;

  static const _map = <String, CompatTypeMeta>{
    'SCREEN': CompatTypeMeta('شاشات', Icons.smartphone, Color(0xFF4D8DFF), 0),
    'BATTERY': CompatTypeMeta('بطاريات', Icons.battery_full, Color(0xFF2EE6A8), 1),
    'GLASS': CompatTypeMeta('زجاج', Icons.shield_outlined, Color(0xFF8B5CF6), 2),
    'INCASSABLE':
        CompatTypeMeta('ضد الكسر', Icons.verified_outlined, Color(0xFFF5B942), 3),
  };

  /// الأنواع الأربعة بترتيب العرض — ثابتة كي لا تحتاج طلباً عند فتح الشاشة.
  static List<String> get orderedTypes {
    final keys = _map.keys.toList();
    keys.sort((a, b) => _map[a]!.rank.compareTo(_map[b]!.rank));
    return keys;
  }

  static CompatTypeMeta of(String type) => _map[type] ??
      CompatTypeMeta(type, Icons.build_outlined, XTheme.cyan, 100);

  static int rankOf(String type) => of(type).rank;
}

/// شاشة توافقات شركة واحدة: اختيار النوع ثم البحث النصّي.
///
/// البحث يجري على الخادم (مكلّف ببطاقات) — لا نسحب سجلات الشركة كاملة إلى
/// الجهاز، وإلا صار نظام العملات بلا معنى. لا نتائج قبل اختيار النوع وكتابة
/// الاستعلام.
class CompatBrandScreen extends StatefulWidget {
  const CompatBrandScreen(
      {super.key, required this.api, required this.brand, this.store,
       this.onCharged});

  final Api api;
  final CompatBrand brand;
  final Store? store;

  /// يُنادى عند كل خصم فعلي (فتح أو بحث) ليعيد الشريط العلوي للرصيد الجديد.
  final VoidCallback? onCharged;

  @override
  State<CompatBrandScreen> createState() => _CompatBrandScreenState();
}

class _CompatBrandScreenState extends State<CompatBrandScreen> {
  /// مهلة قبل إرسال الطلب بعد آخر ضغطة مفتاح.
  ///
  /// لا تخصم شيئاً الآن: الخصم وقع عند فتح الشركة. بقاؤها لأن كل ضغطة مفتاح
  /// طلب شبكة، وتجميع الكتابة المتصلة في طلب واحد أرحم على الإنترنت الضعيف.
  static const _debounce = Duration(milliseconds: 600);

  /// أقل طول استعلام: حرف واحد يطابق كل شيء تقريباً بلا فائدة.
  static const _minQuery = 2;

  final _q = TextEditingController();
  Timer? _timer;

  /// رقم الطلب الأخير — يمنع رداً قديماً من الكتابة فوق نتيجة أحدث.
  int _seq = 0;

  String? _type;
  String _query = '';
  bool _loading = false;
  bool _charged = false;
  String? _error;
  bool _locked = false;
  bool _quotaEmpty = false;
  List<CompatRecord> _records = const [];
  final Set<String> _savingRows = {};
  int _remaining = -1;
  int _balance = -1;
  String _source = '';
  bool _searched = false;

  /// أنواع القطع المتوفرة لهذه الشركة كما يعيدها الخادم مع نتائج البحث،
  /// إضافةً إلى ما أضافه المالك. تُستعمل كخيارات في نموذج التحرير.
  List<String> _types = const [];

  /// المالك يبحث كأي مستخدم، لكن واجهات الإضافة والتعديل تظهر له وحده
  /// داخل النتائج نفسها — بلا تبويب منفصل في اللوحة.
  bool get _isOwner => widget.api.store.hasOwnerSession;

  @override
  void initState() {
    super.initState();
    // الدخول يخصم هنا — قبل أن يكتب المستخدم أي حرف، فيرى رصيده أولاً.
    _open();
  }

  Future<void> _open() async {
    try {
      final r = await widget.api.openCompat(widget.brand.ref);
      if (!mounted) return;
      setState(() {
        _charged = r.charged;
        _remaining = r.remaining;
        _balance = r.balance;
        _source = r.source;
      });
      // الخصم وقع فعلاً: نُبلّغ الشريط فوراً بدل انتظار إعادة التشغيل.
      if (r.charged) widget.onCharged?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        // 402/429 = نفد الرصيد، ويُعرض كحالة حصة لا كخطأ شبكة.
        _quotaEmpty = e.quotaExhausted;
        _locked = e.forbidden;
        _error = e.quotaExhausted ? null : e.message;
      });
      if (e.quotaExhausted) await showSubscribeDialog(context);
    } catch (_) {
      // تعذّر الدخول: نترك البحث يعمل ويخصم الخادم بنفسه عند أول نص، فلا
      // يُمنع المستخدم من شاشة قد تعمل.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _selectType(String type) {
    _seq++;
    setState(() {
      _loading = false;
      _type = _type == type ? null : type;
      _query = '';
      _records = const [];
      _error = null;
      _quotaEmpty = false;
      _searched = false;
    });
    _q.clear();
    _timer?.cancel();
  }

  void _onQuery(String v) {
    _seq++;
    setState(() {
      _query = v;
      _loading = false;
    });
    _timer?.cancel();
    final q = v.trim();
    if (q.length < _minQuery) {
      setState(() {
        _records = const [];
        _error = null;
        _searched = false;
      });
      return;
    }
    _timer = Timer(_debounce, () => _search(q));
  }

  Future<void> _search(String q) async {
    final type = _type;
    if (type == null) return;
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
      _quotaEmpty = false;
    });
    try {
      final r = await widget.api
          .searchCompatCharged(q, brand: widget.brand.ref, type: type);
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _charged = r.charged;
        _remaining = r.remaining;
        _balance = r.balance;
        _source = r.source;
        _records = r.records.map((e) => CompatRecord.fromJson(e)).toList();
        if (r.types.isNotEmpty) _types = r.types;
      });
      if (r.charged) widget.onCharged?.call();
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _records = const [];
        // خادم قديم بلا نقطة البحث المحصّنة: نقولها صراحةً بدل خطأ غامض،
        // فالمشكلة في النشر لا في إنترنت المستخدم.
        _error = e.serverOutdated
            ? 'الخادم يحتاج تحديثاً من المالك — التوافقات غير متاحة الآن'
            : e.message;
        _locked = e.forbidden;
        _quotaEmpty = e.quotaExhausted;
      });
      if (e.quotaExhausted && mounted) {
        await showSubscribeDialog(context);
      }
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _records = const [];
        _error = 'تعذر الاتصال بالخادم — تحقق من الإنترنت';
      });
    }
  }

  /// ── تحرير المالك: يعيش داخل شاشة البحث نفسها ──
  ///
  /// المالك يبحث كأي مستخدم عادي (نفس الخصم ونفس النتائج)، وتظهر له فوق
  /// النتائج أزرار الإضافة، وعلى كل صفّ أزرار التعديل والحذف. لا تبويب
  /// منفصل ولا شاشة مستقلة: التعديل يقع حيث يرى الصفّ فعلاً.

  /// يبني قائمة الأنواع للاختيار، ويضمن ألا يختفي النوع الحالي منها.
  List<String> _typeChoices(String current) {
    final base = _types.isNotEmpty ? _types : CompatTypeMeta.orderedTypes;
    return base.contains(current) || current.isEmpty
        ? base
        : [...base, current];
  }

  Future<void> _ownerAddRow() => _ownerAdd();

  /// نموذج الإضافة الوحيد.
  Future<void> _ownerAdd() async {
    final models = TextEditingController();
    final sub = TextEditingController();
    var chosen = _type ?? CompatTypeMeta.orderedTypes.first;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: XTheme.surface,
          title: const Text('إضافة صفّ توافق',
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'اكتب موديلاً في كل سطر — والنزول للأسفل يعني موديلات أكثر. '
                'الفاصلة ليست فاصلاً: احتفظ بها إن كانت جزءاً من الاسم.',
                style: TextStyle(fontSize: 11.5, color: Colors.white60),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: models,
                maxLines: 6,
                minLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'الموديلات المتوافقة',
                  helperText: 'سطر لكل موديل',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sub,
                decoration: const InputDecoration(
                    labelText: 'الوصف / النوع الفرعي (اختياري)'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: chosen,
                decoration: const InputDecoration(labelText: 'نوع القطعة'),
                items: _typeChoices(chosen)
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setLocal(() => chosen = v ?? chosen),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final list = splitModelLines(models.text)
                    .map((e) => e.toLowerCase())
                    .toList();
                // الحفظ بصمت عند قائمة فارغة كان يُوهم المالك أن الزرّ لا
                // يعمل. نقول له السبب صراحةً.
                if (list.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('اكتب موديلاً واحداً على الأقل')));
                  return;
                }
                try {
                  await widget.api
                      .ownerCompatAdd(brand: widget.brand.ref, rows: [
                    {
                      'compatibleModels': list,
                      'componentType': chosen,
                      'subCategory': {'name': sub.text.trim()},
                    }
                  ]);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) await _ownerRefresh(done: 'تم');
  }

  /// بعد أي تحرير: نعيد تنفيذ البحث نفسه بنفس النص، فيرى المالك النتيجة
  /// النهائية كما يراها المستخدم — لا انعكاس محلي قد يخفي فشل الحفظ.
  ///
  /// وإن كان نصّ البحث أقصر من الحدّ فلا نتائج تُحدَّث أصلاً؛ الرسالة وحدها
  /// تُطمئن المالك أن الحفظ وقع فعلاً بدل صمت يُوهمه بالفشل.
  Future<void> _ownerRefresh({String? done}) async {
    final q = _query.trim();
    if (q.length < _minQuery) {
      if (done != null) _ownerToast(done);
      return;
    }
    await _search(q);
    if (done != null) _ownerToast(done);
  }

  Future<bool> _saveRow(CompatRecord row, Map<String, dynamic>? fields) async {
    if (!_savingRows.add(row.id)) return false;
    _seq++;
    setState(() => _loading = false);
    try {
      final result = fields == null
          ? await widget.api.ownerCompatDelete(brand: widget.brand.ref, id: row.id)
          : await widget.api.ownerCompatPatch(
              brand: widget.brand.ref, id: row.id, fields: fields);
      if (result['ok'] != true) throw ApiException(500, 'لم يؤكد الخادم الحفظ');
      CompatRecord? saved;
      if (fields != null) {
        final data = result['record'];
        if (data is! Map || data['id'] != row.id) {
          throw ApiException(409, 'الخادم يحتاج تحديثاً لتأكيد التعديل داخل الصف');
        }
        saved = CompatRecord.fromJson(Map<String, dynamic>.from(data));
      }
      if (!mounted) return true;
      _seq++;
      setState(() {
        _loading = false;
        _records = [
          for (final item in _records)
            if (item.id != row.id) item else if (saved != null) saved,
        ];
      });
      return true;
    } finally {
      _savingRows.remove(row.id);
      if (mounted) setState(() {});
    }
  }

  void _ownerToast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: XTheme.ok,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _ownerEditRow(CompatRecord r) async {
    // الفصل بسطر لا بفاصلة، أسوةً بنموذج الإضافة: الفاصلة قد تكون جزءاً من
    // اسم الموديل نفسه.
    final models = TextEditingController(text: r.models.join('\n'));
    final sub = TextEditingController(text: r.subCategory ?? '');
    final initial = r.componentType.toUpperCase();
    var chosen = initial;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: XTheme.surface,
          title: const Text('تعديل صفّ توافق',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: models,
                maxLines: 6,
                minLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'الموديلات المتوافقة',
                  helperText: 'سطر لكل موديل',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: chosen,
                decoration: const InputDecoration(labelText: 'نوع القطعة'),
                items: _typeChoices(chosen)
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setLocal(() => chosen = v ?? chosen),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sub,
                decoration: const InputDecoration(
                    labelText: 'الوصف / النوع الفرعي'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final list = splitModelLines(models.text)
                    .map((e) => e.toLowerCase())
                    .toList();
                // الحفظ بصمت عند قائمة فارغة كان يُوهم المالك أن الزرّ لا
                // يعمل. نقول له السبب صراحةً.
                if (list.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('اكتب موديلاً واحداً على الأقل')));
                  return;
                }
                try {
                  final saved = await _saveRow(r, {
                    'compatibleModels': list,
                    'componentType': chosen,
                    'subCategory': {'name': sub.text.trim()},
                  });
                  if (saved && ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(e.message)));
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _ownerToast('تم حفظ التعديل');
  }

  Future<void> _ownerDeleteRow(CompatRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        title: const Text('حذف الصفّ؟'),
        content: const Text('يُخفى من نتائج البحث. البيانات الأصلية لا تُمسّ '
            'ويمكن التراجع عنه.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (await _saveRow(r, null)) _ownerToast('تم حذف الصفّ');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.brand.displayName)),
      body: Column(
        children: [
          _typeSelector(),
          if (_type != null) _searchField(),
          if (_type != null && _remaining >= 0) _quotaChip(),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  /// صف الأنواع: أيقونة واسم فقط — بلا أعداد كي لا تُبنى صورة كاملة عن
  /// حجم البيانات بلا بحث.
  Widget _typeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Row(
        children: [
          for (final t in CompatTypeMeta.orderedTypes)
            Expanded(child: _typeChip(t, _type == t)),
        ],
      ),
    );
  }

  /// شريحة نوع واحدة — بطاقة صغيرة بأيقونة ملوّنة واسم.
  ///
  /// النوع المحدد يأخذ تدرّج لونه مع توهّج، فيبدو «مضغوطاً» فعلاً؛ وهذا
  /// هو الفرق بين قائمة خيارات وشريط تحكّم.
  Widget _typeChip(String type, bool selected) {
    final meta = CompatTypeMeta.of(type);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        onTap: () => _selectType(type),
        borderRadius: BorderRadius.circular(XTheme.rMd),
        splashColor: meta.color.withOpacity(.12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    colors: [
                      meta.color.withOpacity(.26),
                      meta.color.withOpacity(.10),
                    ],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                  )
                : null,
            color: selected ? null : XTheme.surface,
            borderRadius: BorderRadius.circular(XTheme.rMd),
            border: Border.all(
                color: selected
                    ? meta.color.withOpacity(.70)
                    : XTheme.textDim.withOpacity(.16),
                width: selected ? 1.5 : 1),
            boxShadow: selected
                ? XTheme.glow(meta.color, strength: .55)
                : XTheme.shadow(lift: .5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(meta.icon,
                  size: selected ? 22 : 20,
                  color: selected ? meta.color : XTheme.textDim),
              const SizedBox(height: 6),
              Text(meta.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      fontSize: 11.5,
                      color: selected ? meta.color : XTheme.text)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    final meta = CompatTypeMeta.of(_type!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: TextField(
        controller: _q,
        autofocus: true,
        onChanged: _onQuery,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'ابحث في ${meta.label}…',
          prefixIcon: Icon(Icons.search, color: meta.color),
          suffixIcon: _q.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _q.clear();
                    _onQuery('');
                  }),
        ),
      ),
    );
  }

  /// شريط الرصيد: عدّاد واحد = منحة اليوم + العملات، مطابق لما في الشريط
  /// العلوي. كان يعرض عدّادين منفصلين فيظهر رقمان متضاربان لنفس المستخدم.
  Widget _quotaChip() {
    final total = _remaining < 0 ? _balance : _remaining + (_balance < 0 ? 0 : _balance);
    final ok = total > 0;
    final parts = <String>[
      if (_remaining >= 0) 'مجاني $_remaining',
      if (_balance >= 0) 'عملات $_balance',
    ];
    final c = ok ? XTheme.gold : XTheme.danger;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.withOpacity(.09),
          borderRadius: BorderRadius.circular(XTheme.rSm),
          border: Border.all(color: c.withOpacity(.22)),
        ),
        child: Row(children: [
          Icon(Icons.account_balance_wallet_outlined, size: 16, color: c),
          const SizedBox(width: 7),
          Text(ok ? 'المتبقي: $total' : 'لا يوجد رصيد متبقٍ',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w800, color: c)),
          if (parts.isNotEmpty) ...[
            const SizedBox(width: 7),
            Expanded(
              child: Text(parts.join(' + '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: XTheme.textDim)),
            ),
          ] else
            const Spacer(),
          if (_charged)
            Text(_source == 'coins' ? 'خُصمت عملة' : 'خُصم من منحة اليوم',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: XTheme.textDim.withOpacity(.85))),
        ]),
      ),
    );
  }

  Widget _results() {
    if (_type == null) {
      return _emptyView(
          'اختر نوع القطعة أولاً — شاشات أو بطاريات أو زجاج أو ضد الكسر',
          Icons.touch_app);
    }
    final meta = CompatTypeMeta.of(_type!);

    if (_query.trim().length < _minQuery) {
      return _emptyView(
          'اكتب موديل الجهاز للبحث داخل ${meta.label}', meta.icon, meta.color);
    }
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: meta.color));
    }
    if (_error != null) return _errorView();
    if (!_searched) return const SizedBox.shrink();
    if (_records.isEmpty) {
      return _emptyView(
          'لا توجد توافقات مطابقة في ${meta.label}', Icons.search_off);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      itemCount: _records.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          // شريحة عدد النتائج — الحدّ الفاصل بين البحث وقائمته، ويُلحق بها
          // شريط أدوات المالك (إضافة صفّ / صنف كامل) في نفس المكان الذي
          // يرى فيه النتائج — لا تبويب منفصل ولا شاشة أخرى.
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  StatusPill('${_records.length} نتيجة', color: meta.color,
                      icon: meta.icon),
                  const SizedBox(width: 8),
                  Text('في ${meta.label}',
                      style: TextStyle(
                          color: XTheme.textDim, fontSize: 12.5)),
                ]),
                if (_isOwner) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _ownerAddRow,
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('إضافة صفّ', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          );
        }
        return _recordCard(_records[i - 1], meta, i - 1);
      },
    );
  }

  /// بطاقة توافق: شريط نوع ملوّن + أسماء الموديلات، مع فاصل رفيع أسفلها
  /// يفصل الصفوف بصرياً كي لا تتلاصق البطاقات المتتالية.
  Widget _recordCard(CompatRecord r, CompatTypeMeta meta, int index) {
    final models = CompatCatalog.rankModels(r, _query);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        accent: meta.color,
        padding: const EdgeInsets.fromLTRB(16, 14, 18, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.subCategory != null && r.subCategory!.isNotEmpty) ...[
              Row(children: [
                Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: meta.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(r.subCategory!,
                      style: const TextStyle(
                          color: XTheme.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: models
                  .map((m) => _modelChip(m, meta, row: _isOwner ? r : null))
                  .toList(),
            ),
            // أدوات المالك على الصفّ نفسه: إضافة نصّ وتعديل وحذف في موضعها
            // الطبيعي بجانب البيانات، بلا تبويب منفصل.
            if (_isOwner) ...[
              if (_savingRows.contains(r.id)) const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Row(children: [
                TextButton.icon(
                  onPressed: _savingRows.contains(r.id) ? null : () => _ownerAddModel(r),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('إضافة نصّ', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: meta.color,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _savingRows.contains(r.id) ? null : () => _ownerEditRow(r),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('تعديل', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: XTheme.cyan,
                  ),
                ),
                TextButton.icon(
                  onPressed: _savingRows.contains(r.id) ? null : () => _ownerDeleteRow(r),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('حذف', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: XTheme.danger,
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  /// رقاقة موديل — يُبرَز الجزء المطابق لكلمة البحث.
  ///
  /// للمالك تظهر × على الرقاقة نفسها فيحذف ذلك النصّ وحده من الصفّ، بلا
  /// فتح نموذج ولا مساس ببقية الموديلات.
  Widget _modelChip(String m, CompatTypeMeta meta, {CompatRecord? row}) {
    final q = normalizeModel(_query);
    final hit = q.isNotEmpty && normalizeModel(m).contains(q);
    final chip = Container(
      padding: EdgeInsets.fromLTRB(12, 7, row == null ? 12 : 7, 7),
      decoration: BoxDecoration(
        color: hit ? meta.color.withOpacity(.22) : meta.color.withOpacity(.08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
            color: meta.color.withOpacity(hit ? .60 : .18),
            width: hit ? 1.3 : 1),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text.rich(_highlighted(m, q, meta),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        if (row != null) ...[
          const SizedBox(width: 2),
          // هدف لمس صغير فعلاً — أيقونة 15 داخل حشو 4 — فتُخطئ الضغطة أقل
          // قدر ممكن على شاشة ازدحام الرقاقات.
          InkWell(
            onTap: _savingRows.contains(row.id) ? null : () => _ownerRemoveModel(row, m),
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close_rounded,
                  size: 15, color: meta.color.withOpacity(.85)),
            ),
          ),
        ],
      ]),
    );
    return chip;
  }

  /// يحذف موديلاً واحداً من صفّ.
  ///
  /// لو كان آخر موديل لم يبقَ ما يُبحث فيه، فيُحذف الصفّ نفسه — والخادم
  /// يرفض قائمة موديلات فارغة، فترك الصفّ فارغاً كان سيفشل بصمت.
  Future<void> _ownerRemoveModel(CompatRecord r, String model) async {
    final left = r.models.where((m) => m != model).toList();
    final last = left.isEmpty;
    final ok = await _confirm(
        'حذف «$model» من الصفّ؟',
        last
            ? 'هذا آخر نصّ في الصفّ، فيُحذف الصفّ كاملاً لأنه لن يبقى فيه ما يُبحث.'
            : 'يُحذف هذا النصّ وحده ويبقى بقية الصفّ كما هو.');
    if (!ok) return;
    try {
      final saved = await _saveRow(r, last ? null : {'compatibleModels': left});
      if (saved) _ownerToast(last ? 'تم حذف الصفّ' : 'تم حذف النصّ');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.message : 'تعذر الحفظ — تحقق من الاتصال')));
      }
    }
  }

  /// يُضيف نصّاً إلى الصفّ القائم داخل السياق الذي يراه المالك.
  Future<void> _ownerAddModel(CompatRecord r) async {
    final c = TextEditingController();
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        title: const Text('إضافة نصّ إلى الصفّ',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        content: TextField(
          controller: c,
          maxLines: 4,
          minLines: 1,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'الموديل الجديد',
            helperText: 'سطر لكل موديل إن أضفت أكثر من واحد',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              final add = splitModelLines(c.text).map((e) => e.toLowerCase());
              if (add.isEmpty) return;
              // الدمج في العميل يحفظ النصّ الأصلي للمالك ويرسل القائمة
              // النهائية مرة واحدة، فلا يعتمد على دمج الخادم وحده.
              final list = <String>[...r.models];
              for (final m in add) {
                if (!list.any((e) => normalizeModel(e) == normalizeModel(m))) {
                  list.add(m);
                }
              }
              try {
                final saved = await _saveRow(r, {'compatibleModels': list});
                if (saved && ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                    ..clearSnackBars()
                    ..showSnackBar(SnackBar(
                      content: Text(e is ApiException ? e.message : 'تعذر الحفظ — تحقق من الاتصال')));
                }
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    if (added == true) _ownerToast('تمت إضافة النصّ');
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
        content: Text(body, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد')),
        ],
      ),
    );
    return ok == true;
  }

  TextSpan _highlighted(String text, String q, CompatTypeMeta meta) {
    if (q.isEmpty) return TextSpan(text: text);
    final idx = normalizeModel(text).indexOf(q);
    if (idx < 0) return TextSpan(text: text);
    return TextSpan(children: [
      TextSpan(text: text.substring(0, idx)),
      TextSpan(
          text: text.substring(idx, idx + q.length),
          style: TextStyle(
              color: meta.color,
              fontWeight: FontWeight.w900,
              backgroundColor: meta.color.withOpacity(.22))),
      TextSpan(text: text.substring(idx + q.length)),
    ]);
  }

  Widget _emptyView(String message, [IconData? icon, Color? color]) {
    final c = color ?? XTheme.textDim;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // الأيقونة داخل حلقة متدرّجة — شاشة الفراغ تبدو مقصودة لا معطّلة
        Container(
          width: 84, height: 84,
          decoration: BoxDecoration(
            color: c.withOpacity(.10),
            shape: BoxShape.circle,
            border: Border.all(color: c.withOpacity(.22)),
          ),
          child: Icon(icon ?? Icons.inbox_outlined, size: 38, color: c),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: XTheme.textDim,
                  height: 1.7,
                  fontSize: 13.5)),
        ),
        // المالك قد لا يجد الصفّ لأنه غير موجود بعد — فيضيفه من هنا فوراً
        // بدل أن يخرج إلى شاشة تحرير منفصلة ثم يعود ليبحث.
        if (_isOwner) ...[
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _ownerAddRow,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('إضافة صفّ'),
          ),
        ],
      ]),
    );
  }

  Widget _errorView() {
    final icon = _quotaEmpty
        ? Icons.monetization_on_outlined
        : (_locked ? Icons.lock_outline : Icons.error_outline);
    final color = (_quotaEmpty || _locked) ? XTheme.gold : XTheme.danger;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 84, height: 84,
          decoration: BoxDecoration(
            color: color.withOpacity(.10),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(.24)),
          ),
          child: Icon(icon, size: 36, color: color),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: XTheme.textDim, height: 1.6, fontSize: 13.5)),
        ),
        const SizedBox(height: 16),
        if (_locked || _quotaEmpty)
          ElevatedButton.icon(
            onPressed: () => showSubscribeDialog(context),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('تواصل مع المالك'),
            style: ElevatedButton.styleFrom(
              backgroundColor: XTheme.accent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(XTheme.rMd)),
            ),
          )
        else
          TextButton.icon(
              onPressed: () => _search(_query.trim()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('إعادة المحاولة')),
      ]),
    );
  }
}
