import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/compat_catalog.dart';
import '../core/models.dart';
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
  const CompatBrandScreen({super.key, required this.api, required this.brand});

  final Api api;
  final CompatBrand brand;

  @override
  State<CompatBrandScreen> createState() => _CompatBrandScreenState();
}

class _CompatBrandScreenState extends State<CompatBrandScreen> {
  /// مهلة قبل إرسال الطلب بعد آخر ضغطة مفتاح. كل طلب جديد يُخصم من
  /// بطاقات المشترك، فالمهلة القصيرة كانت تكلّف بطاقة لكل وقفة قصيرة أثناء
  /// الكتابة. 600ms يجعل كتابة الموديل المتصلة طلباً واحداً — وإعادة البحث
  /// نفسه مجانية داخل نافذة الخادم (15 دقيقة).
  static const _debounce = Duration(milliseconds: 600);

  /// أقل طول استعلام: حرف واحد يطابق كل شيء تقريباً فيُخصم بلا فائدة.
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
  int _remaining = -1;
  bool _searched = false;

  @override
  void dispose() {
    _timer?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _selectType(String type) {
    setState(() {
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
    setState(() => _query = v);
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
        _records = r.records.map((e) => CompatRecord.fromJson(e)).toList();
      });
    } on ApiException catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _records = const [];
        _error = e.message;
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in CompatTypeMeta.orderedTypes)
            _typeChip(t, _type == t),
        ],
      ),
    );
  }

  Widget _typeChip(String type, bool selected) {
    final meta = CompatTypeMeta.of(type);
    return InkWell(
      onTap: () => _selectType(type),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? meta.color.withOpacity(.18)
              : XTheme.surface.withOpacity(.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected
                  ? meta.color.withOpacity(.65)
                  : XTheme.textDim.withOpacity(.18),
              width: selected ? 1.4 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(meta.icon, size: 19, color: meta.color),
          const SizedBox(width: 8),
          Text(meta.label,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: selected ? meta.color : XTheme.text)),
        ]),
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

  /// شريحة الرصيد: تظهر فقط بعد خصم فعلي حتى يعرف المشترك ثمن بحثه.
  Widget _quotaChip() {
    final ok = _remaining > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        Icon(Icons.monetization_on_outlined,
            size: 15, color: ok ? XTheme.gold : XTheme.danger),
        const SizedBox(width: 6),
        Text(ok ? 'البطاقات المتبقية: $_remaining' : 'آخر بطاقاتك',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: ok ? XTheme.gold : XTheme.danger)),
        if (_charged) ...[
          const Spacer(),
          Text('خُصمت بطاقة لهذا البحث',
              style:
                  TextStyle(fontSize: 11, color: XTheme.textDim.withOpacity(.8))),
        ],
      ]),
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
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
            child: Row(children: [
              Icon(meta.icon, size: 17, color: meta.color),
              const SizedBox(width: 8),
              Text('${_records.length} نتيجة في ${meta.label}',
                  style: TextStyle(
                      color: meta.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ]),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          GlassCard(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
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
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                ],
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: models.map((m) => _modelChip(m, meta)).toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      meta.color.withOpacity(index.isEven ? .28 : 0),
                      meta.color.withOpacity(index.isEven ? 0 : .28),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// رقاقة موديل — يُبرَز الجزء المطابق لكلمة البحث.
  Widget _modelChip(String m, CompatTypeMeta meta) {
    final q = normalizeModel(_query);
    final hit = q.isNotEmpty && normalizeModel(m).contains(q);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: hit ? meta.color.withOpacity(.26) : meta.color.withOpacity(.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: meta.color.withOpacity(hit ? .7 : .2)),
      ),
      child: Text.rich(_highlighted(m, q, meta),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
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
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon ?? Icons.inbox_outlined,
            size: 52, color: (color ?? XTheme.textDim).withOpacity(.55)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: XTheme.textDim, height: 1.7)),
        ),
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
        Icon(icon, size: 44, color: color),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: XTheme.textDim, height: 1.6)),
        ),
        const SizedBox(height: 12),
        if (_locked || _quotaEmpty)
          ElevatedButton.icon(
            onPressed: () => showSubscribeDialog(context),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('تواصل مع المالك'),
            style: ElevatedButton.styleFrom(
                backgroundColor: XTheme.accent, foregroundColor: Colors.white),
          )
        else
          TextButton(
              onPressed: () => _search(_query.trim()),
              child: const Text('إعادة المحاولة')),
      ]),
    );
  }
}
