import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme.dart';

/// قفل البصمة — طبقة ثانية على لوحة المالك بعد كلمة المرور.
///
/// لماذا بعد كلمة المرور لا بدلاً منها؟ كلمة المرور تثبت الهوية، والبصمة
/// تثبت أن من يمسك الجهاز الآن هو صاحبه. من سرق هاتفاً مفتوحاً ووجد جلسة
/// مالك فعّالة لا يستطيع فتح اللوحة بلا بصمة المالك.
///
/// القفل اختياري ويتفعّل من داخل اللوحة نفسها: لو أُلزم به الجميع لتعطّلت
/// اللوحة على جهاز بلا بصمة أو بمستشعر معطّل.
class BiometricLock {
  const BiometricLock._();

  static const _kEnabled = 'x_bio_enabled';
  static final _auth = LocalAuthentication();

  static Future<bool> get enabled async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kEnabled) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, v);
  }

  /// هل الجهاز يملك بصمة مسجّلة فعلاً؟ مستشعر موجود بلا بصمة لا يفيد.
  static Future<bool> get available async {
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// يطلب التحقق. يُعيد true إن نجح، وfalse في كل حال أخرى.
  ///
  /// لا نرمي استثناءً عند الإلغاء: إلغاء المستخدم قراره لا خطأ، ومعاملته
  /// كخطأ كانت ستُظهر رسالة حمراء لمجرد ضغط زر الرجوع.
  static Future<bool> authenticate({
    String reason = 'أكّد هويتك لفتح لوحة المالك',
  }) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        // persistAcrossBackgrounding: نافذة البصمة تُغلق أحياناً عند تبديل
        // التطبيق (إشعار وارد مثلاً). بدونها يفشل التحقق ويُطلب من المالك
        // الإعادة رغم أنه لم يخطئ.
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

/// شاشة قفل البصمة — تُعرض قبل الدخول إلى اللوحة.
class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // طلب تلقائي عند الفتح: خطوة أقل للمالك، وشاشة القفل ليست مخفية
    WidgetsBinding.instance.addPostFrameCallback((_) => _try());
  }

  Future<void> _try() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await BiometricLock.authenticate();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked();
    } else {
      setState(() => _error = 'لم يتم التحقق — أعد المحاولة');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    gradient: XTheme.gradient,
                    borderRadius: BorderRadius.circular(XTheme.rXl),
                    boxShadow: XTheme.glow(XTheme.accent, strength: 1.2),
                  ),
                  child: const Icon(Icons.fingerprint,
                      size: 52, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text('لوحة المالك محميّة',
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'أكّد بصمة إصبعك للمتابعة',
                  style: TextStyle(color: XTheme.textDim),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: const TextStyle(color: XTheme.danger, fontSize: 13)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: XTheme.gradient,
                        borderRadius: BorderRadius.circular(XTheme.rMd),
                        boxShadow: XTheme.glow(XTheme.accent, strength: .7)),
                    child: ElevatedButton(
                      onPressed: _busy ? null : _try,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(XTheme.rMd)),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('تحقّق بالبصمة',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('رجوع',
                      style: TextStyle(color: XTheme.textDim)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
