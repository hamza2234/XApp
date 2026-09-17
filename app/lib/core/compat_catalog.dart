/// فهرس التوافقات المحلي — يبني فهرساً من سجلات الشركة المجلوبة من الخادم.
///
/// السبب: عمود `search_text` غير موجود في مرآة القراءة، فبحث الخادم النصّي
/// لا يجد الموديلات. لذلك تُجلب سجلات الشركة مرة واحدة (بلا نص بحث) ويُبنى
/// الفهرس ويُبحث محلياً — بدون أي كتابة في الموارد المشتركة.
library;

import 'models.dart';

/// ترتيب عرض أنواع القطع.
const compatTypeOrder = ['SCREEN', 'BATTERY', 'GLASS', 'INCASSABLE'];

/// تطبيع اسم الموديل: يزيل محارف العرض الصفرية والبادئات ويوحّد الحالة.
String normalizeModel(String raw) => raw
    .replaceAll('\u200b', '')
    .replaceAll(RegExp(r'[\u200e\u200f\ufeff]'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'^(model|موديل)\s*:\s*', caseSensitive: false), '')
    .trim()
    .toLowerCase();

class CompatCatalog {
  CompatCatalog(this.records) {
    for (final r in records) {
      _byType.putIfAbsent(r.componentType, () => []).add(r);
      final keys = <String>[];
      for (final m in r.models) {
        final k = normalizeModel(m);
        if (k.length >= 2) keys.add(k);
      }
      _normalized[r.id] = keys;
    }
  }

  final List<CompatRecord> records;
  final Map<String, List<CompatRecord>> _byType = {};
  final Map<String, List<String>> _normalized = {};

  /// عدد التوافقات لكل نوع — من السجلات المجلوبة فعلياً.
  Map<String, int> get counts =>
      {for (final e in _byType.entries) e.key: e.value.length};

  int get total => records.length;

  /// الأنواع الموجودة فعلاً في بيانات هذه الشركة، بترتيب العرض المعتمد.
  List<String> get availableTypes {
    final present = _byType.keys.toSet();
    final ordered = [
      ...compatTypeOrder.where(present.contains),
      ...present.where((t) => !compatTypeOrder.contains(t)),
    ];
    return ordered;
  }

  List<CompatRecord> byType(String type) => _byType[type] ?? const [];

  /// بحث داخل نوع واحد فقط. يرجع نتائج مرتّبة حسب جودة المطابقة.
  List<CompatRecord> search(String type, String query) {
    final q = normalizeModel(query);
    if (q.isEmpty) return const [];
    final tokens = q.split(' ').where((t) => t.isNotEmpty).toList();

    final scored = <(int, CompatRecord)>[];
    for (final rec in byType(type)) {
      var best = 99;
      for (final key in _normalized[rec.id] ?? const <String>[]) {
        final s = _score(key, q, tokens);
        if (s < best) best = s;
        if (best == 0) break;
      }
      if (best < 99) scored.add((best, rec));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final e in scored) e.$2];
  }

  /// 0 مطابقة تامة، 1 بداية الاسم، 2 بداية كلمة، 3 داخل الاسم، 4 كل الكلمات.
  static int _score(String key, String q, List<String> tokens) {
    if (key == q) return 0;
    if (key.startsWith(q)) return 1;
    if (key.contains(' $q')) return 2;
    if (key.contains(q)) return 3;
    if (tokens.length > 1 && tokens.every(key.contains)) return 4;
    return 99;
  }

  /// نماذج السجل مرتّبة: المطابقة للبحث أولاً.
  static List<String> rankModels(CompatRecord rec, String query) {
    final q = normalizeModel(query);
    if (q.isEmpty) return rec.models;
    final matched = <String>[];
    final rest = <String>[];
    for (final m in rec.models) {
      if (normalizeModel(m).contains(q)) {
        matched.add(m);
      } else {
        rest.add(m);
      }
    }
    return [...matched, ...rest];
  }
}
