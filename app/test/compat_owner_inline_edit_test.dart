import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// شاشة التوافقات: تعديل داخل الصفّ نفسه.
///
/// تُفحص الشاشة كمصدر نصّي لأن بناء الواجهة كاملاً يحتاج شبكةً وجلسة مالك؛
/// والمطلوب هنا حراسة قرارات الواجهة التي طلبها المالك صراحةً.
void main() {
  final src = File('lib/ui/compat_brand_screen.dart');
  late String ui;

  setUpAll(() {
    expect(src.existsSync(), isTrue);
    ui = src.readAsStringSync();
  });

  group('لا وجود لخيار «إضافة صنف كامل»', () {
    test('الزرّ لم يبقَ في الشاشة', () {
      expect(ui.contains('إضافة صنف كامل'), isFalse,
          reason: 'المالك طلب إضافة صفّ فقط');
    });

    test('الدالة لم تبقَ', () {
      expect(ui.contains('_ownerAddSpec'), isFalse);
    });

    test('لا مسار wholeSpec في نموذج الإضافة', () {
      expect(ui.contains('wholeSpec'), isFalse);
    });
  });

  group('علامة × على كل نصّ في الصفّ', () {
    test('الرقاقة تعرض زرّ حذف للمالك', () {
      expect(ui.contains('Icons.close_rounded'), isTrue);
    });

    test('الحذف يخصّ النصّ المعروض لا الصفّ كله', () {
      expect(ui.contains('_ownerRemoveModel'), isTrue);
      expect(ui.contains('يُحذف هذا النصّ وحده'), isTrue);
    });

    test('حذف آخر نصّ يحذف الصفّ بدل إرسال قائمة فارغة', () {
      final at = ui.indexOf('Future<void> _ownerRemoveModel');
      final fn = ui.substring(at, ui.indexOf('\n  }\n', at));
      expect(fn.contains('final last = left.isEmpty'), isTrue);
      expect(fn.contains('ownerCompatDelete'), isTrue,
          reason: 'الخادم يرفض قائمة موديلات فارغة، فالخيار الأخير يُحذف الصفّ');
    });

    test('الحذف يُرسل القائمة بعد استبعاد النصّ المختار', () {
      final at = ui.indexOf('Future<void> _ownerRemoveModel');
      final fn = ui.substring(at, ui.indexOf('\n  }\n', at));
      expect(fn.contains('r.models.where((m) => m != model)'), isTrue);
      expect(fn.contains("'compatibleModels': left"), isTrue);
    });

    test('الزرّ يظهر للمالك وحده', () {
      expect(ui.contains('row: _isOwner ? r : null'), isTrue);
    });
  });

  group('إضافة نصّ داخل الصفّ', () {
    test('زرّ الإضافة موجود على الصفّ', () {
      expect(ui.contains('إضافة نصّ'), isTrue);
      expect(ui.contains('_ownerAddModel'), isTrue);
    });

    test('الدمج لا يكرّر موديلاً موجوداً', () {
      final at = ui.indexOf('Future<void> _ownerAddModel');
      final fn = ui.substring(at, ui.indexOf('\n  }\n', at));
      expect(fn.contains('normalizeModel(e) == normalizeModel(m)'), isTrue,
          reason: 'بلا هذا الفحص يتكرّر الموديل نفسه في الصفّ');
    });
  });

  group('الفصل بالنزول للأسفل لا بالفاصلة', () {
    test('النموذجان يستعملان تقسيم الأسطر', () {
      expect(ui.contains('splitModelLines(models.text)'), isTrue);
      expect(ui.contains("split(RegExp(r'[,"), isFalse,
          reason: 'بقاء تقسيم بالفاصلة يعيد المشكلة');
    });

    test('التعديل يعرض كل موديل في سطر', () {
      expect(ui.contains("r.models.join('\\n')"), isTrue);
    });

    test('حقّ الإدخال يسمح بعدّة أسطر للمالك', () {
      expect(ui.contains('minLines: 3'), isTrue);
    });
  });

  group('الصفّ الجديد يذهب للقسم الحالي', () {
    test('النوع الافتراضي هو القسم المفتوح', () {
      expect(ui.contains('_type ?? CompatTypeMeta.orderedTypes.first'), isTrue,
          reason: 'إضافة صفّ وأنت في «شاشات» يجب أن تُسجَّله شاشةً');
    });
  });
}
