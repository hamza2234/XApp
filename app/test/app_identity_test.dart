import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// PhoneX: الثيم الداكن افتراضي، والاسم الحالي، وبصمة التطبيق.
void main() {
  test('الثيم الداكن هو الافتراضي في الكود', () {
    final t = File('lib/ui/theme.dart').readAsStringSync();
    // القيم الابتدائية داكنة: هذا هو الافتراضي المطلوب للتطبيق.
    expect(t.contains('static Color bg = _dBg;'), isTrue);
    expect(t.contains('static bool isLight = false;'), isTrue);
    // اختيار المستخدم المحفوظ يتقدّم على الافتراضي.
    expect(t.contains("p.getBool('light_theme') ?? false"), isTrue);
  });

  test('اسم التطبيق PhoneX في الإعدادات والبيان', () {
    final c = File('lib/core/config.dart').readAsStringSync();
    expect(c.contains("const String kAppName = 'PhoneX';"), isTrue);
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m.contains('android:label="PhoneX"'), isTrue);
    // صلاحية الإنترنت لازمة لفتح التطبيق بلا رسالة «تعذر الاتصال».
    expect(m.contains('android.permission.INTERNET'), isTrue);
  });

  test('معرّف الحزمة لم يتغيّر كي تُثبَّت التحديثات فوق النسخة القائمة', () {
    final g = File('android/app/build.gradle.kts').readAsStringSync();
    expect(g.contains('com.xapp.x_app'), isTrue);
  });
}