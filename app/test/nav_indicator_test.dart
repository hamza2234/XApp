import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/ui/nav_bar.dart';

/// موضع الخط البرتقالي في شريط التنقل.
///
/// التطبيق عربي (RTL)، فالعمود 0 يقع على اليمين لا اليسار. إن لم يُراعَ
/// الاتجاه استقر الخط تحت التبويب المعاكس — كان يظهر تحت «الدردشة» عند
/// الضغط على «التوافقات». هذه الدالة تحرس ذلك.
void main() {
  const width = 360.0;
  const count = 3;
  final cell = width / count;

  test('في RTL يقف المؤشّر تحت التبويب المضغوط لا المعاكس', () {
    // التبويب الأول (التوافقات) يمين الشاشة.
    expect(
      navIndicatorCenterX(width, count, 0, TextDirection.rtl),
      closeTo(width - cell * .5, 0.01),
    );
    // الوسط يبقى الوسط في الاتجاهين.
    expect(
      navIndicatorCenterX(width, count, 1, TextDirection.rtl),
      closeTo(width / 2, 0.01),
    );
    // التبويب الأخير (الدردشة) يسار الشاشة.
    expect(
      navIndicatorCenterX(width, count, 2, TextDirection.rtl),
      closeTo(cell * .5, 0.01),
    );
  });

  test('في LTR يبقى الترتيب الطبيعي', () {
    expect(navIndicatorCenterX(width, count, 0, TextDirection.ltr),
        closeTo(cell * .5, 0.01));
    expect(navIndicatorCenterX(width, count, 2, TextDirection.ltr),
        closeTo(width - cell * .5, 0.01));
  });

  test('لا يقسم على صفر مع شريط بلا عناصر', () {
    expect(navIndicatorCenterX(width, 0, 0, TextDirection.rtl), 0);
  });

  testWidgets('شريط التنقل يُبنى ويستجيب للنقر', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) => AnimatedNavBar(
              index: 0,
              onSelect: (_) {},
              items: const [
                NavItem(
                    icon: Icons.hub_outlined,
                    activeIcon: Icons.hub,
                    label: 'التوافقات'),
                NavItem(
                    icon: Icons.schema_outlined,
                    activeIcon: Icons.schema,
                    label: 'المخططات'),
                NavItem(
                    icon: Icons.forum_outlined,
                    activeIcon: Icons.forum,
                    label: 'الدردشة'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('التوافقات'), findsOneWidget);
    expect(find.text('الدردشة'), findsOneWidget);

    // النقر يُبلّغ عن الفهرس الصحيح.
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AnimatedNavBar(
            index: 0,
            onSelect: (i) => tapped = i,
            items: const [
              NavItem(
                  icon: Icons.hub_outlined,
                  activeIcon: Icons.hub,
                  label: 'التوافقات'),
              NavItem(
                  icon: Icons.schema_outlined,
                  activeIcon: Icons.schema,
                  label: 'المخططات'),
              NavItem(
                  icon: Icons.forum_outlined,
                  activeIcon: Icons.forum,
                  label: 'الدردشة'),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('المخططات'));
    expect(tapped, 1, reason: 'النقر على العنصر الثاني يجب أن يعطي الفهرس 1');
  });

  // الطلب كان «معنان زجاج فقط»: أُزيلت الذرّات والمدارات، ثم بقي ظلّ
  // توهّج حول الأيقونة النشطة. هذا الاختبار يمنع رجوعه: أي ظل على الأيقونة
  // يعني هالة متوهّجة حول التبويب النشط.
  testWidgets('لا توهّج حول الأيقونة النشطة', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: AnimatedNavBar(
            index: 0,
            onSelect: (_) {},
            items: const [
              NavItem(
                  icon: Icons.hub_outlined,
                  activeIcon: Icons.hub,
                  label: 'التوافقات'),
              NavItem(
                  icon: Icons.schema_outlined,
                  activeIcon: Icons.schema,
                  label: 'المخططات'),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // الأيقونة النشطة هي أيقونة العنصر المحدَّد في الموضع 0.
    final icons = tester
        .widgetList<Icon>(find.byType(Icon))
        .toList();
    expect(icons, isNotEmpty);
    for (final icon in icons) {
      expect(icon.shadows, isNull,
          reason: 'أيقونات الشريط يجب أن تكون بلا ظل توهّج');
    }
  });
}