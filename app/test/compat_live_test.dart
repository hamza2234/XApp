// اختبار تكامل حقيقي مقابل الخادم المنشور.
// لا محاكاة: يفتح جلسة زائر فعلية ويضرب الشبكة، فيثبت أن مسار التوافقات
// المحصّن منشور فعلاً، وأن الخصم يجري على الخادم، وأن الرفض — إن حدث —
// سببه نفاد الحصة والعملات لا عطل شبكة أو خادم قديم.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_app/core/api.dart';
import 'package:x_app/core/app_config.dart';
import 'package:x_app/core/models.dart';
import 'package:x_app/core/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter يحجب الشبكة في الاختبارات ويُرجع 400 دائماً. هذا اختبار تكامل
  // حقيقي ضد الخادم المنشور، فنُعيد عميل HTTP الحقيقي.
  HttpOverrides.global = null;

  test('مسار التوافقات منشور والخصم على الخادم لا على الجهاز', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.init();
    await AppConfig.instance.load();
    final api = Api(store);
    // نفس ترتيب الإقلاع: المفتاح يُسجَّل قبل أي طلب موقّع، وإلا فشل
    // `guest()` بـ«مفتاح التوقيع غير جاهز» لا لأمر يخص التوافقات.
    await api.initSigningKey();

    // جلسة زائر حقيقية — نفس ما يفعله التطبيق عند الفتح (splash.dart).
    final g = await api.guest();
    await store.setToken(g['token'] as String);
    await store.setUser(g['user'] as Map<String, dynamic>);
    expect(store.isGuest, isTrue, reason: 'يجب أن تكون جلسة الزائر قائمة');

    // 1) استعراض الأنواع: لا خصم، ويثبت أن المسار الجديد منشور — لو كان
    //    الخادم قديماً لعاد 404 وظهرت رسالة «يحتاج تحديثاً». لا خصم هنا لأن
    //    استعلاماً فارغاً لا يسحب بيانات.
    final browse = await api.searchCompatCharged('',
        brand: '01xiaomi.json', type: 'SCREEN');
    expect(browse.records, isEmpty);
    expect(browse.charged, isFalse, reason: 'لا خصم على استعراض الأنواع');
    expect(browse.types, containsAll(['SCREEN', 'BATTERY', 'GLASS']),
        reason: 'الخادم الجديد يعيد الأنواع من نقطة البحث المحصّنة');

    // 2) بحث حقيقي: إما يُخصم من مصدر معروف (حصة مجانية أو عملات)، أو يُرفض
    //    لعدم وجود أي رصيد. لا ثالث: عطل الشبكة أو خادم قديم مرفوض هنا.
    CompatSearchResult? ok;
    ApiException? refused;
    try {
      ok = await api.searchCompatCharged('11',
          brand: '01xiaomi.json', type: 'SCREEN');
    } on ApiException catch (e) {
      refused = e;
    }

    if (ok != null) {
      expect(ok.charged, isTrue, reason: 'بحث جديد يُخصم على الخادم');
      expect(ok.records, isNotEmpty, reason: 'البحث عن موديل موجود يعيد بيانات');
      expect(['free', 'coins'], contains(ok.source),
          reason: 'الخصم من الحصة المجانية أو من العملات');
      // كل سجل يعود بنوعه المطلوب — الفصل حسب النوع يعمل على الخادم.
      for (final r in ok.records) {
        expect((r as Map)['componentType'], 'SCREEN');
      }
    } else {
      expect(refused!.quotaExhausted, isTrue,
          reason: 'إما نجاح بخصم أو رفض لنفاد الحصة والعملات');
      expect(refused.serverOutdated, isFalse,
          reason: 'المسار الجديد منشور — لا رسالة خادم قديم');
    }

    // 3) نوع غير معروف يُرفض — النوع لا يُمرَّر للاستعلام أبداً.
    await expectLater(
      api.searchCompatCharged('11', brand: '01xiaomi.json', type: 'HACK'),
      throwsA(isA<ApiException>()),
    );
  }, timeout: const Timeout(Duration(minutes: 4)));
}