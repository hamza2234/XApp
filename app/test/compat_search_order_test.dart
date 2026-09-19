import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// ترتيب نتائج بحث التوافقات.
///
/// كان الاستعلام بلا ORDER BY، فيُرجع SQLite الصفوف بترتيب تخزين اعتباطي
/// ويظهر السجل المطابق تماماً بعد صفّين. هذه الاختبارات تحرس وجود الترتيب
/// وبنية سجل التوافقات الحقيقية التي يعتمد عليها.
void main() {
  final src = File('../worker/src/index.ts');
  late String ts;

  setUpAll(() {
    // الاختبار يعمل من مجلد app، والمصدر في worker المجاور.
    expect(src.existsSync(), isTrue,
        reason: 'لم يُعثر على مصدر العامل في ${src.absolute.path}');
    ts = src.readAsStringSync();
  });

  test('بحث التوافقات يحمل ترتيباً صريحاً لا ترتيب تخزين اعتباطي', () {
    expect(ts.contains('async function mirrorSearchCompat'), isTrue);
    final body = ts.substring(ts.indexOf('async function mirrorSearchCompat'));
    final fn = body.substring(0, body.indexOf('\n}\n'));
    expect(fn.contains('ORDER BY'),
        isTrue,
        reason: 'الاستعلام بلا ORDER BY يظهر النتائج بترتيب اعتباطي');
  });

  test('الترتيب يعتمد على الملاءمة لا على المعرّف وحده', () {
    expect(ts.contains('function relevanceScore'), isTrue);
    final body = ts.substring(ts.indexOf('function relevanceScore'));
    final fn = body.substring(0, body.indexOf('\n}\n'));
    // الحقل الحقيقي في سجلات التوافقات قائمة موديلات لا حقلاً مفرداً.
    expect(fn.contains('compatibleModels'), isTrue,
        reason: 'بنية السجل فيها compatibleModels كقائمة');
    // المطابقة التامة في موديل يجب أن تزن أكثر من مطابقة عابرة.
    expect(fn.contains('m === t'), isTrue);
    expect(fn.contains('subCategory'), isTrue);
  });

  test('الترتيب يُطبَّق فعلاً على النتائج قبل القصّ', () {
    final body = ts.substring(ts.indexOf('async function mirrorSearchCompat'));
    final fn = body.substring(0, body.indexOf('\n}\n'));
    expect(fn.contains('sort('), isTrue, reason: 'لا ترتيب فعلي على الصفوف');
    // القصّ بعد الترتيب لا قبله، وإلا ضاعت أفضل النتائج.
    final sortAt = fn.indexOf('sort(');
    final sliceAt = fn.indexOf('.slice(0, opts.limit)');
    expect(sortAt, lessThan(sliceAt));
    // نُجلب أكثر من الحدّ كي يبقى للترتيب مجال.
    expect(fn.contains('fetchLimit'), isTrue);
  });
}