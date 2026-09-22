/// شاشة تحرير التوافقات للمالك — إضافة وتعديل صفوف متتالية بلا مغادرة الشاشة.
///
/// القاعدة: المرآة مصدر للقراءة فقط ولا تُكتب أبداً. كل تغيير هنا يُحفظ في
/// `x_compat_edits` كطبقة فوقها، فلا يمكن للمالك — ولو بالخطأ — أن يُفسد
/// البيانات الأصلية. هذه الشاشة لا تعرف ذلك وتتعامل مع واجهة الخادم فقط.
library;

import 'package:flutter/material.dart';

import '../core/api.dart';
import 'theme.dart';

/// أنواع القطع المعروفة في التطبيق — تُعرض كاختيار لا كنصّ حرّ.
const _knownTypes = ['SCREEN', 'BATTERY', 'GLASS', 'INCASSABLE'];

class CompatEditorScreen extends StatefulWidget {
  const CompatEditorScreen({super.key, required this.api});
  final Api api;

  @override
  State<CompatEditorScreen> createState() => _CompatEditorScreenState();
}

class _CompatEditorScreenState extends State<CompatEditorScreen> {
  List<String> _brands = [];
  List<Map<String, String>> _subBrands = [];
  String? _brand;

  List<dynamic> _records = [];
  List<String> _types = [];
  bool _loading = false;
  String? _error;
  String _filter = '';
  String _typeFilter = '';

  @override
  void initState() {
    super.initState();
    _loadBrands();
  }

  Future<void> _loadBrands() async {
    try {
      final r = await widget.api.ownerCompatBrands();
      if (!mounted) return;
      setState(() {
        _brands = (r['brands'] as List? ?? []).map((e) => '$e').toList();
        _subBrands = (r['subBrands'] as List? ?? [])
            .map((e) => {
                  'key': '${(e as Map)['key']}',
                  'name': '${e['name']}',
                })
            .toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadRecords() async {
    final brand = _brand;
    if (brand == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.ownerCompatList(
        brand: brand,
        q: _filter,
        type: _typeFilter,
      );
      if (!mounted) return;
      setState(() {
        _records = r['records'] as List? ?? [];
        _types = (r['types'] as List? ?? []).map((e) => '$e').toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _editRecord(Map record) async {
    final id = '${record['id']}';
    final models = TextEditingController(
        text: (record['compatibleModels'] as List? ?? []).join('، '));
    // النوع الفرعي كائن في بعض السجلات ونصّ في غيرها — نقرأ الشكلين.
    final subRaw = record['subCategory'];
    final sub = TextEditingController(
        text: subRaw is Map ? '${subRaw['name'] ?? ''}' : '${subRaw ?? ''}');
    var type = '${record['componentType'] ?? ''}'.toUpperCase();
    if (!_types.contains(type)) type = _types.isNotEmpty ? _types.first : '';

    final saved = await showDialog<bool>(
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
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'الموديلات المتوافقة',
                  helperText: 'افصل بينها بفاصلة أو سطر جديد',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: type.isEmpty ? null : type,
                decoration: const InputDecoration(labelText: 'نوع القطعة'),
                items: _types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setLocal(() => type = v ?? type),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sub,
                decoration: const InputDecoration(labelText: 'الوصف / النوع الفرعي'),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final list = models.text
                    .split(RegExp(r'[,،\n]'))
                    .map((e) => e.trim().toLowerCase())
                    .where((e) => e.isNotEmpty)
                    .toList();
                if (list.isEmpty || type.isEmpty) return;
                try {
                  await widget.api.ownerCompatPatch(
                    brand: _brand!,
                    id: id,
                    fields: {
                      'compatibleModels': list,
                      'componentType': type,
                      'subCategory': {'name': sub.text.trim()},
                    },
                  );
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
    if (saved == true) await _loadRecords();
  }

  /// إضافة صفوف متتالية بلا مغادرة الشاشة: بعد الحفظ يبقى الحقل فارغاً
  /// وجاهزاً للصف التالي — المالك يكتب عادة أكثر من صفّ في الجلسة الواحدة.
  Future<void> _addRows() async {
    final models = TextEditingController();
    var type = 'SCREEN';
    final sub = TextEditingController();
    var busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final added = <Map<String, dynamic>>[];
          return AlertDialog(
            backgroundColor: XTheme.surface,
            title: const Text('إضافة صفوف توافق',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                  'اكتب صفّاً واحفظه، ثم اكتب الذي بعده. أو أدخل عدة أسطر مرة واحدة.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white60),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: models,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'الموديلات المتوافقة',
                    helperText: 'سطر لكل صفّ لإضافة دفعة، أو فاصلة داخل الصفّ',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'نوع القطعة'),
                  items: (_types.isEmpty ? _knownTypes : _types)
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setLocal(() => type = v ?? type),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sub,
                  decoration:
                      const InputDecoration(labelText: 'الوصف / النوع الفرعي'),
                ),
                if (added.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('أُضيف في هذه الجلسة: ${added.length}',
                      style: const TextStyle(
                          fontSize: 12, color: XTheme.ok,
                          fontWeight: FontWeight.w700)),
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إغلاق'),
              ),
              // حفظ بلا إغلاق: هذا هو جوهر «صفّاً بعد صفّ».
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final text = models.text.trim();
                        if (text.isEmpty) return;
                        // سطر لكل صفّ متى كانت الأسطر أكثر من واحد.
                        final lines = text
                            .split('\n')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();
                        final rows = lines.length > 1
                            ? lines
                                .map((l) => {
                                      'compatibleModels': l,
                                      'componentType': type,
                                      'subCategory':
                                          sub.text.trim().isEmpty ? type : sub.text.trim(),
                                    })
                                .toList()
                            : [
                                {
                                  'compatibleModels': text,
                                  'componentType': type,
                                  'subCategory':
                                      sub.text.trim().isEmpty ? type : sub.text.trim(),
                                }
                              ];
                        setLocal(() => busy = true);
                        try {
                          final r = await widget.api
                              .ownerCompatAdd(brand: _brand!, rows: rows);
                          final n = (r['ids'] as List? ?? []).length;
                          added.addAll(List.generate(n, (_) => <String, dynamic>{}));
                          models.clear();
                          setLocal(() => busy = false);
                        } on ApiException catch (e) {
                          setLocal(() => busy = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text(e.message)));
                          }
                        }
                      },
                child: busy
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ وإضافة التالي'),
              ),
            ],
          );
        },
      ),
    );
    await _loadRecords();
  }

  Future<void> _deleteRecord(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        title: const Text('حذف الصفّ؟'),
        content: const Text('يُخفى من نتائج البحث. البيانات الأصلية لا تُمسّ.'),
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
      await widget.api.ownerCompatDelete(brand: _brand!, id: id);
      await _loadRecords();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _addType() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: XTheme.surface,
        title: const Text('إضافة نوع قطعة'),
        content: TextField(
          controller: name,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'اسم النوع', hintText: 'مثال: CAMERA'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إضافة')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      await widget.api
          .ownerCompatAddType(brand: _brand!, name: name.text.trim());
      await _loadRecords();
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
      backgroundColor: XTheme.bg,
      appBar: AppBar(
        title: const Text('تحرير التوافقات'),
        actions: [
          if (_brand != null)
            IconButton(
              tooltip: 'إضافة نوع قطعة',
              icon: const Icon(Icons.new_label_outlined),
              onPressed: _addType,
            ),
          if (_brand != null)
            IconButton(
              tooltip: 'إضافة صفوف',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _addRows,
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            value: _brand,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'الشركة', border: OutlineInputBorder()),
            items: [
              ..._subBrands.map((s) => DropdownMenuItem(
                  value: 'v_${s['key']}',
                  child: Text('${s['name']} (افتراضي)',
                      style: const TextStyle(fontSize: 13)))),
              ..._brands.map((b) =>
                  DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 13)))),
            ],
            onChanged: (v) {
              setState(() {
                _brand = v;
                _records = [];
              });
              _loadRecords();
            },
          ),
        ),
        if (_brand != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'بحث',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onSubmitted: (v) {
                    _filter = v;
                    _loadRecords();
                  },
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _typeFilter.isEmpty ? null : _typeFilter,
                hint: const Text('الكل', style: TextStyle(fontSize: 12)),
                items: _types
                    .map((t) => DropdownMenuItem(
                        value: t, child: Text(t, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (v) {
                  setState(() => _typeFilter = v ?? '');
                  _loadRecords();
                },
              ),
            ]),
          ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator())
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(_error!, style: const TextStyle(color: XTheme.danger)),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _records.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = _records[i] as Map;
                final models = (r['compatibleModels'] as List? ?? []).join('، ');
                final sub = r['subCategory'];
                final subName =
                    sub is Map ? '${sub['name'] ?? ''}' : '${sub ?? ''}';
                return ListTile(
                  dense: true,
                  title: Text(models,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    '${r['componentType'] ?? ''}${subName.isEmpty ? '' : ' — $subName'}'
                    '${r['isNew'] == true ? ' · مُضاف' : ''}'
                    '${r['edited'] == true && r['isNew'] != true ? ' · مُعدّل' : ''}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      onPressed: () => _editRecord(r),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 19, color: XTheme.danger),
                      onPressed: () => _deleteRecord('${r['id']}'),
                    ),
                  ]),
                );
              },
            ),
          ),
      ]),
    );
  }
}
