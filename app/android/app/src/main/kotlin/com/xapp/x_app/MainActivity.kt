package com.xapp.x_app

import android.annotation.SuppressLint
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * بصمة الجهاز الدائمة.
 *
 * معرّف الجهاز السابق كان يُولَّد في Dart ويُخزَّن مع بيانات التطبيق، فمسح
 * البيانات يمحوه ويعود المستخدم بمنحة يومية جديدة. ANDROID_ID مشتق من مفتاح
 * توقيع التطبيق والمستخدم والجهاز، فلا يتغير بمسح البيانات ولا بإعادة
 * التثبيت ولا بتبديل الحساب — وهو ما يجعل المنحة مرتبطة بالجهاز فعلاً.
 *
 * ولماذا `FlutterFragmentActivity` لا `FlutterActivity`؟ إضافة `local_auth`
 * تشترط `FragmentActivity` لعرض نافذة البصمة؛ مع `FlutterActivity` تفشل
 * `authenticate()` بلا استثناء ظاهر فتُعيد false دائماً، فيبدو قفل البصمة
 * «لا يتفعّل» ولا يفتح اللوحة. هذا كان سبب تعطّل القفل في جلسة المالك.
 */
class MainActivity : FlutterFragmentActivity() {
    private val channel = "x_app/device"

    /**
     * مفتاح رئيسي في Android Keystore لتغليف سرّ التوقيع.
     *
     * لماذا تغليف ولا تخزين مباشر: `SharedPreferences` ملف نصّي داخل بيانات
     * التطبيق، يُقرأ بنسخة احتياطية أو بصلاحية root. هنا يُولَّد مفتاح AES
     * داخل Keystore — وهو لا يخرج منها أبداً ولا يمكن استخراجه — ويُشفَّر به
     * السرّ قبل كتابته. نسخة من الملف وحده لا تكفي لفكّه.
     *
     * لا يُطلب `setUserAuthenticationRequired`: طلب بصمة عند كل طلب شبكة
     * يجعل التطبيق غير قابل للاستعمال. الحماية هنا من الاستخراج لا من
     * الاستعمال، وهي المطلوبة.
     */
    private val keyAlias = "x_install_key_wrap"

    private fun masterKey(): javax.crypto.SecretKey {
        val ks = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry(keyAlias, null) as? java.security.KeyStore.SecretKeyEntry)
            ?.let { return it.secretKey }
        val gen = javax.crypto.KeyGenerator.getInstance(
            android.security.keystore.KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore"
        )
        gen.init(
            android.security.keystore.KeyGenParameterSpec.Builder(
                keyAlias,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or
                    android.security.keystore.KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    private fun seal(plain: ByteArray): String {
        val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, masterKey())
        val iv = cipher.iv
        val ct = cipher.doFinal(plain)
        return android.util.Base64.encodeToString(
            iv + ct, android.util.Base64.NO_WRAP
        )
    }

    private fun unseal(blob: String): ByteArray? = try {
        val all = android.util.Base64.decode(blob, android.util.Base64.NO_WRAP)
        val iv = all.copyOfRange(0, 12)
        val ct = all.copyOfRange(12, all.size)
        val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            javax.crypto.Cipher.DECRYPT_MODE, masterKey(),
            javax.crypto.spec.GCMParameterSpec(128, iv)
        )
        cipher.doFinal(ct)
    } catch (_: Throwable) {
        null
    }

    @SuppressLint("HardwareIds")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "fingerprint" -> result.success(
                        try {
                            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID) ?: ""
                        } catch (_: Throwable) {
                            ""
                        }
                    )
                    // سرّ التوقيع مغلَّف بمفتاح Keystore: يُكتب في التخزين
                    // مشفَّراً، ولا يُفكّ إلا داخل هذا الجهاز.
                    "sealSecret" -> {
                        val v = call.argument<String>("value")
                        result.success(
                            if (v == null) null
                            else try { seal(v.toByteArray(Charsets.UTF_8)) }
                            catch (_: Throwable) { null }
                        )
                    }
                    "unsealSecret" -> {
                        val v = call.argument<String>("value")
                        val out = if (v == null) null else unseal(v)
                        result.success(out?.toString(Charsets.UTF_8))
                    }
                    // منع التقاط الشاشة (لقطات ولقطات فيديو) — يُفعَّل عند فتح
                    // المخططات وفيديوهات الدورات ويُطفأ عند الخروج.
                    //
                    // FLAG_SECURE يجعل النظام نفسه يرفض الالتقاط، فلا تُحفظ
                    // صورة ولا يسجّل مسجّل الشاشة المحتوى. هذا حجب على مستوى
                    // النظام: لا ينفع معه تطبيق تصوير يطلب صلاحية، بخلاف أي
                    // حجب داخل الواجهة الذي يُلتفّ عليه بالتصوير الخارجي.
                    "setSecure" -> {
                        val on = call.arguments as? Boolean ?: false
                        window.setFlags(
                            if (on) android.view.WindowManager.LayoutParams.FLAG_SECURE else 0,
                            android.view.WindowManager.LayoutParams.FLAG_SECURE
                        )
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
