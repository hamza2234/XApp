import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/ui/brand_logo.dart';

/// كل شركة يجب أن تُعرض بشعارها الخاص — لا شعار شركة أخرى.
/// هذا الاختبار يمنع تكرار ما حدث سابقاً حين كانت REDMI وBLACK SHARK
/// تعرضان شعار شاومي نفسه.
void main() {
  const names = [
    'MI', 'REDMI', 'BLACK SHARK', 'POCO', 'INFINIX', 'HUAWEI',
    'HONOR', 'SAMSUNG', 'REALME', 'OPPO', 'VIVO', 'ITEL',
    'NOKIA', 'SONY', 'MOTOROLA', 'GOOGLE', 'ONEPLUS', 'iPhone',
  ];

  group('حل مفاتيح شعارات الشركات', () {
    test('REDMI وBLACK SHARK لهما مفتاحان مستقلان لا شاومي', () {
      expect(BrandLogo.assetKeyFor('REDMI'), 'redmi');
      expect(BrandLogo.assetKeyFor('BLACK SHARK'), 'blackshark');
      expect(BrandLogo.assetKeyFor('MI'), 'xiaomi');
      expect(BrandLogo.assetKeyFor('01xiaomi'), 'xiaomi');
      expect(BrandLogo.assetKeyFor('02realme'), 'realme');
    });

    test('لا شركتان مختلفتان تتقاسمان ملف شعار واحد', () {
      final keys = names.map(BrandLogo.assetKeyFor).toList();
      expect(keys.toSet().length, names.length,
          reason: 'شعار مكرر بين شركتين: $keys');
    });

    test('كل شركة لها ملف شعار موجود فعلاً على القرص', () {
      for (final n in names) {
        final key = BrandLogo.assetKeyFor(n);
        expect(BrandLogo.hasAsset(n), isTrue, reason: '$n بلا ملف شعار');
        final f = File('assets/brands/$key.jpg');
        expect(f.existsSync(), isTrue, reason: 'ملف مفقود: ${f.path}');
        expect(f.lengthSync(), greaterThan(1000), reason: 'ملف صغير جداً: $key');
      }
    });
  });
}