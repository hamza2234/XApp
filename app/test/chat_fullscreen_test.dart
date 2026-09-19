import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الدردشة تعمل بملء الشاشة تلقائياً — لا زر تكبير يضغطه المستخدم.
///
/// لماذا فحص الملف المصدري لا شجرة الواجهة؟ لأن شاشة الدردشة تبني رأسها
/// بعد نجاح `chatState()` من الخادم، و`Api` صنف ملموس لا يمكن استبداله
/// بواجهة وهمية في اختبار واجهة. اختبار يبني الشاشة بلا شبكة لا يعرض الرأس
/// أصلاً، فيمرّ عبثاً ويوهم بأنه يحرس شيئاً. فحص الشيفرة المصدّرة يمسك
/// الحقيقة التي تهم: ألا يعود زر ملء الشاشة إلى الملف.
void main() {
  test('لا زر ملء شاشة في الدردشة ولا في الغلاف', () {
    for (final path in ['lib/ui/chat_screen.dart', 'lib/ui/shell.dart']) {
      final src = File(path).readAsStringSync();
      expect(src.contains('Icons.fullscreen'), isFalse,
          reason: '$path: زر ملء الشاشة يجب ألا يعود — الوضع تلقائي');
      expect(src.contains('onHeaderTap'), isFalse,
          reason: '$path: لا مبدّل ملء شاشة بعد اليوم');
    }
  });

  test('الغلاف يرسم الدردشة بملء الشاشة ويحتفظ بمخرج', () {
    final src = File('lib/ui/shell.dart').readAsStringSync();
    // الشريطان مخفيّان حين يكون تبويب الدردشة مفتوحاً.
    expect(src.contains('_chatOpen'), isTrue);
    // ومخرج الرأس يعيد الشريطين.
    expect(src.contains('onExit: _exitChat'), isTrue);
    expect(src.contains('_lastNonChatTab'), isTrue);
  });

  test('الأسطح معتمة لا شبه شفّافة — النص يجب أن يُقرأ', () {
    final src = File('lib/ui/chat_screen.dart').readAsStringSync();
    // الخطأ الذي وقعنا فيه: طبقة بيضاء شبه شفّافة فوق ثيم معتم تُنتج أبيض
    // فوق أبيض في الوضع الفاتح، فيختفي الرأس والكومبوزر. الأسطح هنا معتمة.
    expect(src.contains('BackdropFilter'), isFalse,
        reason: 'لا زجاج فوق ثيم معتم: يمحو المحتوى في الوضع الفاتح');
    expect(src.contains('color: XTheme.surface'), isTrue,
        reason: 'الرأس والكومبوزر بخلفية سطح معتمة مقروءة');
  });
}
