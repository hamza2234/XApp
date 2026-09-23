// اختبار تكامل حقيقي لقفل الإصدارات مقابل الخادم المنشور.
//
// العطل الذي يحرسه هذا الملف: المالك يوقف إصداراً من لوحته، والتطبيق على
// جهاز آخر يعمل كأن شيئاً لم يحدث. سببه أن `/v1/bootstrap` لم يكن يُرسل
// `blockedVersions` أصلاً، وكان يخضع للقفل نفسه فيصل القفل بلا رسالته.
// الاختبار يمرّ على المسار الحقيقي الموقّع لا على محاكاة.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:x_app/core/api.dart';
import 'package:x_app/core/config.dart';
import 'package:x_app/core/models.dart';
import 'package:x_app/core/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Flutter يحجب الشبكة في الاختبارات؛ هذا اختبار تكامل فنُعيد العميل الحقيقي.
  HttpOverrides.global = null;

  test('bootstrap يحمل حقول القفل التي يقرأها التطبيق', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.init();
    final api = Api(store);
    // التوقيع إلزامي على /v1/*، والمفتاح يُبنى ويسجَّل قبل أي طلب موقّع.
    await api.initSigningKey();

    final boot = await api.bootstrap();
    final raw = boot['settings'] as Map;
    final s = XSettings.fromJson(raw.cast<String, dynamic>());

    // الحقول موجودة فعلاً في الردّ — لا يكفي أن النموذج يقرأها، فغيابها
    // من الخادم كان يجعل «إيقاف إصدار» بلا أثر على الإطلاق.
    expect(raw.containsKey('blockedVersions'), isTrue,
        reason: 'بدون هذه القائمة لا يمكن إيقاف إصدار محدد أبداً');
    expect(raw.containsKey('appLocked'), isTrue,
        reason: 'بدونها لا يعرف التطبيق أن المالك أوقفه للصيانة');
    expect(raw.containsKey('lockMessage'), isTrue,
        reason: 'بدونها يظهر نص عام لا كلام المالك');
    expect(s.blockedVersions, isA<List<int>>());
  });

  test('bootstrap يحمل نص ورابط شاشة التحديث', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.init();
    final api = Api(store);
    // التوقيع إلزامي على /v1/*؛ بلا مفتاح مسجَّل يُرفض الطلب قبل أن يُقرأ.
    await api.initSigningKey();

    final boot = await api.bootstrap();
    final u = boot['update'];
    expect(u, isA<Map>(),
        reason: 'شاشة التحديث تُبنى من هذا الحقل في splash.dart');
    expect((u as Map).containsKey('message'), isTrue);
    expect(u.containsKey('url'), isTrue);
  });

  test('رقم البناء المُعلن يطابق رقم البناء في pubspec', () {
    // ملاحظة كي لا يُظنّ عطلاً: نسخ --split-per-abi تحمل versionCode مُزاحاً
    // (arm64=2020، armeabi=1020) لأن Flutter يضيف إزاحة لكل معالج. الخادم لا
    // يقرأه أصلاً — يقرأ ترويسة `x-app-version` المبنية على kAppVersion،
    // فالمقارنة تجري على 20 دائماً في كل النسخ.
    // كان kAppVersion = 5 بينما pubspec يقول 20، فما يراه المالك في
    // «التثبيتات حسب الإصدار» لا يطابق ما يقارنه الخادم فعلاً.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*[\d.]+\+(\d+)', multiLine: true)
        .firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec.yaml يجب أن يحمل رقم بناء');
    expect(kAppVersion, int.parse(m!.group(1)!),
        reason: 'kAppVersion يجب أن يساوي رقم البناء في pubspec');
  });

  test('إصدار قديم يُقفل فعلاً بـ426 ويحمل رسالة التحديث', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.init();
    // المفتاح يُبنى ويسجَّل قبل أي توقيع يدوي في _signedPost.
    await Api(store).initSigningKey();

    // نُوقّع الطلب بأنفسنا برقم بناء قديم. هذا هو المسار الذي كان معطلاً:
    // المالك يرفع الحد الأدنى فيظل التطبيق القديم يعمل كأن شيئاً لم يحدث.
    final old = await _signedPost(store, '/v1/auth/guest', build: 1);
    expect(old.status, 426,
        reason: 'إصدار أقدم من الحد الأدنى يجب أن يُقفل لا أن يمرّ');
    expect(old.body['update'], isA<Map>(),
        reason: 'القفل بلا رسالة تحديث يترك المستخدم بلا مخرج');
    expect((old.body['update'] as Map).containsKey('message'), isTrue);

    // والنسخة الحالية تمرّ من المسار نفسه — القفل لا يطال إلا القديم.
    // لو طالها القفل لتعطّل التطبيق على مستخدميه كلهم، وهو أخطر من العطل نفسه.
    final now = await _signedPost(store, '/v1/auth/guest');
    expect(now.status, 200, reason: 'النسخة الحالية يجب ألا تُقفل');
  });

  test('النسخة الحالية تمرّ من البوابة ولا تُقفل نفسها', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await Store.init();
    final api = Api(store);
    await api.initSigningKey();

    // أي قفل للنسخة الحالية يعني تعطيل التطبيق على مستخدميه كلهم، وهو
    // أخطر من العطل الأصلي.
    final boot = await api.bootstrap();
    final s = XSettings.fromJson(
        (boot['settings'] as Map).cast<String, dynamic>());
    expect(s.blockedVersions.contains(kAppVersion), isFalse,
        reason: 'النسخة الحالية لا يجوز أن تكون في قائمة الإيقاف');
    expect(kAppVersion >= s.minVersion, isTrue,
        reason: 'النسخة الحالية يجب ألا تكون أقدم من الحد الأدنى');
  });
}

/// طلب موقّع يدوياً كي نتحكّم برقم البناء المُعلن — وهو ما تحكم به البوابة.
///
/// يُحاكي بالضبط ما يفعله `RequestSigner.headers` لكن برقم بناء مُمرَّر:
/// Ed25519 بمفتاح خاص بهذا التثبيت على
/// `installId|ts|nonce|method|path|bodyHash`. لا سرّ مشترك هنا — كان الاختبار
/// يوقّع بـHMAC بسرّ مضمّن، وذلك السرّ أُزيل من التطبيق، فبقاء الاختبار عليه
/// كان يعيد إدخال ما أُخرج.
Future<({int status, Map<String, dynamic> body})> _signedPost(
    Store store, String path, {int? build}) async {
  final client = HttpClient();
  final ed = Ed25519();
  final rnd = Random.secure();
  final ts = DateTime.now().millisecondsSinceEpoch.toString();
  final nonce = List<int>.generate(16, (_) => rnd.nextInt(256))
      .map((e) => e.toRadixString(16).padLeft(2, '0'))
      .join();
  final installId = store.installId;
  final reqBody = utf8.encode('{}');
  final bodyHash = Sha256().hash(reqBody).then(
      (h) => h.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join());
  final payload =
      '$installId|$ts|$nonce|POST|$path|${await bodyHash}';

  final seed = base64Decode(store.signSeed ?? '');
  final kp = await ed.newKeyPairFromSeed(seed);
  final sig = await ed.sign(utf8.encode(payload), keyPair: kp);

  final dev = store.deviceId;
  final fp = store.fingerprint;
  final req = await client.postUrl(Uri.parse('$kApiBase$path'));
  req.headers.set('x-install-id', installId);
  req.headers.set('x-device-id', dev);
  if (fp.isNotEmpty) req.headers.set('x-device-fp', fp);
  req.headers.set('x-app-ts', ts);
  req.headers.set('x-app-nonce', nonce);
  req.headers.set('x-app-sig', sig.bytes
      .map((e) => e.toRadixString(16).padLeft(2, '0'))
      .join());
  req.headers.set('x-app-version', '${build ?? kAppVersion}');
  req.headers.set('User-Agent', 'X-App/${kAppVersionName}');
  req.headers.set('Content-Type', 'application/json');
  // التوقيع يشمل بصمة الجسم؛ بلا كتابته يُوقَّع sha256('{}') بينما يُرسل
  // جسم فارغ، فيُرفض الطلب بـ«توقيع غير صالح» (403) قبل أن تصل البوابة
  // إلى فحص الإصدار — أي أن الاختبار كان يقيس توقيعاً لا وصولاً.
  req.write('{}');
  final res = await req.close();
  final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
  client.close();
  Map<String, dynamic> body = const {};
  try {
    body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  } catch (_) {
    // 426 و200 كلاهما JSON؛ الفشل هنا يعني ردّاً غير متوقع فنتركه فارغاً
    // ليظهر في فشل التوقّع لا كاستثناء ترميز يحجب السبب.
  }
  return (status: res.statusCode, body: body);
}
