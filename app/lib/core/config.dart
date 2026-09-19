/// إعدادات تطبيق X
/// ملاحظة أمنية: لا يوجد هنا أي مفتاح Cloudflare أو قاعدة بيانات —
/// كل الوصول يمر عبر Worker الخاص بنا فقط.
library;

import 'dart:convert';

const String kApiBase = 'https://x-app-api.www-hmzhh123-com.workers.dev';

/// إصدار التطبيق — يُرسَل في كل طلب وتتحكم به لوحة المالك.
const int kAppVersion = 2;
const String kAppVersionName = '1.8.0';
const String kAppName = 'MAPX';

/// سر توقيع الطلبات — مشوّش (XOR + base64 + تقسيم) ليصعّب استخراجه
/// من الحزمة. الحماية الحقيقية في الـ Worker: توقيع + JWT + ربط الجهاز.
class SigKey {
  static const List<int> _x = [
    0x5a, 0x12, 0x4f, 0x77, 0x03, 0x69, 0x2d, 0x41,
  ];
  static const List<String> _p = [
    'aSEuQjZQHA==', 'eGh0dhU1WEl0bCA=', 'eBI7WB0=', 'ImhxeU8yXE4n',
    'O3d2FDQKSCRrdytBYg==', 'XxklbSR+', 'QzMPHnE7Kyw=', 'EjRbS3A=',
  ];

  static String get secret {
    final enc = _p.map(base64Decode).expand((e) => e).toList();
    final out =
        List<int>.generate(enc.length, (i) => enc[i] ^ _x[i % _x.length]);
    return String.fromCharCodes(out);
  }
}

/// مفتاح فك تشفير ملفات المخططات — مشوّش بنفس الطريقة.
/// ملف مسروق من الشبكة يظهر كبايتات مشفرة لا تفتح إلا هنا.
class FileKey {
  static const List<int> _x = SigKey._x;
  static const List<String> _p = [
    'bXZ9RGBZGXQ5', 'InYTZ1Ed', 'cW0ndxU3URUiOHR9', 'ETJbGndocw==',
    'ehE2Cx0ibXN7EzY=', 'Cxl0PyIrRzM=', 'XxglPiQ=', 'fUFnWBkg',
  ];

  static List<int> get bytes {
    final enc = _p.map(base64Decode).expand((e) => e).toList();
    final hex = String.fromCharCodes(
        List<int>.generate(enc.length, (i) => enc[i] ^ _x[i % _x.length]));
    return List<int>.generate(
        hex.length ~/ 2, (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16));
  }
}
