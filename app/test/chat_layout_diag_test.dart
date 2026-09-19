import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as fchat;
import 'package:x_app/core/api.dart';
import 'package:x_app/core/models.dart';
import 'package:x_app/core/store.dart';
import 'package:x_app/ui/chat_screen.dart';
import 'package:x_app/ui/chat_theme_x.dart';
import 'package:x_app/ui/theme.dart';

/// يشغّل شاشة الدردشة الحقيقية ببيانات ثابتة على مقاس هاتف.
///
/// الحاجة: «الشاشة مشوّهة» عطل بصري لم تلتقطه اختبارات التباين السابقة. هنا
/// نركّب الشجرة الحقيقية ونلتقط أخطاء البناء والتخطيط التي تُنتج الشاشة
/// البيضاء وأشرطة التجاوز — وهي ما يسمّيه المستخدم تشويهاً.
class _FakeApi extends Api {
  _FakeApi(super.store);

  @override
  Future<ChatState> chatState() async => ChatState(
        enabled: true,
        welcome: 'أهلاً بك في الدردشة العامة',
        rooms: const [
          ChatRoom(id: 'r1', name: 'القسم العام', icon: 'chat'),
          ChatRoom(id: 'r2', name: 'أخبار MAPX', icon: 'announcement'),
        ],
        myNickname: 'أنا',
        canWrite: true,
        canSendMedia: true,
        notify: true,
        role: 'registered',
      );

  @override
  Future<ChatPage> chatMessages(String room,
          {int since = 0, int before = 0, int limit = 40}) async =>
      ChatPage(
        messages: [
          for (var i = 0; i < 24; i++)
            ChatMessage(
              id: 'm$i',
              roomId: room,
              kind: 'text',
              body: 'رسالة رقم $i — نصّ عربي طبيعي للفحص',
              mediaUrl: '',
              mediaMime: '',
              mediaSize: 0,
              at: 1700000000000 + i * 60000,
              mine: i % 3 == 0,
              author: ChatAuthor(
                id: i % 3 == 0 ? '' : 'dev$i',
                nickname: i % 3 == 0 ? 'أنا' : 'عضو $i',
              ),
            ),
        ],
        members: 12,
        online: 3,
      );

  @override
  Future<Map<String, dynamic>> chatProfile({
    String? nickname,
    String? imageB64,
    bool clearAvatar = false,
    bool? notify,
  }) async =>
      const {};
}

void main() {
  late _FakeApi api;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = _FakeApi(await Store.init());
  });

  Future<void> mount(WidgetTester tester, {required bool light}) async {
    XTheme.apply(light);
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: XTheme.theme(),
      locale: const Locale('ar'),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: XTheme.bg,
          body: ChatScreen(api: api, store: api.store, onExit: () {}),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// يطبّع الخطأ إلى أول سطر مفيد، ويحذف الأكواد اللونية.
  String firstLine(Object e) => e
      .toString()
      .replaceAll(RegExp(r'\x1B\[[0-9;]*m'), '')
      .split('\n')
      .first;

  for (final light in [false, true]) {
    final name = light ? 'فاتح' : 'داكن';

    testWidgets('الوضع $name: لا أخطاء بناء ولا تجاوز مساحة', (tester) async {
      final details = <FlutterErrorDetails>[];
      final prev = FlutterError.onError;
      FlutterError.onError = details.add;
      addTearDown(() => FlutterError.onError = prev);

      await mount(tester, light: light);
      FlutterError.onError = prev;
      while (tester.takeException() != null) {}

      for (final d in details) {
        final info = d.informationCollector?.call().join('\n') ?? '';
        // ignore: avoid_print
        print('#### [$name] ${firstLine(d.exception)}\n$info');
      }

      expect(
        details.map((d) => firstLine(d.exception)).toList(),
        isEmpty,
        reason: 'أخطاء بناء في الوضع $name',
      );
    });

    testWidgets('الوضع $name: الرأس والرسائل والكومبوزر مرسومة', (tester) async {
      final details = <FlutterErrorDetails>[];
      final prev = FlutterError.onError;
      FlutterError.onError = details.add;
      addTearDown(() => FlutterError.onError = prev);

      await mount(tester, light: light);
      FlutterError.onError = prev;
      for (final d in details) {
        final info = d.informationCollector?.call().join('\n') ?? '';
        // ignore: avoid_print
        print('#### [$name] ${firstLine(d.exception)}\n$info\n${d.stack}');
      }
      while (tester.takeException() != null) {}

      expect(find.text('القسم العام'), findsWidgets);
      expect(find.textContaining('رسالة رقم'), findsWidgets);
      expect(find.byType(XChatScope), findsOneWidget);

      // الكومبوزر يجب أن يكون في أسفل الشاشة لا طافياً فوق الرسائل.
      // حزمة `flutter_chat_ui` تبني `EditableText` مباشرة لا `TextField`،
      // فالفحص عليه هو الصحيح.
      expect(find.byType(fchat.Composer), findsOneWidget);
      final composerY = tester.getTopLeft(find.byType(EditableText)).dy;
      final screenH =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      expect(composerY, greaterThan(screenH * 0.6),
          reason: 'حقل الكتابة ليس في أسفل الشاشة');
    });
  }
}