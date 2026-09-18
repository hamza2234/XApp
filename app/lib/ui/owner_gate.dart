import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/store.dart';
import 'biometric_gate.dart';
import 'owner_screen.dart';
import 'theme.dart';

/// بوابة لوحة المالك — ثلاث طبقات قبل الوصول.
///
/// 1. جلسة مالك معزولة: تُطلب من `/v1/owner/login` بسرّ مستقل، وليست جلسة
///    المستخدم العادي. حتى لو كان الحساب role=owner في جلسة عادية، لا تكفي
///    لفتح اللوحة.
/// 2. بصمة الجهاز (إن فعّلها المالك): تثبت أن من يمسك الهاتف الآن هو صاحبه.
/// 3. جلسة صالحة: كل ردود اللوحة مشفّرة بمفتاح مشتق من الجلسة، فجلسة منتهية
///    أو مسروقة لا تُفك أصلاً.
///
/// لماذا بوابة مستقلة لا شاشة داخل اللوحة؟ لأن فتح اللوحة يجب ألا يبدأ
/// بتحميل أي بيانات: البوابة تفصل تماماً بين «محاولة الدخول» و«البيانات»،
/// فلا يُرسل طلب واحد قبل التحقق.
class OwnerGate extends StatefulWidget {
  const OwnerGate({super.key, required this.api, required this.store});

  final Api api;
  final Store store;

  @override
  State<OwnerGate> createState() => _OwnerGateState();
}

class _OwnerGateState extends State<OwnerGate> {
  bool _bioChecked = false;
  bool _bioOk = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  /// البصمة تُطلب فقط إن كان للمالك جلسة قائمة وفعّل القفل.
  Future<void> _checkBiometric() async {
    final hasSession = widget.store.hasOwnerSession;
    final enabled = await BiometricLock.enabled;
    if (!mounted) return;
    setState(() {
      _bioChecked = true;
      // لا بصمة بلا جلسة: نافذة بصمة قبل الدخول بلا معنى
      _bioOk = !hasSession || !enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_bioChecked) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: XTheme.accent)),
      );
    }
    if (!_bioOk) {
      return BiometricGate(
        onUnlocked: () async {
          await widget.store.markOwnerUnlocked();
          if (mounted) setState(() => _bioOk = true);
        },
      );
    }
    if (!widget.store.hasOwnerSession) {
      return _OwnerLoginScreen(
        api: widget.api,
        store: widget.store,
        onSuccess: () => setState(() {}),
      );
    }
    return OwnerScreen(api: widget.api, store: widget.store);
  }
}

/// شاشة دخول المالك — نموذج بسيط بلا أي تلميح عن وجود الحساب.
class _OwnerLoginScreen extends StatefulWidget {
  const _OwnerLoginScreen({
    required this.api,
    required this.store,
    required this.onSuccess,
  });

  final Api api;
  final Store store;
  final VoidCallback onSuccess;

  @override
  State<_OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<_OwnerLoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'أدخل اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.ownerLogin(_user.text.trim(), _pass.text);
      final token = r['token']?.toString();
      if (token == null || token.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'تعذر إنشاء الجلسة';
        });
        return;
      }
      await widget.store.setOwnerToken(token);
      // مسح الحقلين فوراً: كلمة المرور لا تبقى في الذاكرة بعد الاستخدام.
      _pass.clear();
      if (!mounted) return;
      widget.onSuccess();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'تعذر الاتصال — تحقق من الإنترنت';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دخول المالك')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 20),
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                  gradient: XTheme.gradient,
                  borderRadius: BorderRadius.circular(XTheme.rXl),
                  boxShadow: XTheme.glow(XTheme.accent, strength: 1.1),
                ),
                child: const Icon(Icons.shield_moon_outlined,
                    size: 46, color: Colors.white),
              ),
              const SizedBox(height: 20),
              const Text('منطقة محميّة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text('هذه اللوحة للمالك وحده. كل الوصول مُسجَّل.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: XTheme.textDim, fontSize: 13)),
              const SizedBox(height: 26),
              TextField(
                controller: _user,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    hintText: 'اسم المستخدم',
                    prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                onSubmitted: (_) => _submit(),
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: 'كلمة المرور',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: XTheme.danger.withOpacity(.10),
                    borderRadius: BorderRadius.circular(XTheme.rSm),
                    border:
                        Border.all(color: XTheme.danger.withOpacity(.26)),
                  ),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: XTheme.danger, fontSize: 13)),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: XTheme.gradient,
                      borderRadius: BorderRadius.circular(XTheme.rMd),
                      boxShadow: XTheme.glow(XTheme.accent, strength: .7)),
                  child: ElevatedButton(
                    onPressed: _busy ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(XTheme.rMd)),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('دخول',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
