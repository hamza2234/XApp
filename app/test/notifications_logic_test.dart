import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/core/models.dart' as app;
import 'package:x_app/core/notifications.dart';

/// فحوص منطق الإشعارات: الوجهة، وقرار الإظهار، وسطر المعاينة.
///
/// لا منصة ولا مكوّنات نظام هنا. ما نفحصه هو المنطق الصافي الذي يقرّر أيّ
/// إشعار يظهر وأين يفتح — وهو بالضبط ما يُفسد بصمت لو انحرف.
void main() {
  group('وجهة الإشعار', () {
    test('الدوران: الترميز ثم الفك يعيد الوجهة نفسها', () {
      final chat = NotificationTarget.chat('r7');
      final back = NotificationTarget.decode(chat.encode());
      expect(back, isNotNull);
      expect(back!.kind, 'chat');
      expect(back.roomId, 'r7');

      final ads = NotificationTarget.ads;
      final backAds = NotificationTarget.decode(ads.encode());
      expect(backAds, isNotNull);
      expect(backAds!.kind, 'ad');
      expect(backAds.roomId, isEmpty);
    });

    test('الحمولة الفارغة أو المفقودة تُرفض بلا انهيار', () {
      expect(NotificationTarget.decode(null), isNull);
      expect(NotificationTarget.decode(''), isNull);
      expect(NotificationTarget.decode('   '), isNull);
    });

    test('نصّ ليس JSON يُرفض بلا انهيار', () {
      // إشعار من نسخة قديمة أو من تطبيق آخر قد يحمل أي شيء.
      expect(NotificationTarget.decode('not-json'), isNull);
      expect(NotificationTarget.decode('[1,2,3]'), isNull);
      expect(NotificationTarget.decode('"a string"'), isNull);
    });

    test('نوع وجهة غير معروف يُرفض بدل فتح شاشة عشوائية', () {
      expect(NotificationTarget.decode('{"k":"ads"}'), isNull);
      expect(NotificationTarget.decode('{"k":"settings"}'), isNull);
    });

    test('قسم بلا معرّف يُرفض — لا وجهة صالحة بلا قسم', () {
      expect(NotificationTarget.decode('{"k":"chat"}'), isNull);
      expect(NotificationTarget.decode('{"k":"chat","r":""}'), isNull);
    });
  });

  group('بوّابة إشعار الدردشة', () {
    // الحالة الأساسية: دردشة مفعّلة، إشعارات مفتوحة، رسالة غيري، في قسم آخر.
    bool gate({
      bool chatEnabled = true,
      bool notifyEnabled = true,
      bool mine = false,
      String roomId = 'r1',
      String openRoomId = '',
    }) =>
        ChatNotifyGate.shouldNotify(
          chatEnabled: chatEnabled,
          notifyEnabled: notifyEnabled,
          mine: mine,
          roomId: roomId,
          openRoomId: openRoomId,
        );

    test('ينبّه في الحالة الطبيعية', () {
      expect(gate(), isTrue);
    });

    test('لا ينبّه عن رسالتي أنا', () {
      expect(gate(mine: true), isFalse);
    });

    test('لا ينبّه عن القسم المفتوح أمام المستخدم', () {
      expect(gate(openRoomId: 'r1'), isFalse);
    });

    test('ينبّه عن قسم آخر وإن كان غيره مفتوحاً', () {
      expect(gate(roomId: 'r2', openRoomId: 'r1'), isTrue);
    });

    test('لا ينبّه حين تكون الدردشة موقوفة', () {
      expect(gate(chatEnabled: false), isFalse);
    });

    test('لا ينبّه حين يكتم المستخدم الإشعارات', () {
      expect(gate(notifyEnabled: false), isFalse);
    });

    test('قسم بلا معرّف لا يُنبَّه عنه', () {
      expect(gate(roomId: ''), isFalse);
    });

    test('الكتم يغلب فتح قسم آخر (لا إشعار في أي حال)', () {
      expect(gate(notifyEnabled: false, roomId: 'r2', openRoomId: 'r1'), isFalse);
    });
  });

  group('سطر معاينة الرسالة', () {
    app.ChatMessage msg({
      String kind = 'text',
      String body = '',
      int seconds = 0,
    }) =>
        app.ChatMessage(
          id: 'm1',
          roomId: 'r1',
          kind: kind,
          body: body,
          mediaUrl: '',
          mediaMime: '',
          mediaSize: 0,
          at: 0,
          seconds: seconds,
          mine: false,
          author: const app.ChatAuthor(id: 'u2', nickname: 'أحمد'),
        );

    test('النصّ يُعرض كما هو', () {
      expect(msg(body: 'السلام عليكم').preview, 'السلام عليكم');
    });

    test('الفراغ المحيط يُنظَّف', () {
      expect(msg(body: '  مرحبا  ').preview, 'مرحبا');
    });

    test('النصّ الطويل يُقصّ بعلامة قطع', () {
      final long = 'ا' * 400;
      final p = msg(body: long).preview;
      expect(p.length, lessThanOrEqualTo(121));
      expect(p.endsWith('…'), isTrue);
    });

    test('صورة بلا نصّ توصف ولا تظهر فراغاً', () {
      expect(msg(kind: 'image').preview, 'أرسل صورة');
    });

    test('مقطع فيديو بلا نصّ يوصف', () {
      expect(msg(kind: 'video').preview, 'أرسل مقطع فيديو');
    });

    test('رسالة صوتية تذكر مدتها إن عُرفت', () {
      expect(msg(kind: 'audio', seconds: 12).preview, contains('12'));
      expect(msg(kind: 'audio').preview, 'أرسل رسالة صوتية');
    });

    test('نوع مجهول بلا نصّ يُعيد فراغاً بدل كلمة مخترعة', () {
      expect(msg(kind: 'sticker').preview, isEmpty);
    });

    test('نصّ مصحوب بوسيط يغلب النصّ على الوصف', () {
      expect(msg(kind: 'image', body: 'شوف هذي').preview, 'شوف هذي');
    });
  });
}