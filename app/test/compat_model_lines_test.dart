import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/core/compat_catalog.dart';

/// فصل الموديلات: سطر لكل موديل، وللفاصلة معنى آخر.
void main() {
  group('فصل الموديلات بالسطر الجديد', () {
    test('كل سطر موديل مستقل', () {
      expect(splitModelLines('A10\nA20\nA30'), ['A10', 'A20', 'A30']);
    });

    test('الفاصلة لا تفصل — تبقى جزءاً من الاسم', () {
      expect(splitModelLines('Redmi Note 8, 8 Pro'),
          ['Redmi Note 8, 8 Pro']);
    });

    test('الفاصلة العربية لا تفصل أيضاً', () {
      expect(splitModelLines('A10، A20'), ['A10، A20']);
    });

    test('الأسطر الفارغة تُسقَط بلا موديل وهمي', () {
      expect(splitModelLines('A10\n\n\nA20\n  \n'), ['A10', 'A20']);
    });

    test('المسافات الزائدة تُقلَّم', () {
      expect(splitModelLines('  A10  \n\tA20\t'), ['A10', 'A20']);
    });

    test('يقطعه محرف فصل السطر في Unicode لا السطر العادي فقط', () {
      expect(splitModelLines('A10\u2028A20\u2029A30'), ['A10', 'A20', 'A30']);
    });

    test('يفصل على \\r وحده (ملف من ويندوز)', () {
      expect(splitModelLines('A10\r\nA20'), ['A10', 'A20']);
    });

    test('المحارف الصفرية الخفيّة لا تصير موديلاً', () {
      expect(splitModelLines('A10\n\u200b\nA20'), ['A10', 'A20']);
    });

    test('النزول للأسفل يعني موديلات أكثر — القائمة تطول بطول النصّ', () {
      final lines = List.generate(25, (i) => 'Model $i').join('\n');
      expect(splitModelLines(lines).length, 25);
    });

    test('نصّ فارغ يعني قائمة فارغة لا عنصراً فارغاً', () {
      expect(splitModelLines(''), isEmpty);
      expect(splitModelLines('\n\n'), isEmpty);
    });
  });
}
