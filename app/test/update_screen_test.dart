// فحص شاشة القفل: هل يفهم المستخدم منها ما يفعله؟
//
// طلب صريح من المالك: عند القفل يجب أن يظهر رابط تحديث أو وصف واضح مفهوم.
// الشاشة السابقة كانت تعرض نصّاً عاماً وزراً يظهر فقط إن وُجد رابط، فمن
// ضبط رسالة بلا رابط ترك مستخدميه أمام شاشة مسدودة لا مخرج منها.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_app/core/app_config.dart';
import 'package:x_app/ui/update_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('رابط التحديث يظهر كزر واضح حين يضبطه المالك', (t) async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.instance.load();

    await t.pumpWidget(_wrap(const UpdateScreen(
      message: 'أوقفنا هذه النسخة — حدّث للتكملة',
      url: 'https://example.com/app.apk',
    )));

    // رسالة المالك تُعرض بنصّها لا بنص عام.
    expect(find.text('أوقفنا هذه النسخة — حدّث للتكملة'), findsOneWidget);
    // الزر موجود فعلاً — القفل بلا زر لا مخرج منه.
    expect(find.text('تحديث الآن'), findsOneWidget);
  });

  testWidgets('بلا رابط: وصف مفهوم وقناة تواصل بدل شاشة مسدودة', (t) async {
    SharedPreferences.setMockInitialValues({'cfg_telegram': 'https://t.me/x'});
    await AppConfig.instance.load();

    await t.pumpWidget(_wrap(const UpdateScreen(
      message: 'هذه النسخة لم تعد مدعومة',
    )));

    expect(find.text('هذه النسخة لم تعد مدعومة'), findsOneWidget);
    // لا زر تحديث بلا رابط — لا نعرض زراً معطّلاً.
    expect(find.text('تحديث الآن'), findsNothing);
    // لكن المستخدم يفهم ما يفعله، ويجد من يسأله.
    expect(
      find.textContaining('حدّث التطبيق من مصدر'),
      findsOneWidget,
      reason: 'بلا رابط يجب أن يبقى وصف واضح يشرح ما يفعله المستخدم',
    );
    expect(find.text('تواصل مع الإدارة'), findsOneWidget);
  });

  testWidgets('بلا رابط وبلا تيليجرام: الوصف وحده يكفي', (t) async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.instance.load();

    await t.pumpWidget(_wrap(const UpdateScreen(message: 'قفل إجباري')));

    expect(find.text('قفل إجباري'), findsOneWidget);
    expect(find.textContaining('حدّث التطبيق من مصدر'), findsOneWidget);
    // لا قناة تواصل مضبوطة، فلا نعرض زراً يقود إلى رابط فارغ.
    expect(find.text('تواصل مع الإدارة'), findsNothing);
  });

  testWidgets('بلا رسالة من المالك: نص افتراضي مفهوم لا فراغ', (t) async {
    SharedPreferences.setMockInitialValues({});
    await AppConfig.instance.load();

    await t.pumpWidget(_wrap(const UpdateScreen()));

    expect(find.text('تحديث مطلوب'), findsOneWidget);
    expect(find.textContaining('حدّث التطبيق للمتابعة'), findsOneWidget);
  });
}
