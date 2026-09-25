import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// أمان تحرير التوافقات: الحقول تُفلتَر واحداً واحداً، والنوع يُتحقَّق منه،
/// والحجم محدود. كان `patch` يدمج `fields` كما وصل، فجلسة مالك مسروقة تكتب
/// أي مفتاح وأي حجم في صفّ يقرأه كل المستخدمين.
void main() {
  final src = File('../worker/src/index.ts');
  late String ts;

  setUpAll(() {
    expect(src.existsSync(), isTrue,
        reason: 'لم يُعثر على مصدر العامل في ${src.absolute.path}');
    ts = src.readAsStringSync().replaceAll('\r\n', '\n');
  });

  String fnBody(String marker) {
    final at = ts.indexOf(marker);
    expect(at >= 0, isTrue, reason: 'لم يُعثر على $marker');
    final body = ts.substring(at);
    return body.substring(0, body.indexOf('\n}\n'));
  }

  group('تقسيم الموديلات في العامل', () {
    test('الفاصل سطر جديد لا فاصلة', () {
      final fn = fnBody('function splitModelLines');
      expect(fn.contains(r'[\n\r\u2028\u2029\u0085]'), isTrue,
          reason: 'يجب أن يقسم على محارف السطر');
      // الفاصلة نفسها لا يجوز أن تكون ضمن محارف الفصل.
      expect(fn.contains(r'[,،\n]'), isFalse,
          reason: 'وجود فاصلة كفاصل يعني انشقاق الأسماء التي تحملها');
      expect(fn.contains('،'), isFalse,
          reason: 'الفاصلة العربية فاصل أيضاً — لا يجوز أن تفصل');
    });
  });

  group('تنقية قائمة الموديلات', () {
    test('موجودة وتفرض الحدود', () {
      final fn = fnBody('function sanitizeModels');
      expect(fn.contains('Array.isArray'), isTrue);
      expect(fn.contains('COMPAT_MAX_MODEL_LEN'), isTrue);
      expect(fn.contains('COMPAT_MAX_MODELS'), isTrue);
    });

    test('تُستعمل في patch لا في add وحده', () {
      final patch = fnBody("if (op === 'patch')");
      expect(patch.contains('sanitizeModels'), isTrue,
          reason: 'patch كان يثق بـfields كما وصل');
    });

    test('كل حقل يُفلتَر باسمه ولا يُقبل مفتاح اعتباطي', () {
      final patch = fnBody("if (op === 'patch')");
      for (final key in [
        'compatibleModels',
        'componentType',
        'subCategory',
        'note'
      ]) {
        expect(patch.contains("key === '$key'"), isTrue,
            reason: 'الحقل $key يجب أن يُفلتَر صراحةً');
      }
    });

    test('لا دمج مباشر لحقول العميل كما وصلت', () {
      final patch = fnBody("if (op === 'patch')");
      expect(patch.contains('merged = { ...merged, ...safe }'), isTrue,
          reason: 'الدمج يجب أن يكون من الكائن المُنقّى لا من body.fields');
    });
  });

  group('التحقق من نوع القطعة', () {
    test('نوع مجهول يُرفض', () {
      final fn = fnBody('async function assertCompatType');
      expect(fn.contains('COMPAT_TYPES.includes'), isTrue);
      expect(fn.contains('نوع قطعة غير معروف'), isTrue);
    });

    test('نوع أضافه المالك مقبول', () {
      final fn = fnBody('async function assertCompatType');
      expect(fn.contains("kind = 'cat'"), isTrue,
          reason: 'أنواع المالك المضافة يجب ألا تُرفض');
    });

    test('يُستعمل في الإضافة والتعديل معاً', () {
      expect(fnBody("if (op === 'add')").contains('assertCompatType'), isTrue);
      expect(fnBody("if (op === 'patch')").contains('assertCompatType'), isTrue);
    });

    test('الإضافة لم تعد تقبل أي نصّ كنوع', () {
      final add = fnBody("if (op === 'add')");
      final old = "String(r.componentType ?? '').trim().toUpperCase()";
      expect(add.contains(old), isFalse,
          reason: 'كان النوع يُقبل بلا تحقق فيُخزَّن نوع لا وجود له');
    });
  });

  group('حدود الحجم', () {
    test('الحدود معرّفة', () {
      for (final c in [
        'COMPAT_MAX_MODELS',
        'COMPAT_MAX_MODEL_LEN',
        'COMPAT_MAX_SUB_LEN',
        'COMPAT_MAX_NOTE_LEN'
      ]) {
        expect(ts.contains('const $c ='), isTrue, reason: 'ينقص حدّ $c');
      }
    });

    test('حدّ الصفوف في النداء الواحد قائم', () {
      expect(ts.contains('الحد 50 صفاً في المرة'), isTrue);
    });
  });

  group('بوابة لوحة المالك', () {
    test('وقت التحقق من الرمز', () {
      expect(ts.contains('verifyOwnerJwt'), isTrue);
      expect(ts.contains('ownerPayload.sub !== caller.uid'), isTrue,
          reason: 'ربط الجلسة بالمستخدم يمنع إعادة استخدام رمز مالك آخر');
    });

    test('كل ردود اللوحة مشفّرة', () {
      expect(ts.contains("'x-enc': 'aes-gcm'"), isTrue);
      expect(ts.contains("'cache-control': 'no-store'"), isTrue);
    });

    test('محاولة غير المالك تُسجَّل', () {
      expect(ts.contains('non_owner_admin_attempt'), isTrue);
    });
  });
}
