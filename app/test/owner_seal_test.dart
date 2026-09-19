import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/core/api.dart';

/// عيّنة ثابتة من `ownerSeal` في العامل: AES-GCM بمفتاح مشتق من الرمز،
/// والوسم ملحق بآخر النص المشفّر — وهو ما يفكّه `OwnerCrypto.open`.
///
/// العيّنة مولّدة بـ WebCrypto (نفس ما يستخدمه العامل) حتى لا تختبر
/// الدالة ضد نفسها. لا تحتوي أي سرّ حقيقي.
const _token = 'fixture-owner-token';
const _sealed =
    'BwcHBwcHBwcHBwcH.pg2HED0q3cxwGW8SVdUbZHsQ0AOXXtiSRRBbBQJ6tnn_yzUYErRtZsse'
    'KPgwZiR35ucrDi47ZzD-ycmo2JxswF2XotVALyX4wOxlDqZUQ69pokaAKbHv7W9s9-9JP9'
    '8z1j0';

void main() {
  test('يفكّ رد لوحة المالك الحقيقي ويرفض الوسم المعدّل', () async {
    final clear = await OwnerCrypto.open(_token, _sealed);
    expect(clear.containsKey('settings'), isTrue,
        reason: 'الرد المفكوك يجب أن يحمل إعدادات اللوحة');
    expect(clear['users'], isA<List>());
    expect((clear['settings'] as Map)['telegramLink'], 'https://t.me/Mapx4');

    // وسم مصادقة معدّل يجب أن يُرفض لا أن يُقبل.
    final dot = _sealed.indexOf('.');
    final body =
        base64Url.decode(base64Url.normalize(_sealed.substring(dot + 1)));
    body[body.length - 1] ^= 0xff;
    final forged = '${_sealed.substring(0, dot + 1)}${base64Url.encode(body)}';
    await expectLater(
      OwnerCrypto.open(_token, forged),
      throwsA(isA<Exception>()),
      reason: 'وسم GCM معدّل يجب أن يفشل التحقق',
    );
  });

  test('يرفض رمزاً مختلفاً عن الذي شُفّر به الرد', () async {
    await expectLater(
      OwnerCrypto.open('token-آخر', _sealed),
      throwsA(isA<Exception>()),
    );
  });
}