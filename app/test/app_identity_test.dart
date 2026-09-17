import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// MAPX: الثيم الفاتح افتراضي، والاسم الجديد، وبصمة التطبيق.
void main() {
  test('الثيم الفاتح هو الافتراضي في الكود', () {
    final t = File('lib/ui/theme.dart').readAsStringSync();
    // القيم الابتدائية فاتحة حتى لا يظهر وميض داكن عند الإقلاع.
    expect(t.contains('static Color bg = _lBg;'), isTrue);
    expect(t.contains('static bool isLight = true;'), isTrue);
    // اختيار المستخدم المحفوظ يتقدّم على الافتراضي.
    expect(t.contains("p.getBool('light_theme') ?? true"), isTrue);
  });

  test('اسم التطبيق MAPX في الإعدادات والبيان', () {
    final c = File('lib/core/config.dart').readAsStringSync();
    expect(c.contains("const String kAppName = 'MAPX';"), isTrue);
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m.contains('android:label="MAPX"'), isTrue);
    // صلاحية الإنترنت لازمة لفتح التطبيق بلا رسالة «تعذر الاتصال».
    expect(m.contains('android.permission.INTERNET'), isTrue);
  });

  test('معرّف الحزمة لم يتغيّر كي تُثبَّت التحديثات فوق النسخة القائمة', () {
    final g = File('android/app/build.gradle.kts').readAsStringSync();
    expect(g.contains('com.xapp.x_app'), isTrue);
  });
}