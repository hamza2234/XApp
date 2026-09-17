import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/compat_catalog.dart';
import '../core/models.dart';
import 'theme.dart';
import 'subscribe_dialog.dart';

/// ميتاداتا نوع القطعة: أيقونة ولون وترتيب مستقل لكل نوع.
class CompatTypeMeta {
  const CompatTypeMeta(this.label, this.icon, this.color, this.rank);
  final String label;
  final IconData icon;
  final Color color;

  /// ترتيب العرض: الشاشات أولاً ثم البطاريات فالزجاج فضد الكسر.
  final int rank;

  static const _map = <String, CompatTypeMeta>{
    'SCREEN': CompatTypeMeta('شاشات', Icons.smartphone, Color(0xFF4D8DFF), 0),
    'BATTERY': CompatTypeMeta('بطاريات', Icons.battery_full, Color(0xFF2EE6A8), 1),
    'GLASS': CompatTypeMeta('زجاج', Icons.shield_outlined, Color(0xFF8B5CF6), 2),
    'INCASSABLE':
        CompatTypeMeta('ضد الكسر', Icons.verified_outlined, Color(0xFFF5B942), 3),
  };

  /// كل قيمة غير معروفة تأخذ أيقونة محايدة مستقلة وأخيرة في الترتيب.
  static CompatTypeMeta of(String type) =>
      _map[type.toUpperCase()] ??
      CompatTypeMeta(type, Icons.build_outlined, XTheme.cyan, 100);

  static int rankOf(String type) => of(type).rank;
}

/// شاشة شركة: يختار المستخدم نوع القطعة أولاً (شاشات/بطاريات/زجاج/ضد الكسر)
/// ثم يبحث داخل ذلك النوع فقط. لا نتائج قبل اختيار النوع وكتابة الاستعلام.
class CompatBrandScreen extends StatefulWidget {
  const CompatBrandScreen({super.key, required this.api, required this.brand});
  final Api api;
  final CompatBrand brand;

  @override
  State<CompatBrandScreen> createState() => _CompatBrandScreenState();
}

class _CompatBrandScreenState extends State<CompatBrandScreen> {
  final _q = TextEditingController();
  CompatCatalog? _catalog;
  bool _loading = true;
  String? _loadError;
  bool _locked = false;
  String? _type;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  /// يُجلب كامل سجلات الشركة مرة واحدة وتُبنى فهرسة محلية، فيعمل العدّ
  /// والبحث داخل النوع فوراً وبلا طلبات متكررة.
  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      // الشركة الفرعية تُطلب بمعرّفها ليصفّيها الخادم على كلمتها.
      final list = await widget.api.compatByBrand(widget.brand.ref);
      if (!mounted) return;
      setState(() {
        _catalog =
            CompatCatalog(list.map((e) => CompatRecord.fromJson(e)).toList());
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.message;
        _locked = e.forbidden;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'تعذر تحميل بيانات الشركة';
      });
    }
  }

  void _selectType(String type) {
    setState(() {
      _type = _type == type ? null : type;
      _query = '';
    });
    _q.clear();
  }

  void _onQuery(String v) => setState(() => _query = v);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.brand.displayName)),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: XTheme.accent));
    }
    if (_loadError != null) return _errorView();

    final catalog = _catalog!;
    if (catalog.availableTypes.isEmpty) {
      return _emptyView('لا توجد توافقات لهذه الشركة');
    }

    return Column(
      children: [
        _typeSelector(catalog),
        if (_type != null) _searchField(),
        Expanded(child: _results(catalog)),
      ],
    );
  }

  /// صف الأنواع: أيقونة واسم وعدد مستقل لكل نوع — بلا خلط بين الأنواع.
  Widget _typeSelector(CompatCatalog catalog) {
    final types = [...catalog.availableTypes]
      ..sort((a, b) => CompatTypeMeta.rankOf(a).compareTo(
          CompatTypeMeta.rankOf(b)));
    final counts = catalog.counts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in types)
            _typeChip(t, counts[t] ?? 0, _type == t),
        ],
      ),
    );
  }

  Widget _typeChip(String type, int count, bool selected) {
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
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: meta.color.withOpacity(.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: meta.color)),
          ),
        ]),
      ),
    );
  }

  Widget _searchField() {
    final meta = CompatTypeMeta.of(_type!);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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

  Widget _results(CompatCatalog catalog) {
    if (_type == null) {
      return _emptyView(
          'اختر نوع القطعة أولاً — شاشات أو بطاريات أو زجاج أو ضد الكسر',
          Icons.touch_app);
    }
    final meta = CompatTypeMeta.of(_type!);
    final total = catalog.byType(_type!).length;

    if (_query.trim().isEmpty) {
      return _emptyView(
          'اكتب موديل الجهاز للبحث داخل ${meta.label}\n($total توافق متاح)',
          meta.icon,
          meta.color);
    }

    final found = catalog.search(_type!, _query);
    if (found.isEmpty) {
      return _emptyView('لا توجد توافقات مطابقة في ${meta.label}',
          Icons.search_off);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
      itemCount: found.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 12),
            child: Row(children: [
              Icon(meta.icon, size: 17, color: meta.color),
              const SizedBox(width: 8),
              Text('${found.length} نتيجة في ${meta.label}',
                  style: TextStyle(
                      color: meta.color,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ]),
          );
        }
        return _recordCard(found[i - 1], meta, i - 1);
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
          // فاصل بصري رفيع بين الصفوف.
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
        color: hit
            ? meta.color.withOpacity(.26)
            : meta.color.withOpacity(.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: meta.color.withOpacity(hit ? .7 : .2)),
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
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_locked ? Icons.lock_outline : Icons.error_outline,
            size: 44, color: _locked ? XTheme.gold : XTheme.danger),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(_loadError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: XTheme.textDim)),
        ),
        const SizedBox(height: 12),
        if (_locked)
          ElevatedButton.icon(
            onPressed: () => showSubscribeDialog(context),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('تواصل مع المالك'),
            style: ElevatedButton.styleFrom(
                backgroundColor: XTheme.accent,
                foregroundColor: Colors.white),
          )
        else
          TextButton(
              onPressed: _loadCatalog, child: const Text('إعادة المحاولة')),
      ]),
    );
  }
}