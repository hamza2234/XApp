import 'package:flutter/services.dart';

/// حجب التقاط الشاشة على مستوى النظام.
///
/// يرفع `FLAG_SECURE` في نافذة أندرويد، فيرفض النظام نفسه لقطات الشاشة
/// وتسجيل الفيديو: تظهر اللقطة سوداء ويسجّل مسجّل الشاشة إطاراً أسود. وهذا
/// هو الفرق عن أي حجب داخل الواجهة — الأخير يُلتفّ عليه بتصوير الجهاز من
/// الخارج أو بأداة تلتقط الإطارات المرسومة.
///
/// القيد الذي يجب فهمه: الحجب يخص نافذة التطبيق، فلا يمنع تصوير الشاشة
/// بكاميرا خارجية. لا توجد تقنية تمنع ذلك، والحماية الفعلية تبقى في أن
/// الملفات مشفّرة ولا تُخدَم بلا جلسة صحيحة.
class SecureScreen {
  SecureScreen._();

  static const _channel = MethodChannel('x_app/device');

  /// عدّاد لا قيمة منطقية: أكثر من شاشة قد تطلب الحجب في الوقت نفسه
  /// (عارض مخطط نبّت عليه إشعار فيُفتح آخر). إطفاء الحجب عند إغلاق إحداهما
  /// كان يفكّ الحماية عن الأخرى — فالحجب يبقى ما دام عدّاده أكبر من صفر.
  static int _depth = 0;

  static Future<void> on() async {
    _depth++;
    if (_depth == 1) await _apply(true);
  }

  static Future<void> off() async {
    _depth--;
    if (_depth <= 0) {
      _depth = 0;
      await _apply(false);
    }
  }

  /// إطفاء قسري — عند الخروج من الحساب أو قفل التطبيق، حيث لا يضمن
  /// عدّاد عمق صحيح بعد تبديل شاشات مفاجئ.
  static Future<void> reset() async {
    _depth = 0;
    await _apply(false);
  }

  static Future<void> _apply(bool secure) async {
    try {
      await _channel.invokeMethod('setSecure', secure);
    } catch (_) {
      // منصة لا تدعم القناة (اختبارات/سطح المكتب) — لا نُسقط الشاشة.
    }
  }
}
