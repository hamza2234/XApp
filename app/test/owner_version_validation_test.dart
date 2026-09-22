// فحص قواعد حقول لوحة المالك — العطل الذي كلّف المالك ثقة تطبيقه.
//
// كان المالك يكتب اسم الإصدار «1.4.0» في حقل «أدنى إصدار» فيُحفظ 1 بصمت:
// `int.tryParse('1.4.0')` تُعيد null و`?? 1` تبتلع الفشل. النتيجة أن
// «إيقاف إصدار» لم يحدث قط، ولم يعلم المالك أن شيئاً فشل.
import 'package:flutter_test/flutter_test.dart';
import 'package:x_app/core/version_rules.dart';

void main() {
  group('حقل أدنى إصدار', () {
    test('اسم الإصدار يُرفض بدل أن يُحفظ 1 بصمت', () {
      // هذا بالضبط ما فعله المالك فأوقف الحماية عن قصد.
      expect(minVersionError('1.4.0'), isNotNull,
          reason: '«1.4.0» اسم إصدار لا رقم بناء — الحفظ الصامت هو العطل الأصلي');
      expect(minVersionError('2.0.0'), isNotNull);
      expect(minVersionError('v2'), isNotNull);
    });

    test('الفراغ وغير الرقمي يُرفضان', () {
      expect(minVersionError(''), isNotNull);
      expect(minVersionError('   '), isNotNull);
      expect(minVersionError('abc'), isNotNull);
    });

    test('رقم البناء الصحيح يُقبل', () {
      expect(minVersionError('6'), isNull);
      expect(minVersionError(' 20 '), isNull,
          reason: 'المسافات الطرفية تُقلَّم قبل التحليل');
      expect(minVersionError('1'), isNull);
    });
  });

  group('الحجب بلا مخرج', () {
    test('رفع الحدّ الأدنى بلا رسالة ورابط يُرفض', () {
      expect(
        blockWithoutExitError(
            minVersion: 6,
            hasBlockedVersions: false,
            updateMessage: '',
            updateUrl: ''),
        isNotNull,
        reason: 'قفل بلا نصّ يبدو للمستخدم عطلاً',
      );
      // رسالة بلا رابط: المستخدم يفهم لكن لا يجد ما يفعله.
      expect(
        blockWithoutExitError(
            minVersion: 6,
            hasBlockedVersions: false,
            updateMessage: 'حدّث التطبيق',
            updateUrl: ''),
        isNotNull,
        reason: 'بلا رابط يبقى المستخدم محجوباً بلا مخرج',
      );
    });

    test('قائمة إصدارات موقوفة وحدها تكفي لإلزام الرسالة', () {
      // لا يرفع الحدّ لكنه يوقف إصداراً بعينه — نفس أثر الحجب.
      expect(
        blockWithoutExitError(
            minVersion: 1,
            hasBlockedVersions: true,
            updateMessage: '',
            updateUrl: 'https://x/apk'),
        isNotNull);
    });

    test('رسالة ورابط معاً يمرّان', () {
      expect(
        blockWithoutExitError(
            minVersion: 6,
            hasBlockedVersions: false,
            updateMessage: 'حدّث التطبيق للمتابعة',
            updateUrl: 'https://x/apk'),
        isNull);
    });

    test('لا حجب أحد: لا نشترط رسالة ولا رابطاً', () {
      // من لم يوقف أحداً لا يُطالَب بشيء، وإلا صار الشرط عائقاً لا حماية.
      expect(
        blockWithoutExitError(
            minVersion: 1,
            hasBlockedVersions: false,
            updateMessage: '',
            updateUrl: ''),
        isNull);
    });
  });
}
