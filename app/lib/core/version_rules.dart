/// قواعد حقول لوحة المالك التي يُساء فهمها بسهولة.
///
/// مفصولة عن الواجهة كي تُفحص بلا شبكة ولا مكوّنات. وهي تحرس عطلاً حقيقياً
/// وقع: المالك كتب اسم الإصدار «1.4.0» في حقل «أدنى إصدار»، و`int.tryParse`
/// أعادت null فحُفظ 1 بصمت، فظنّ أنه أوقف إصداراً وهو لم يفعل.
library;

/// خطأ حقل «أدنى إصدار»، أو null إن كان صالحاً.
///
/// الحقل رقم بناء لا اسم إصدار: المقارنة على الخادم `v < minVersion` بين
/// أعداد صحيحة، فاسم مثل «2.0.0» لا معنى له هناك.
String? minVersionError(String raw) {
  if (int.tryParse(raw.trim()) == null) {
    return 'أدنى إصدار غير صالح — اكتب رقم البناء (مثال: 6) لا اسم الإصدار (2.0.0)';
  }
  return null;
}

/// خطأ الحجب بلا مخرج، أو null إن كان الحفظ سليماً.
///
/// حجب نسخة بلا رسالة يترك المستخدم أمام شاشة يظنها عطلاً، وبلا رابط لا يجد
/// ما يفعله فيبقى محجوباً. الشرط لا يمنع المالك من عمله بل يمنعه من حجب
/// الناس بلا أن يقول لهم شيئاً.
String? blockWithoutExitError({
  required int minVersion,
  required bool hasBlockedVersions,
  required String updateMessage,
  required String updateUrl,
}) {
  final blocksSomebody = minVersion > 1 || hasBlockedVersions;
  if (!blocksSomebody) return null;
  if (updateMessage.trim().isEmpty) {
    return 'اكتب رسالة التحديث أولاً — المستخدم يجب أن يعرف سبب القفل';
  }
  if (updateUrl.trim().isEmpty) {
    return 'ضع رابط التحديث أولاً — بلا رابط لا يستطيع المستخدم فكّ القفل';
  }
  // الرابط يجب أن يكون قابلاً للتحميل فعلاً. رابط من نسخة قديمة (اسم حزمة
  // قديم، مسار محذوف) يجعل المستخدم يرى «حدّث التطبيق» ولا يجد ما يحمّله —
  // وهو أسوأ من عدم الحجب أصلاً.
  final u = updateUrl.trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    return 'رابط التحديث يجب أن يبدأ بـ http أو https';
  }
  return null;
}
