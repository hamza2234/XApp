import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبار الجوهر في مسار فيديو الدورات: التنزيل والتفكيك يجريان على شكل
/// دفق، وقطع الشبكة لا تسير على حدود البلوكات. لو لم يزحف عدّاد AES-CTR
/// مع كل قطعة لظهر المقطع مفكوكاً صحيحاً حتى أول حدّ قطعة ثم مشوّشاً.
///
/// هذا الاختبار يثبت أن التفكيك بالقطع يعطي نفس بايتات التفكيك الكامل،
/// مهما كان حجم القطعة — بما فيها أحجام لا تقبل القسمة على 16.
void main() {
  final algo = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);

  Future<Uint8List> encrypt(Uint8List plain, SecretKey key, List<int> nonce) async {
    final box = await algo.encrypt(plain, secretKey: key, nonce: nonce);
    return Uint8List.fromList(box.cipherText);
  }

  /// يفكّ التشفير على قطع بالحجم المطلوب — محاكاة لما تفعله التطبيق مع
  /// ما يصلك من الشبكة.
  Future<Uint8List> decryptChunked(
    Uint8List cipher, SecretKey key, List<int> nonce, int chunk,
  ) async {
    final out = <int>[];
    final stream = Stream<List<int>>.fromIterable([
      for (var i = 0; i < cipher.length; i += chunk)
        cipher.sublist(i, min(i + chunk, cipher.length)),
    ]);
    await for (final c in algo.decryptStream(
      stream,
      secretKey: key,
      nonce: nonce,
      mac: Mac.empty,
    )) {
      out.addAll(c);
    }
    return Uint8List.fromList(out);
  }

  test('التفكيك بالقطع يطابق التفكيك الكامل مهما كان حجم القطعة', () async {
    final key = await algo.newSecretKey();
    final nonce = List<int>.generate(16, (i) => (i * 7 + 3) & 0xff);

    // حجم ليس مضاعفاً لـ16 كي لا تصادف حدود القطع حدود البلوكات.
    final plain = Uint8List.fromList(
        List<int>.generate(100003, (i) => (i * 31 + 11) & 0xff));
    final cipher = await encrypt(plain, key, nonce);

    // الأحجام الصغيرة والمتوسطة والكبيرة، وأحجام غير قابلة للقسمة على 16.
    for (final chunk in [1, 7, 15, 16, 17, 64, 1024, 65536, 100003]) {
      final got = await decryptChunked(cipher, key, nonce, chunk);
      expect(got.length, plain.length, reason: 'حجم القطعة $chunk');
      expect(got, equals(plain), reason: 'حجم القطعة $chunk');
    }
  });

  test('قطعة واحدة تحمل الرسالة كاملة تفكّ صحيحة', () async {
    final key = await algo.newSecretKey();
    final nonce = List<int>.generate(16, (i) => i);
    final plain = Uint8List.fromList(
        List<int>.generate(64, (i) => (i * 5 + 2) & 0xff));
    final cipher = await encrypt(plain, key, nonce);
    final got = await decryptChunked(cipher, key, nonce, plain.length);
    expect(got, equals(plain));
  });

  test('القطع الفارغة بين البيانات لا تفسد التفكيك', () async {
    final key = await algo.newSecretKey();
    final nonce = List<int>.generate(16, (i) => i + 1);
    final plain = Uint8List.fromList(
        List<int>.generate(5000, (i) => (i * 13 + 5) & 0xff));
    final cipher = await encrypt(plain, key, nonce);

    // قطع فارغة كما قد يفعلها محوّل شبكة يقسّم على حدود غير منتظمة.
    final out = <int>[];
    await for (final c in algo.decryptStream(
      Stream<List<int>>.fromIterable([
        cipher.sublist(0, 100),
        <int>[],
        cipher.sublist(100, 101),
        <int>[],
        cipher.sublist(101),
      ]),
      secretKey: key,
      nonce: nonce,
      mac: Mac.empty,
    )) {
      out.addAll(c);
    }
    expect(Uint8List.fromList(out), equals(plain));
  });
}

