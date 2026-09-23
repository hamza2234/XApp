/// توقيع الطلبات بمفتاح خاص بكل تثبيت — بلا أي سرّ مضمّن في الحزمة.
///
/// لماذا تغيّر هذا: كان التطبيق يحمل سرّاً واحداً مشتركاً بين كل النسخ،
/// مشوّشاً بـXOR ومفتاح التشويش في الملف نفسه. استخراجه ثوانٍ، وبعدها
/// يستطيع من استخرجه توقيع أي طلب من أي جهاز إلى الأبد — ولا سبيل لإبطال
/// ما سرّبه إلا تحديث كل المستخدمين.
///
/// البديل: يولّد كل تثبيت زوج مفاتيح Ed25519 محلياً عند أول تشغيل. المفتاح
/// الخاص يُغلَّف بمفتاح داخل Android Keystore ولا يغادر الجهاز، والمفتاح
/// العام وحده يُسجَّل على الخادم مرة واحدة. النتيجة:
///   * لا سرّ في الحزمة — فحص الحزمة لا يمنح أحداً شيئاً.
///   * تسريب مفتاح تثبيت لا يفيد على غيره: الخادم يربط المفتاح بتثبيته.
///   * الإبطال لكل تثبيت على حدة، لا للجميع.
///
/// التوقيع يغطّي الطريقة والمسار وطابعاً زمنياً وnonce وبصمة الجسم، فيصير
/// الطلب مربوطاً بمحتواه: اعتراض طلب صالح وتبديل جسمه يُبطل التوقيع.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';

import 'config.dart';
import 'store.dart';

class RequestSigner {
  RequestSigner(this._store);

  final Store _store;
  static final _ed = Ed25519();
  static final _rnd = Random.secure();

  /// يضمن وجود زوج المفاتيح ويسجّل العام على الخادم مرة واحدة.
  ///
  /// `enroll` نداء غير موقّع (لا يمكن توقيع طلب بمفتاح لم يُسجَّل بعد)،
  /// ويُستدعى فقط إن لم يكن المفتاح العام قد أُرسل من قبل.
  Future<void> ensureKey(
      Future<void> Function(String installId, String publicKey) enroll) async {
    await _store.warmSignKey();
    final made = await _store.ensureSignKey(() async {
      final kp = await _ed.newKeyPair();
      final seed = await kp.extractPrivateKeyBytes();
      final pub = await kp.extractPublicKey();
      return (seed: base64Encode(seed), publicKey: hex(pub.bytes));
    });
    if (!_store.installKeySent) {
      await enroll(_store.installId, made.publicKey);
      await _store.markInstallKeySent();
    }
  }

  /// أقصى حجم يدخل في بصمة الجسم — مطابق لـ`MAX_BODY_HASH` في الخادم.
  /// ما فوقه يُوقَّع بالمسار وحده، فلا يُحمَّل نصّ التوقيع بحجم الفيديو.
  static const _maxBodyHash = 256 * 1024;

  /// يبني ترويسات موقّعة لطلب بعينه.
  ///
  /// بصمة الجسم تُحسب من البايتات المرسلة نفسها، فلا بدّ من تمرير الجسم
  /// هنا. غيابه يعني بصمة فارغة — وهذا مقبول للطلبات بلا جسم.
  Future<Map<String, String>> headers(
    String method,
    String pathWithQuery, {
    List<int>? body,
  }) async {
    final seedB64 = _store.signSeed;
    if (seedB64 == null) {
      // لا مفتاح بعد: الإقلاع لم يستدعِ ensureKey. نُفشل بصمت بدل إرسال
      // طلب غير موقّع، فيُعاد الإقلاع ويُبنى المفتاح.
      throw StateError('signing key not ready');
    }
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _newNonce();
    // نفس قاعدة الخادم حرفياً: الجسم الفارغ — أو ما يتجاوز الحد — بصمته
    // فارغة. أي اختلاف هنا يعني رفضاً على كل رفع كبير (مقاطع الفيديو)،
    // لأن الخادم يحسب '' بينما التطبيق يحسب بصمة.
    final bodyHash = (body == null || body.isEmpty || body.length > _maxBodyHash)
        ? ''
        : hex(c.sha256.convert(body).bytes);
    final installId = _store.installId;
    final payload = '$installId|$ts|$nonce|$method|$pathWithQuery|$bodyHash';

    final kp = await _ed.newKeyPairFromSeed(base64Decode(seedB64));
    final sig = await _ed.sign(utf8.encode(payload), keyPair: kp);
    final dev = _store.deviceId;
    final fp = _store.fingerprint;

    return {
      'x-install-id': installId,
      'x-device-id': dev,
      if (fp.isNotEmpty) 'x-device-fp': fp,
      'x-app-ts': ts,
      'x-app-nonce': nonce,
      'x-app-sig': hex(sig.bytes),
      'x-app-version': '$kAppVersion',
      'User-Agent': 'X-App/$kAppVersionName',
    };
  }

  /// nonce عشوائي لكل طلب: يمنع إعادة إرسال الطلب نفسه مرتين.
  ///
  /// `Random.secure` لا `Random`: مولّد غير آمن قد يعيد القيمة نفسها على
  /// جهازين، فيصطدم الـnonce ويُرفض طلب صحيح.
  static String _newNonce() =>
      hex(List<int>.generate(16, (_) => _rnd.nextInt(256)));
}

String hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
