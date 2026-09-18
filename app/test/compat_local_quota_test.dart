import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_app/core/store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('عدّاد بحوث التوافقات اليومي', () {
    test('يبدأ من صفر ولا يستهلك قبل البحث', () async {
      final s = await Store.init();
      expect(s.compatUsedToday(), 0);
    });

    test('يخصم واحداً لكل بحث ويحفظ المتبقّي', () async {
      final s = await Store.init();
      expect(await s.recordCompatSearch(3), 2);
      expect(await s.recordCompatSearch(3), 1);
      expect(await s.recordCompatSearch(3), 0);
      expect(s.compatUsedToday(), 3);
    });

    test('لا يعطي متبقياً سالباً عند تجاوز الحد', () async {
      final s = await Store.init();
      for (var i = 0; i < 3; i++) {
        await s.recordCompatSearch(3);
      }
      expect(await s.recordCompatSearch(3), 0);
      expect(s.compatUsedToday(), 4);
    });

    test('حد صفري يعني لا بحوث مجانية', () async {
      final s = await Store.init();
      expect(await s.recordCompatSearch(0), 0);
    });

    test('العدّاد يستمر بعد مثيل جديد — لا يُصفَّر بإعادة الفتح', () async {
      final a = await Store.init();
      await a.recordCompatSearch(3);
      final b = await Store.init();
      expect(b.compatUsedToday(), 1);
      expect(await b.recordCompatSearch(3), 1);
    });

    test('عدّاد يوم سابق لا يُحسب على اليوم الحالي', () async {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final key = '${yesterday.year}-'
          '${yesterday.month.toString().padLeft(2, '0')}-'
          '${yesterday.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        'x_compat_day': key,
        'x_compat_used': 9,
      });
      final s = await Store.init();
      expect(s.compatUsedToday(), 0,
          reason: 'عدّاد الأمس يجب ألا يُحجب يومٌ جديد');
      expect(await s.recordCompatSearch(3), 2);
    });
  });
}
