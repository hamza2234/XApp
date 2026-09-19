# XApp — ملاحظات العمل

تطبيق Flutter (عميل) + Cloudflare Worker (خادم). التطبيق يقرأ من Worker خارجي
عبر اتصال موقّع بـ HMAC. لا نكتب في أي مورد مشترك مع تطبيقات أخرى.

## بناء APK

```bash
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/workspace/tools/android-sdk
export ANDROID_SDK_ROOT=/workspace/tools/android-sdk
export PATH=/workspace/tools/flutter/bin:$PATH
cd app
flutter build apk --release                                    # 76MB لكل المعالجات
flutter build apk --release --target-platform android-arm64 --split-per-abi  # 27MB
```

الناتج: `app/build/app/outputs/flutter-apk/`.

### التوقيع

المستودع يدعم keystore إصدار عبر `app/android/key.properties` (مستثنى في
`.gitignore`). المفتاح الدائم الموجود:

- `app/android/xapp-release.jks` (نسخة احتياطية في `/workspace/keys/`)
- alias: `xapp` · sha256: `032f8c38b7ff886fe5d55a1ce1a0342dc3b0f64e0826bdb09369697df34ae697`

البيئة تُعاد تهيئتها دوريًا فتفقد `~/.android/debug.keystore` وقد يفقد `/usr/lib/jvm`
أيضاً. بدون `key.properties` يُستخدم مفتاح debug فيتغيّر التوقيع ويرفض أندرويد
التحديث فوق النسخة القديمة. لذلك استخدم المفتاح الدائم دائماً.

### متطلبات البيئة بعد إعادة التهيئة

```bash
apt-get update && apt-get install -y openjdk-21-jdk-headless
```

## نشر نسخة للتنزيل

```bash
cp app/build/app/outputs/flutter-apk/app-release.apk       /workspace/dist/X-app-vX.Y.Z.apk
cp app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk /workspace/dist/X-app-vX.Y.Z-arm64.apk
cd /workspace/dist && sha256sum *.apk | tee SHA256.txt
# حدّث الروابط والبصمات في index.html
pgrep -f "http.server 12000" || (cd /workspace/dist && setsid nohup python3 -m http.server 12000 --bind 0.0.0.0 > server.log 2>&1 &)
```

الرابط العام: `https://work-1-uqpzekbyhjvrxjks.prod-runtime.all-hands.dev/`

## الفحص

```bash
cd app && flutter analyze lib          # يجب: 0 errors / 0 warnings
BT=/workspace/tools/android-sdk/build-tools/36.0.0
$BT/aapt2 dump permissions build/app/outputs/flutter-apk/app-release.apk
$BT/apksigner verify --print-certs build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

## حقائق مهمة عن الخادم (مقيسة)

توقيع الطلب: `HMAC-SHA256(secret, "<deviceId>|<ts>|<METHOD>|<path+query>")` مع
الترويسات `x-device-id`, `x-app-ts`, `x-app-sig`, `x-app-version`, `User-Agent: X-App/1.0.0`.

- `GET /v1/data/compatibility` يقبل `q`, `brand`, `type`, `limit`. **`limit` أقصاه
  500 فعلياً**.
- `POST /v1/data/compat/search` هو مسار البحث المعتمد. يقبل `{q, brand, type}`.
  يرجع `{records, types, charged, remaining}`.
- **البحث صار على الخادم**: البحث المحلي السابق كان يحمّل ملف الشركة كاملاً
  (~65KB و0.9 ثانية) عند كل دخول. الآن الكتابة تُرسَل للخادم. لا تعدّل بنية المرآة
  — موارد مشتركة مع تطبيق آخر — لكن استعلام `LOWER(data) LIKE ?` داخل
  `mirrorSearchCompat` يعمل ولا يحتاج `search_text`.
- **استعلام فارغ لا يُخصم**: يرجع `types` فقط (بلا `records`) لبناء صف الأنواع،
  وهو سلوك النقطتين. لا تُعِد الخصم على `q=''` وإلا استُنزف المشترك بمجرد فتح شاشة.
- يقولب `type` يعمل ويرجع أنواعاً مختلفة.
- 15 شركة، ~1256 سجلاً. أنواع القطع: `SCREEN`, `BATTERY`, `GLASS`, `INCASSABLE`.

## نظام العملات في التوافقات

البحث الواحد يُخصم من رصيد بطاقات المخططات (نفس العملة، لا نظام منفصل).

- الثمن من `settings.compatSearchCost` (ضبطه المالك، 0=مجاني، الافتراضي 1).
- **الخصم مرة واحدة لكل استعلام جديد**: بصمة `cq:<uid>:<hmac>` بمهلة 900 ثانية
  تجعل إعادة البحث نفسه أو التنقل بين النتائج مجانياً. كل نص جديد يكلّف — وهذا
  ما يمنع سحب التوافقات آلياً.
- **البصمة تُكتب بعد نجاح الخصم فقط**: كتابتها قبله كانت تمنع أي بحث آخر خلال
  النافذة من الخصم حتى لو تغيّر النص.
- `consumeFileQuota` تخصم ذرياً (`UPDATE ... WHERE quota_balance > 0 RETURNING`)
  فسباق الطلبات لا يعطي بيانات مجانية، و`consumeFileQuota` هي موضع تسجيل
  البصمة الوحيد (تسجيلها مرتين كان يفسد نافذة السماح).
- التطبيق ينتظر 280ms بعد آخر ضغطة مفتاح قبل الطلب (debounce) ويسقط الردود
  القديمة بـ `_seq` — أقل استهلاكاً وأسرع إحساساً من طلب لكل حرف.
- `Api.searchCompatCharged` يتراجع لـ `GET /v1/data/compatibility` عند 404 فقط،
  كي يعمل التطبيق قبل نشر الخادم الجديد.

## رابط تيليجرام والباقات: مصدر واحد

الوجهة يحددها المالك من لوحته (`settings.telegramLink`) — **لا رابط مثبت في
الكود**. `lib/core/app_config.dart` هو المصدر الوحيد:

- `load()` عند الإقلاع: يقرأ من `SharedPreferences` فيعمل بلا شبكة.
- `applyBootstrap(boot)` من ردّ `/v1/bootstrap` (يُمرَّر جاهزاً، بلا جلب مكرر).
- `applyOwnerSettings(...)` بعد حفظ المالك — يشمل الشاشات المفتوحة فوراً عبر
  `notifyListeners` (تستمع لها `Shell`).
- رابط فارغ من الخادم **لا يمحو** رابطاً صالحاً محفوظاً. و`reset()` يمسحه
  للاختبارات فقط.
- `openExternal` يتعامل مع الرابط الفارغ برسالة واضحة بدل الفشل الصامت.

عند إضافة أي شاشة تستخدم تيليجرام: اقرأ `AppConfig.instance.telegram`، ولا
تضع قيمة افتراضية. لتجهيز رسالة: `shell.dart::_tgWithText` (يستخدم `&` إن كان
في الرابط استعلام مسبقاً).

## فتح تيليجرام: مخطط tg:// لا https

أندرويد يربط مخطط `https` بالمتصفح افتراضياً، فرابط `https://t.me/...` **لا**
يفتح تيليجرام إلا إن اختار المستخدم «افتح دائماً» فيه. لذلك كل «تواصل مع
المالك» كان ينتهي في المتصفح.

- `external_link.dart::telegramAppUri` يحوّل `https://t.me/<اسم>` إلى
  `tg://resolve?domain=<اسم>`، ويحفظ `text`/`start` كما هي، ويحوّل الدعوات
  `+مفتاح` إلى `tg://join?invite=`. يرجع `null` لغير روابط تيليجرام.
- `openExternal` يجرّب مخطط التطبيق أولاً ثم الرابط الأصلي، ويحفظ `text`
  كي تصل الرسالة الجاهزة. لا تعتمد على `canLaunchUrl` وحدها.
- الروابط غير التابعة لتيليجرام لا تُمس (تحقق صارم من النطاق).

## شاشة التوافقات: النوع أولاً

`compat_brand_screen.dart` يستعلم الخادم أثناء الكتابة داخل نطاق الشركة والنوع.
`CompatTypeMeta` يحمل اسم كل نوع وأيقونته ولونه وترتيبه.

- **لا أعداد في صف الأنواع**: الأيقونة والاسم فقط.
- لا نتائج قبل اختيار النوع وكتابة الاستعلام.
- `CompatBrand.ref` يرسل `v_poco` للشركات الفرعية ليصفّيها الخادم على كلمتها.
- الشركات الفرعية تتداخل مشروعاً (POCO ∩ Redmi = سجلات تذكر الفرعيتين)،
  فالتقاطع ليس خطأً.
- عند الخصم يظهر رصيد البطاقات كشريحة في شريط العنوان، وعند النفاد حوار
  يوجّه للباقات بدل رسالة خطأ صامتة.
- `compat_catalog.dart` بقي لـ `normalizeModel` و`rankModels` (إبراز وترتيب
  النتائج) — لم يعد يبني فهرساً محلياً كاملاً.

## أول تشغيل: «تعذر الاتصال تحقق من الإنترنت»

كانت `splash.dart` تعيد المحاولة في حلقة صامتة بلا حد ولا مخرج. الآن:

- تُعاد المحاولة تلقائياً 3 مرات بتراجع تدريجي (600ms × رقم المحاولة) —
  يراعي شبكة أول تشغيل البطيئة.
- عند الفشل يظهر **زر «إعادة المحاولة»** برسالة واضحة، بدل انتظار بلا نهاية.
- الاستثناءات غير الشبكية (خطأ من الخادم مثلاً) لا تُعاد — إعادة المحاولة بلا
  فائدة تُطيل الانتظار.
- `flutter analyze lib` يجب أن يبقى 0 error / 0 warning.
- اختبارات `app/test/` تحمي هذه السلوكيات: الثيم الفاتح، اسم MAPX، معرّف الحزمة
  الثابت، واستقلال شعارات الشركات.

## أندرويد: أخطاء متكررة

- **`INTERNET` غير موجود في release**: قالب Flutter يضعه في debug/profile فقط.
  يجب إعلانه في `app/android/app/src/main/AndroidManifest.xml` وإلا يفشل كل اتصال
  برسالة «تعذر الاتصال تحقق من الإنترنت».
- **فتح تيليجرام/الروابط يفشل صامتاً**: أندرويد 11+ يخفي التطبيقات غير المعلَنة.
  يجب إعلان `<queries>` مع `scheme https/http/tg` وحزم تيليجرام، وإلا يعيد
  `canLaunchUrl` القيمة `false`. استخدم `openExternal` في `lib/ui/external_link.dart`
  ولا تستخدم `canLaunchUrl` كشرط لإطلاق الرابط.

## توزيع النسخ: الرابط الدائم على Cloudflare R2

خادم التحميل المحلي (`/workspace/serve_dist.sh`، منفذ 12000) يعمل داخل بيئة
العمل المؤقتة و**يموت كلما أُعيد إنشاء البيئة** فيتوقف الرابط ويشكو المستخدم
أن «خادم التحميل لا يحمل». حلقة `while true` لا تكفي لأن إعادة إنشاء البيئة
تقتل العملية الأم أيضاً.

الرابط الدائم المعتمد (لا يعتمد على بيئة العمل):

```
https://pub-8da12185716441d4bcdcd4c49f395174.r2.dev/download.html
```

- الحاوية: `xapp-releases` على حساب Cloudflare، عامة عبر managed domain.
- الملفات: `MAPX-v<النسخة>.apk` مع نسخ `-arm64` و `-armeabi-v7a` و `-x86_64`.
- الرفع عبر API بلا wrangler:
  `curl -X PUT https://api.cloudflare.com/client/v4/accounts/<ACC>/r2/buckets/xapp-releases/objects/<name> -H "Authorization: Bearer <token>" --data-binary @<file>`
  التوكن في `/workspace/.cf_token` والحساب `4b386375f3294750ffdb6f89de3a09db`.
- صفحة التنزيل تُنشر باسم `download.html` لأن روابطها نسبية فتعمل كما هي.

عند كل نسخة جديدة: ارفع الحزم الأربع مع `download.html` و `SHA256.txt`، وتأكد
أن بصمة الملف المنزّل من الرابط تطابق `sha256sum` المحلي.

## ترتيب نتائج بحث التوافقات (طبقة الخادم)

`mirrorSearchCompat` كان بلا `ORDER BY`، فيُعيد D1 صفوفه بترتيب تخزين
اعتباطي: بحث «note 12» يعرض سجلاً فيه `note 12s` قبل سجل فيه `note 12 pro+`.
الحل: جلب حتى `limit*3` صف ثم ترتيبها في JS عبر `relevanceScore`
(مطابقة تامة في موديل > بداية موديل > احتواء > نوع فرعي > أي نص)، مع توحيد
المسافات لأن البيانات تكتب الموديل صيغتين («note 12» و«note12pro»).

الترتيب في JS لا في SQL عن قصد: أسماء حقول `data` JSON غير موثّقة في المخطط،
فـ`json_extract` على اسم مخمّن يهشّ؛ حقول التوافقات الفعلية هي
`compatibleModels` (قائمة) و`subCategory` (كائن فيه `name`) و`componentType`.
اختبار الحراسة: `app/test/compat_search_order_test.dart`.