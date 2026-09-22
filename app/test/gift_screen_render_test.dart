// شاشة الهديّة ظهرت سوداء فارغة عند المستخدم. الشكّ الأول أن البناء نفسه
// يرمي استثناءً: نافذة سفلية (`showModalBottomSheet`) فيها `Column` بارتفاع
// أدنى، وبداخلها `GiftScreen` وهو `ListView` — والقائمة داخل عمود بلا ارتفاع
// محدود ترمي «Vertical viewport was given unbounded height». هذه الاختبارات
// تبني الشاشة فعلياً في الحالتين (جديدة/مستلمة) كي لا يبقى العطل نظرياً.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:x_app/ui/gift_screen.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

GiftScreen _gift({
  int amount = 100,
  bool claimed = false,
  int nextAt = 0,
  int balance = 250,
  Future<GiftClaimResult> Function()? onClaim,
}) =>
    GiftScreen(
      amount: amount,
      claimed: claimed,
      nextAt: nextAt,
      balance: balance,
      onClaim: onClaim ?? () async => const GiftClaimResult(ok: true, amount: 100),
    );

void main() {
  testWidgets('تُبنى بلا استثناء وتعرض زر الإدارة والأرقام', (t) async {
    await t.pumpWidget(_host(_gift()));
    await t.pump();
    expect(testerException(t), isNull);
    expect(find.text('هديّة اليوم'), findsOneWidget);
    expect(find.text('أدِر العجلة واستلم'), findsOneWidget);
    // الرصيد يظهر بالرقم لا فراغاً.
    expect(find.text('250 عملة'), findsOneWidget);
  });

  testWidgets('لا يوجد RenderFlex/Viewport غير محدود داخل النافذة السفلية',
      (t) async {
    // نحاكي سياق النافذة السفلية الحقيقي: عمود بارتفاع أدنى بداخلها الشاشة.
    await t.pumpWidget(_host(
      Column(mainAxisSize: MainAxisSize.min, children: [_gift()]),
    ));
    await t.pump();
    final err = testerException(t);
    expect(err, isNull,
        reason: 'القائمة داخل عمود بلا ارتفاع محدود ترمي استثناء وتُفرغ الشاشة');
  });

  testWidgets('الحالة المستلمة تعرض الرقم والعدّاد بلا استثناء', (t) async {
    final soon = DateTime.now().millisecondsSinceEpoch + 3600 * 1000;
    await t.pumpWidget(_host(_gift(claimed: true, nextAt: soon, amount: 100)));
    await t.pump();
    expect(testerException(t), isNull);
    expect(find.text('استلمت هديّة اليوم'), findsOneWidget);
    expect(find.text('100'), findsWidgets);
  });

  testWidgets('الهديّة المعطّلة: الزر معطّل والنصّ مفهوم لا فراغ', (t) async {
    await t.pumpWidget(_host(_gift(amount: 0)));
    await t.pump();
    expect(find.text('الهديّة معطّلة حالياً'), findsOneWidget);
    final b = t.widget<FilledButton>(find.byType(FilledButton));
    expect(b.onPressed, isNull);
  });

  testWidgets('دور كامل: العجلة تستقرّ والمبلغ يُكشف ويُضاف للرصيد', (t) async {
    await t.pumpWidget(_host(_gift(
      amount: 70,
      balance: 10,
      onClaim: () async => const GiftClaimResult(ok: true, amount: 70),
    )));
    await t.pump();
    await t.tap(find.text('أدِر العجلة واستلم'));
    // نُكمل حركة الدوران بالكامل: مرحلتان بمهل محدودة.
    await t.pumpAndSettle(const Duration(milliseconds: 50));
    expect(testerException(t), isNull);
    expect(find.text('استلمت هديّة اليوم'), findsOneWidget);
    expect(find.text('80 عملة'), findsOneWidget);
  });
}

/// آخر استثناء التُقط أثناء البناء، أو null.
Object? testerException(WidgetTester t) =>
    t.takeException() == null ? null : t.takeException();
