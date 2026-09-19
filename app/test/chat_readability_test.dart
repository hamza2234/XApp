import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as fc;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as fcu;
import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/core/models.dart' as app;
import 'package:x_app/ui/chat_bridge.dart';
import 'package:x_app/ui/chat_theme_x.dart';
import 'package:x_app/ui/theme.dart';

/// يحرس الدرس الذي كلّفنا إصداراً معطوباً: واجهة الدردشة يجب أن تكون
/// **مقروءة** في الوضعين، لا زجاجاً يمحو المحتوى.
///
/// الخطأ السابق لم يُلتقط لأن أحداً لم يقس التباين؛ الاختبارات كانت تتحقق من
/// وجود وسم `BackdropFilter` (أي أن الزجاج موجود!) لا من أن النص يُرى.
void main() {
  app.ChatMessage msg({
    required String id,
    required String body,
    required bool mine,
    String kind = 'text',
  }) =>
      app.ChatMessage(
        id: id,
        roomId: 'r1',
        kind: kind,
        body: body,
        mediaUrl: '',
        mediaMime: '',
        mediaSize: 0,
        at: DateTime(2026, 1, 1, 12).millisecondsSinceEpoch,
        mine: mine,
        author: app.ChatAuthor(
          id: mine ? '' : 'device-2',
          nickname: mine ? 'أنا' : 'عضو',
        ),
      );

  Widget host({required bool light}) {
    XTheme.apply(light); // يبدّل ألوان XTheme كاملة
    return MaterialApp(
      locale: const Locale('ar'),
      home: XChatScope(
        child: Builder(
          builder: (context) => Scaffold(
            body: fcu.Chat(
              currentUserId: ChatBridge.myUserId,
              resolveUser: (_) async => null,
              theme: xChatTheme(context),
              chatController: fc.InMemoryChatController(
                messages: [
                  ChatBridge().toCore(
                      msg(id: '1', body: 'رسالة من غيري', mine: false),
                      isMine: false),
                ],
              ),
              // النصوص الافتراضية في الحزمة إنجليزية، ونمرّر البدائل العربية
              // صراحةً: v2 أسقطت الترجمة العربية التي كانت في v1.
              builders: fc.Builders(
                composerBuilder: (context) => const fcu.Composer(
                  hintText: 'اكتب رسالة',
                ),
                emptyChatListBuilder: (context) =>
                    const fcu.EmptyChatList(text: 'لا رسائل بعد'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  for (final light in [true, false]) {
    testWidgets(
        light ? 'الوضع الفاتح: نصّ الدردشة مقروء' : 'الوضع الداكن: نصّ الدردشة مقروء',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(light: light));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(fcu.Chat), findsOneWidget);

      // نصّ الرسالة ظاهر فعلاً — لا محجوباً بخلفية بلون النص.
      expect(find.text('رسالة من غيري'), findsOneWidget);

      // تباين الخلفية: خلفية الدردشة وحاوية الفقاعة يجب أن تختلفا عن لون
      // النص، وإلا وقعنا في «أبيض على أبيض».
      final chatTheme = xChatTheme(
        tester.element(find.byType(fcu.Chat)),
      );
      final c = chatTheme.colors;
      _expectContrast(c.onSurface, c.surface, 'نصّ على خلفية الدردشة');
      _expectContrast(c.onSurface, c.surfaceContainer, 'نصّ على فقاعة');
      _expectContrast(c.onPrimary, c.primary, 'نصّ رسالتي على البرتقالي');
    });
  }
}

/// النسبة الدنيا المقروءة. `WCAG AA` يشترط 4.5 للنصّ العادي؛ نتّسع قليلاً
/// (3.0) لأن الفقاعات نصوص كبيرة نسبياً، لكن نمنع قطعاً التشابه التام الذي
/// جعل الواجهة السابقة غير مرئية.
void _expectContrast(Color fg, Color bg, String where) {
  final l1 = _lum(fg), l2 = _lum(bg);
  final hi = l1 > l2 ? l1 : l2, lo = l1 > l2 ? l2 : l1;
  final ratio = (hi + 0.05) / (lo + 0.05);
  expect(ratio, greaterThan(3.0),
      reason: '$where: تباين ${ratio.toStringAsFixed(2)} منخفض — النص سيختفي');
}

/// إضاءة نسبية حسب WCAG.
double _lum(Color c) {
  double ch(double v) {
    v = v;
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}
