# تطبيق X

تطبيق توافقات ومخططات هواتف — Android (APK) + iOS، بواجهة عربية RTL حديثة.

## البنية

```
XApp/
├── worker/          x-app-api — Cloudflare Worker (الواجهة الخلفية الوحيدة)
│   ├── src/index.ts كل المسارات + طبقات الأمان
│   ├── schema.sql   مخطط قاعدة x-app-db
│   └── wrangler.toml
└── app/             تطبيق Flutter (كود واحد → APK + iOS)
    └── lib/
        ├── core/    api.dart (توقيع HMAC) • store.dart • models.dart • config.dart
        └── ui/      splash • auth • shell • compat • schem • browser • viewer • owner
```

## العزل عن التطبيقات الأخرى (مهم)

- `phonex-mirror` (D1) و `phonex-schematics` (R2): **قراءة فقط** — لا يوجد أي استدعاء كتابة عليها في كود Worker.
- بيانات X (مستخدمون/تثبيتات/إعدادات/أمان/إعلانات خاصة): في `x-app-db` و `x-app-quota` — منفصلة كلياً.
- لا يُعدَّل Worker الآخر `phonex-drive-proxy` ولا أي مورد مشترك.

## طبقات الأمان

1. توقيع HMAC-SHA256 لكل طلب: `X-App-Sig = HMAC(secret, deviceId|ts|method|path+query)`
2. JWT للجلسات — الزائر `guest_{deviceId}` مرتبط بالجهاز، المستخدم مرتبط بجهاز واحد
3. كشف مزارع الأجهزة + حظر IP متصاعد عند الإساءة
4. سجل أحداث أمنية (جهاز + IP + مسار + سبب) يظهر في لوحة المالك
5. حصة يومية للزائر على فتح المخططات — يتحكم بها المالك لحظياً
6. بوابة إصدارات: إيقاف أي إصدار أو رفع الحد الأدنى من اللوحة

## النشر

```bash
cd worker
npx wrangler deploy
# الأسرار (مرة واحدة):
# wrangler secret put X_JWT_SECRET / X_SIG_SECRET / X_OWNER_KEY
```

## بناء التطبيق

```bash
cd app
flutter pub get
flutter build apk --release          # APK
# iOS: يتطلب macOS + Xcode — الكود جاهز، نفّذ flutter build ipa على Mac
```

## إنشاء حساب المالك (مرة واحدة)

```bash
curl -X POST https://x-app-api.www-hmzhh123-com.workers.dev/v1/owner/bootstrap \
  -H "x-owner-key: <X_OWNER_KEY>" -H "x-device-id: setup" \
  -H "x-app-ts: <now_ms>" -H "x-app-sig: <hmac>" -H "x-app-version: 1" \
  -d '{"username":"owner","password":"..."}'
```
(أو استخدم سكربت owner_bootstrap.py المرفق)
