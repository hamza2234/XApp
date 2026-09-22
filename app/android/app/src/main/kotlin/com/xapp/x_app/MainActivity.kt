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
