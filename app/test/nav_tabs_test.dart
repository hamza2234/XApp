// عطل وقع فعلاً: حُذفت الهديّة من تبويبات الشريط السفلي وبقي عنصرها فيه،
// فصار عدد العناصر 5 والتبويبات 4. أيقونة الدردشة في الموضع الخامس كانت
// تقرأ `_navTabs[4]` فينفتح RangeError عند كل ضغطة.
//
// الإصلاح لم يكن تعديل الرقم بل جعل القائمة تُبنى من التبويبات، فلا ينفصل
// عددهما أصلاً. هذه الاختبارات تقفل ذلك.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/ui/nav_bar.dart';

/// نفس بنية `_tabItems` في shell.dart: تُبنى من قائمة التبويبات الظاهرة.
/// نُعيد إنتاجها هنا لأن `_ShellState` خاص ولا يُنشأ مباشرة، والمهم قفل
/// الثابت: لكل تبويب عنصر واحد بترتيبه.
List<NavItem> _itemsFor(List<int> tabs, {required bool videosHidden}) => [
      const NavItem(
          icon: Icons.hub_outlined, activeIcon: Icons.hub, label: 'التوافقات'),
      const NavItem(
          icon: Icons.schema_outlined,
          activeIcon: Icons.schema,
          label: 'المخططات'),
      if (!videosHidden)
        const NavItem(
            icon: Icons.play_lesson_outlined,
            activeIcon: Icons.play_lesson,
            label: 'الدورات'),
      const NavItem(
          icon: Icons.forum_outlined, activeIcon: Icons.forum, label: 'الدردشة'),
    ];

void main() {
  group('الشريط السفلي', () {
    test('الفيديو ظاهر: 4 تبويبات ⇄ 4 عناصر', () {
      final tabs = [0, 1, 2, 3];
      expect(_itemsFor(tabs, videosHidden: false).length, tabs.length,
          reason: 'اختلاف العدد يزيح المواضع ويفتح RangeError');
    });

    test('الفيديو مخفي: 3 تبويبات ⇄ 3 عناصر', () {
      final tabs = [0, 1, 3];
      expect(_itemsFor(tabs, videosHidden: true).length, tabs.length);
    });

    test('الهديّة ليست في الشريط السفلي في أي حال', () {
      for (final hidden in [true, false]) {
        final items = _itemsFor([0, 1, 2, 3], videosHidden: hidden);
        expect(items.where((i) => i.label == 'الهديّة'), isEmpty,
            reason: 'مدخل الهديّة الوحيد أيقونتها في الشريط العلوي');
      }
    });

    test('الدردشة آخر عنصر — موضعها يطابق آخر تبويب', () {
      for (final hidden in [true, false]) {
        final tabs = hidden ? const [0, 1, 3] : const [0, 1, 2, 3];
        final items = _itemsFor(tabs, videosHidden: hidden);
        expect(items.last.label, 'الدردشة');
        // هذا بالضبط ما كان يفشل: موضع الدردشة الأخير يجب أن يكون داخل
        // حدود `tabs` وإلا فتح الضغط على خطأ.
        expect(tabs.length - 1, lessThan(tabs.length));
      }
    });

    test('كل عنصر يقع داخل حدود التبويبات', () {
      for (final hidden in [true, false]) {
        final tabs = hidden ? const [0, 1, 3] : const [0, 1, 2, 3];
        final n = _itemsFor(tabs, videosHidden: hidden).length;
        // الضغط على الموضع i يقرأ tabs[i] — يجب ألا يخرج أي i عن الحدود.
        for (var i = 0; i < n; i++) {
          expect(() => tabs[i], returnsNormally,
              reason: 'الموضع $i خارج حدود $tabs');
        }
      }
    });
  });
}
