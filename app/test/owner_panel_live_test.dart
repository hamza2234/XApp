// اختبار تكامل حقيقي للوحة المالك: يفتح جلسة مالك فعلية ويفكّ كل ردّ مشفّر.
//
// الغرض: إثبات أن كل أقسام اللوحة تُفكّ فعلاً. كان `OwnerCrypto.open` يمرّر
// الوسم الملحق كأنه جزء من النص المشفّر، فيفشل التحقق في كل ردّ ويظهر
// «تعذر فك رد اللوحة» في كل قسم. هذا الاختبار يمنع رجوع العطل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_app/core/api.dart';
import 'package:x_app/core/app_config.dart';
import 'package:x_app/core/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter يحجب الشبكة في الاختبارات؛ هذا اختبار تكامل حقيقي.
  HttpOverrides.global = null;

  final user = Platform.environment['XAPP_OWNER_USER'] ?? '';
  final pass = Platform.environment['XAPP_OWNER_PASS'] ?? '';
  if (user.isEmpty || pass.isEmpty) {
    test('لوحة المالك: كل الأقسام تُفك', () {
      markTestSkipped('عيّن XAPP_OWNER_USER و XAPP_OWNER_PASS');
    });
    return;
  }

  test('لوحة المالك: كل الأقسام تُفكّ وتُقرأ', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.init();
    await AppConfig.instance.load();
    final api = Api(store);

    final login = await api.ownerLogin(user, pass);
    expect(login['token'], isA<String>(), reason: 'دخول المالك يجب أن ينجح');
    await store.setOwnerToken(login['token'] as String);
    expect(store.hasOwnerSession, isTrue);

    // كل قسم يعيد ردّاً مشفّراً. فشل أي واحد منه يعيد 401
    // «تعذر فك رد اللوحة» — وهو العطل الذي أُصلح.
    final gets = <String>[
      'overview',
      'settings',
      'users',
      'bans',
      'requests',
      'wallets',
      'security',
      'announcements',
      'chat/actions',
      'chat/messages',
    ];

    final failures = <String>[];
    for (final key in gets) {
      try {
        final m = await api.ownerGet('/v1/owner/$key');
        // الرد المفكوك لا يحمل enc: لو حملها فالفك لم يجرِ.
        if (m.containsKey('enc')) failures.add('$key: لم يُفكّ');
      } on ApiException catch (ex) {
        failures.add('$key: ${ex.status} ${ex.message}');
      } catch (ex) {
        failures.add('$key: $ex');
      }
    }

    expect(failures, isEmpty, reason: 'أقسام فشلت: ${failures.join(' | ')}');
  });
}