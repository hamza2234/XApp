// العجلة شكل لا قرعة: القيمة قرار الخادم، والقطاعات تُرسم بأرقام كثيرة
// مختلفة، والمؤشّر يستقرّ على القطاع الذي يحمل قيمة اليوم. الخطأ الذي يجب
// ألا يقع: أن يقف السهم على قطاع لا يطابق المبلغ المعروض، فيظهر تناقض
// صارخ بين شكل العجلة والمبلغ المكتوب.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// نفس `_labels` في gift_screen.dart.
const _labels = <int>[
  5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 100, 150, 200, 250,
];

int get _winIndex => _labels.length ~/ 2;

/// نفس `_restFor`: زاوية القطاع `i` بحيث يقف وسطه تحت المؤشّر بعد `a`.
double restFor(double a, int i, int n) {
  final sweep = 2 * math.pi / n;
  final mid = i * sweep + sweep / 2;
  var d = ((-math.pi / 2 - mid) - a) % (2 * math.pi);
  if (d < 0) d += 2 * math.pi;
  return a + d + 2 * 2 * math.pi;
}

/// الزاوية الظاهرة للقطاع `i` عند الزاوية الكلية `a` — منفصلة عن الكسور.
double midOf(int i, int n, double a) => i * (2 * math.pi / n) + (math.pi / n) + a;

void main() {
  group('هندسة عجلة الهديّة', () {
    test('يستقرّ المؤشّر على وسط القطاع الفائز', () {
      for (final a in [0.0, 0.7, 3.1, 12.9, -2.0, 100.0]) {
        final rest = restFor(a, _winIndex, _labels.length);
        // المؤشّر أعلى العجلة عند -π/2. بعد الدوران، وسط القطاع الفائز
        // يجب أن يوافق هذا الموضع (بفارق دورات كاملة).
        final delta = (midOf(_winIndex, _labels.length, rest) - (-math.pi / 2)) %
            (2 * math.pi);
        final off = math.min(delta, 2 * math.pi - delta);
        expect(off, lessThan(1e-9),
            reason: 'من $a: السهم لا يقع على وسط القطاع الفائز');
      }
    });

    test('الدوران دائماً للأمام ولا يقلّ عن دورتين', () {
      for (final a in [0.0, 5.0, 40.0]) {
        final rest = restFor(a, _winIndex, _labels.length);
        expect(rest - a, greaterThan(2 * 2 * math.pi - 1e-9),
            reason: 'حركة قصيرة أو ارتداد للخلف تبدو غير طبيعية');
      }
    });

    test('القيمة الفعلية تُوضع على قطاع الاستقرار وحده', () {
      // نحاكي `_segLabels`: القيمة تحلّ محلّ رقم واحد، وبقية الأرقام تبقى.
      final amount = 37;
      final shown = List<int>.from(_labels);
      shown[_winIndex] = amount;
      expect(shown[_winIndex], amount);
      expect(shown.where((v) => v == amount).length, 1,
          reason: 'تكرار القيمة يكشف القطاع من بعيد');
      // الرقم الذي حلّت القيمة محلّه يختفي، فمجموع الأرقام يبقى متمايزاً
      // والعدد ثابت: العجلة تظل بأرقام كثيرة مختلفة.
      expect(shown.toSet().length, shown.length);
      expect(shown.length, _labels.length);
      expect(shown.contains(_labels[_winIndex]), isFalse);
    });

    test('أرقام القطاعات كلها موجبة وقيمها متمايزة في الأصل', () {
      expect(_labels.every((v) => v > 0), isTrue);
      expect(_labels.toSet().length, _labels.length);
      expect(_labels.length, greaterThan(8), reason: 'أرقام كثيرة مطلوبة');
    });
  });
}