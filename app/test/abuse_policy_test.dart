import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// سياسة الحظر وحدود المعدّل في العامل.
///
/// العلة التي دفعت لهذه الاختبارات: المستخدم (وهو المالك) رأى «طلبات كثيرة»
/// ثم حظراً وهو يتصفّح تطبيقه بيده. السبب لم يكن إساءة، بل ثلاثة أخطاء
/// تصميم تراكمت:
///
///  1. `/v1/chat/state` كان يشارك دلو `list` مع تصفّح الشركات. الدردشة
///     تستدعيه دورياً، فاستهلكت الدلو وحدها ثم رُفض المستخدم في أول بحث.
///  2. عدّاد الإساءة كان يحظر الجهاز نهائياً عند 15، والعنوان عند 60 —
///     أرقام يبلغها إنسان على شبكة متقطّعة أو نسخة تُحدَّث مراراً.
///  3. الانفجار كان يُحتسب إساءة «خطيرة»، فعاصفة إعادة المحاولة بعده
///     انقطاع تحوّل إلى حظر دائم.
///
/// هذه الاختبارات تثبّت أن العلة لا تعود: لكل مسار دوريّ دلو مستقل،
/// وعتبات الحظر أعلى بكثير من السلوك البشري، وللمالك استثناء.
void main() {
  final src = File('../worker/src/index.ts');
  late String ts;

  setUpAll(() {
    expect(src.existsSync(), isTrue,
        reason: 'لم يُعثر على مصدر العامل في ${src.absolute.path}');
    ts = src.readAsStringSync();
  });

  /// جسم دالة بالاسم حتى أول قوس إغلاق في بداية سطر.
  String fnBody(String name) {
    final i = ts.indexOf(name);
    expect(i, greaterThanOrEqualTo(0), reason: 'دالة $name غير موجودة');
    final rest = ts.substring(i);
    final end = rest.indexOf('\n}\n');
    return end < 0 ? rest : rest.substring(0, end);
  }

  test('حالة الدردشة لا تشارك دلو حدّ تصفّح الشركات', () {
    // يشارك `list` معناه: الدردشة تستنفد حدّ البحث فيُرفض المستخدم في
    // شاشة لا علاقة لها بالدردشة.
    final i = ts.indexOf("path === '/v1/chat/state'");
    expect(i, greaterThanOrEqualTo(0));
    final body = ts.substring(i, i + 900);
    expect(body.contains("'list'"), isFalse,
        reason: 'دلو مشترك مع تصفّح الشركات يستنفد الحدّ في دقائق');
    expect(body.contains('chatstate'), isTrue,
        reason: 'للدردشة دلوها المستقل');
  });

  test('حظر الجهاز التلقائي لا يبلغه الاستعمال البشري', () {
    final body = fnBody('async function noteAbuse');
    final m = RegExp(r'dc \+ 1 >= (\d+)').firstMatch(body);
    expect(m, isNotNull, reason: 'عتبة حظر الجهاز غير موجودة');
    final threshold = int.parse(m!.group(1)!);
    expect(threshold, greaterThanOrEqualTo(40),
        reason: 'عتبة منخفضة تحظر جهازاً شرعياً بعد انقطاع شبكة أو تحديث');
  });

  test('حظر العنوان التلقائي أعلى من حظر الجهاز بكثير', () {
    final body = fnBody('async function noteAbuse');
    final m = RegExp(r'count \+ 1 >= (\d+)').firstMatch(body);
    expect(m, isNotNull);
    // المشغّلون يضعون آلاف المستخدمين خلف عنوان واحد، فحظر العنوان
    // يعاقب من لم يذنب.
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(150),
        reason: 'عتبة عنوان منخفضة تحجب جيران الجهاز المسيء');
  });

  test('المالك مستثنى من الحظر التلقائي في كل الفحوص', () {
    // بغير هذا يغلق المالك نفسه خارج تطبيقه باستعماله المشروع، ولا يصل
    // إلى صفحة إلغاء الحظر لأن فحص الحظر يسبق المصادقة.
    for (final fn in ['burstLimit', 'rateLimit', 'detectSweep']) {
      expect(fnBody(fn).contains('hasOwnerSession'),
          isTrue,
          reason: '$fn يحظر المالك بلا استثناء');
    }
  });

  test('الانفجار الشبكي لا يُحتسب إساءة خطيرة تفضي إلى حظر دائم', () {
    final body = fnBody('burstLimit');
    final call = RegExp(r'noteAbuse\([^;]*\)').allMatches(body).map((m) => m.group(0)!);
    expect(call, isNotEmpty, reason: 'الانفجار يجب أن يُسجَّل لا أن يُحظر فقط');
    for (final c in call) {
      expect(c.contains("'low'"), isTrue,
          reason: 'عاصفة إعادة محاولة بعد انقطاع شبكة ليست هجوماً');
    }
  });

  test('كشف مزرعة الأجهزة يسجّل قبل أن يحظر', () {
    final body = fnBody('async function trackDeviceFarm');
    expect(body.contains('ip_hardban'), isTrue,
        reason: 'الحظر بلا أثر في السجل يمنع المالك من معرفة سببه');
  });
}
