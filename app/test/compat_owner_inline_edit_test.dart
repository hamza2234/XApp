import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_app/core/api.dart';
import 'package:x_app/core/models.dart';
import 'package:x_app/core/store.dart';
import 'package:x_app/ui/compat_brand_screen.dart';

/// شاشة التوافقات: تعديل داخل الصفّ نفسه.
///
/// تُفحص الشاشة كمصدر نصّي لأن بناء الواجهة كاملاً يحتاج شبكةً وجلسة مالك؛
/// والمطلوب هنا حراسة قرارات الواجهة التي طلبها المالك صراحةً.
void main() {
  final src = File('lib/ui/compat_brand_screen.dart');
  late String ui;

  setUpAll(() {
    expect(src.existsSync(), isTrue);
    ui = src.readAsStringSync().replaceAll('\r\n', '\n');
  });

  testWidgets('حفظ وإزالة النص يحدثان الصف دون إعادة البحث', (t) async {
    SharedPreferences.setMockInitialValues({});
    final store = await t.runAsync(() async {
      final s = await Store.init();
      await s.setOwnerToken('local-test-owner');
      return s;
    });
    final api = _InlineApi(store!);
    await t.pumpWidget(MaterialApp(home: CompatBrandScreen(
      api: api, brand: CompatBrand('apple', 'Apple', 'apple.json', 2, 1),
    )));
    await t.pumpAndSettle();
    await t.tap(find.text('شاشات').first);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'iphone');
    await t.pump(const Duration(milliseconds: 650));
    await t.pumpAndSettle();
    expect(api.searches, 1);
    await t.tap(find.text('إضافة نصّ'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'new model\nsecond model');
    api.pending = Completer<void>();
    await t.tap(find.text('إضافة').last);
    await t.pump();
    await t.tap(find.text('إضافة').last);
    await t.pump();
    expect(api.patches, 1);
    api.pending!.complete();
    await t.pumpAndSettle();
    expect(find.text('new model'), findsOneWidget);
    expect(find.text('second model'), findsOneWidget);
    expect(api.searches, 1);
    final chip = find.ancestor(of: find.text('new model'), matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: chip, matching: find.byIcon(Icons.close_rounded)));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'تأكيد'));
    await t.pumpAndSettle();
    expect(find.text('new model'), findsNothing);
    expect(find.text('second model'), findsOneWidget);
    expect(api.saved['compatibleModels'], ['iphone 11', 'second model']);
    api.failure = ApiException(503, 'تعذر الحفظ');
    final second = find.ancestor(of: find.text('second model'), matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: second, matching: find.byIcon(Icons.close_rounded)));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'تأكيد'));
    await t.pumpAndSettle();
    expect(find.text('second model'), findsOneWidget);
    expect(find.text('تعذر الحفظ'), findsOneWidget);
    expect(api.searches, 1);
    expect(t.takeException(), isNull);
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
      expect(fn.contains('last ? null'), isTrue,
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

class _InlineApi extends Api {
  _InlineApi(super.store);
  int searches = 0;
  int patches = 0;
  Completer<void>? pending;
  ApiException? failure;
  Map<String, dynamic> saved = {
    'id': 'row1', 'componentType': 'SCREEN',
    'compatibleModels': ['iphone 11'], 'subCategory': {'name': 'LCD'},
  };

  @override
  Future<CompatOpenResult> openCompat(String? brand) async =>
      const CompatOpenResult(source: 'owner');

  @override
  Future<CompatSearchResult> searchCompatCharged(String q,
      {String? brand, String? type}) async {
    searches++;
    return CompatSearchResult(records: [saved], types: ['SCREEN']);
  }

  @override
  Future<Map<String, dynamic>> ownerCompatPatch({required String brand,
      required String id, required Map<String, dynamic> fields}) async {
    patches++;
    if (pending != null) await pending!.future;
    if (failure != null) throw failure!;
    saved = {...saved, ...fields};
    return {'ok': true, 'record': saved};
  }
}
