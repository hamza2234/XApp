import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as fc;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as fchat;
import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/core/models.dart' as app;
import 'package:x_app/ui/chat_bridge.dart';
import 'package:x_app/ui/chat_theme_x.dart';

/// فحوص على مسار الدردشة الحقيقي: الجسر والثيم ورسم الحزمة.
///
/// لا واجهة وهمية هنا. نبني `Chat` الحقيقية فوق محرّك حقيقي برسائل حقيقية،
/// ونفحص ما يراه المستخدم: نصّ الرسالة، واتجاه فقاعتنا، وإعادة التزامن التي
/// تتكرّر عندنا في كل دورة استطلاع.
app.ChatMessage _msg({
  required String id,
  String kind = 'text',
  String body = 'مرحبا',
  bool mine = false,
  String authorId = 'u2',
  String nickname = 'أحمد',
  String mediaUrl = '',
}) =>
    app.ChatMessage(
      id: id,
      roomId: 'r1',
      kind: kind,
      body: body,
      mediaUrl: mediaUrl,
      mediaMime: '',
      mediaSize: 0,
      at: 1700000000000,
      mine: mine,
      author: app.ChatAuthor(id: authorId, nickname: nickname, avatarUrl: ''),
    );

/// يبني الحزمة الحقيقية في شجرة حقيقية بثيم التطبيق واتجاه RTL.
Future<void> _pumpChat(
  WidgetTester tester,
  fc.InMemoryChatController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (ctx) => XChatScope(
            child: fchat.Chat(
              currentUserId: ChatBridge.myUserId,
              chatController: controller,
              theme: xChatTheme(ctx),
              resolveUser: (id) async => fc.User(id: id, name: 'اسم'),
              onMessageSend: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('الرسالة النصّية تظهر بنصّها في الواجهة', (tester) async {
    final c = fc.InMemoryChatController()
      ..setMessages([
        ChatBridge().toCore(_msg(id: 'm1', body: 'سعر الشاشة ٣٥٠'), isMine: false),
      ]);

    await _pumpChat(tester, c);

    expect(find.text('سعر الشاشة ٣٥٠'), findsOneWidget);
  });

  testWidgets('فقاعة الطرف الآخر في جهة البداية ورسالتي في جهة النهاية',
      (tester) async {
    final c = fc.InMemoryChatController()
      ..setMessages([
        ChatBridge().toCore(_msg(id: 'a', body: 'منه'), isMine: false),
        ChatBridge().toCore(_msg(id: 'b', body: 'مني', mine: true), isMine: true),
      ]);

    await _pumpChat(tester, c);

    final mine = tester.getCenter(find.text('مني'));
    final theirs = tester.getCenter(find.text('منه'));
    // في RTL البداية يمين والنهاية يسار، ورسالتي يجب أن تكون في النهاية.
    expect(mine.dx, lessThan(theirs.dx),
        reason: 'رسالتي يجب أن تكون في جهة النهاية، والطرف الآخر في البداية');
  });

  testWidgets('النصّ يُرسم بلون مقروء على فقاعة رسالتي', (tester) async {
    final c = fc.InMemoryChatController()
      ..setMessages([
        ChatBridge().toCore(_msg(id: 'b', body: 'ردّي', mine: true), isMine: true),
      ]);

    await _pumpChat(tester, c);

    // `Chat` ترسم فقاعة افتراضية بلون الثيم: `onPrimary` الغامق. الأبيض هنا
    // يعني تبايناً 2.6 على البرتقالي — وهو ما كان غير مقروء.
    final text = tester.widget<Text>(find.text('ردّي'));
    expect(text.style?.color, isNot(Colors.white),
        reason: 'لا نصّ أبيض على برتقالي فاتح');
  });

  test('إعادة التزامن بنفس المعرّفات لا تنهار — وهي ما يقع كل دورة استطلاع',
      () async {
    final c = fc.InMemoryChatController();
    final bridge = ChatBridge();
    final core = [
      bridge.toCore(_msg(id: 'x1', body: 'أ'), isMine: false),
      bridge.toCore(_msg(id: 'x2', body: 'ب'), isMine: false),
    ];

    await c.setMessages(core);
    // الاستطلاع يعيد بناء القائمة كاملة كل بضع ثوان؛ التكرار يجب ألا يفشل.
    await c.setMessages(core);
    expect(c.messages.length, 2);
  });

  test('الجسر يحفظ كائن التطبيق ويعيده بلا فقدان', () {
    final core = ChatBridge()
        .toCore(_msg(id: 'k1', body: 'نصّ', nickname: 'سعيد', authorId: 'u9'),
            isMine: false);

    final back = ChatBridge.unwrap(core);
    expect(back, isNotNull);
    expect(back!.id, 'k1');
    expect(back.body, 'نصّ');
    expect(back.author.nickname, 'سعيد');
  });

  test('رسالتي تحمل معرّفاً ثابتاً حتى لا تنتقل الفقاعة بين الجهتين', () {
    final bridge = ChatBridge();
    final mine = bridge.toCore(_msg(id: 'm', mine: true, authorId: ''), isMine: true);
    expect(mine.authorId, ChatBridge.myUserId);
    // الطرف الآخر بلا معرّف لا يساوي معرّفنا أبداً، وإلا صارت رسالته رسالتنا.
    final anon = bridge.toCore(_msg(id: 'a', authorId: ''), isMine: false);
    expect(anon.authorId, isNot(ChatBridge.myUserId));
  });

  test('الرسالة النظامية تُبنى كنظام لا كفقاعة', () {
    final core = ChatBridge()
        .toCore(_msg(id: 's', kind: 'system', body: 'انضم فلان'), isMine: false);
    expect(core, isA<fc.SystemMessage>());
  });

  test('الوسائط تحمل مساراً مطلقاً لأن الخادم يرسل مساراً نسبياً', () {
    final core = ChatBridge().toCore(
      _msg(id: 'i1', kind: 'image', mediaUrl: '/v1/media/abc'),
      isMine: false,
    );
    expect(core, isA<fc.ImageMessage>());
    expect((core as fc.ImageMessage).source.startsWith('http'), isTrue,
        reason: 'الرابط النسبي يجب أن يُسبق بأصل الخادم وإلا فشل التحميل');
  });
}