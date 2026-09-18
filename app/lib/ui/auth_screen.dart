import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/app_config.dart';
import '../core/store.dart';
import 'theme.dart';
import 'external_link.dart';
import 'privacy_sheet.dart';

/// تسجيل الدخول / طلب حساب / متابعة كزائر
/// إنشاء الحساب يتطلب تفعيل المالك — التواصل عبر تيليجرام.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.store});
  final Api api;
  final Store store;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _registerMode = false;
  bool _busy = false;
  bool _agreed = false;
  String? _msg;
  bool _msgOk = false;

  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _name = TextEditingController();
  final _note = TextEditingController();

  Future<void> _login() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      _set('أدخل اسم المستخدم وكلمة المرور');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.api.login(_user.text.trim(), _pass.text);
      await widget.store.setToken(r['token']);
      await widget.store.setUser(r['user']);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      _set(e.message);
    } catch (_) {
      _set('تعذر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRegister() async {
    if (_user.text.trim().length < 3 || _pass.text.length < 6) {
      _set('اسم مستخدم (3+) وكلمة مرور (6+) مطلوبة');
      return;
    }
    // الموافقة على السياسة شرط للتسجيل: التسجيل يحفظ بيانات مرتبطة بجهازك،
    // ولا يصح بلا علمك. الدخول لحساب قائم لا يشترطها — الموافقة أُخذت سابقاً.
    if (!_agreed) {
      _set('يجب الموافقة على سياسة الخصوصية أولاً');
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.api.register(
          _user.text.trim(), _pass.text, _name.text.trim(), _note.text.trim());
      _set(
          'تم إرسال طلبك — فعّل المالك حسابك ثم سجّل دخولك. تواصل عبر تيليجرام للإسراع.',
          ok: true);
      if (r['telegram'] != null) {
        AppConfig.instance
            .applyOwnerSettings(telegram: r['telegram'].toString());
      }
    } on ApiException catch (e) {
      _set(e.message);
    } catch (_) {
      _set('تعذر الاتصال بالخادم');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _set(String m, {bool ok = false}) =>
      setState(() { _msg = m; _msgOk = ok; });

  Future<void> _openTelegram() =>
      openExternal(context, AppConfig.instance.telegram, label: 'تيليجرام');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 30),
              // الشعار بهالة متوهجة — أول ما تقع عليه العين
              Container(
                width: 88, height: 88,
                decoration: BoxDecoration(
                    gradient: XTheme.gradient,
                    borderRadius: BorderRadius.circular(XTheme.rXl),
                    boxShadow: XTheme.glow(XTheme.accent, strength: 1.2)),
                child: const Center(
                    child: Text('MAPX',
                        style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .5,
                            color: Colors.white))),
              ),
              const SizedBox(height: 20),
              Text(_registerMode ? 'طلب حساب جديد' : 'تسجيل الدخول',
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                _registerMode
                    ? 'الحساب يُفعَّل من المالك بعد الطلب'
                    : 'أدخل بياناتك للمتابعة بلا حدود',
                style: TextStyle(color: XTheme.textDim, fontSize: 13.5),
              ),
              const SizedBox(height: 26),
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    TextField(
                      controller: _user,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                          hintText: 'اسم المستخدم',
                          prefixIcon: Icon(Icons.person_outline)),
                      textDirection: TextDirection.ltr,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _pass,
                      obscureText: true,
                      decoration: const InputDecoration(
                          hintText: 'كلمة المرور',
                          prefixIcon: Icon(Icons.lock_outline)),
                      textDirection: TextDirection.ltr,
                    ),
                    if (_registerMode) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _name,
                        decoration: const InputDecoration(
                            hintText: 'الاسم (اختياري)',
                            prefixIcon: Icon(Icons.badge_outlined)),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _note,
                        decoration: const InputDecoration(
                            hintText: 'ملاحظة للمالك (اختياري)',
                            prefixIcon: Icon(Icons.note_alt_outlined)),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // تظهر في الحالتين: إلزامية عند التسجيل، وللعلم عند الدخول.
                    PrivacyConsentTile(
                      accepted: _agreed,
                      required: _registerMode,
                      onChanged: (v) => setState(() => _agreed = v),
                    ),
                    if (_msg != null) ...[
                      const SizedBox(height: 14),
                      // رسالة داخل شريحة ملوّنة: الخطأ يُرى فوراً بدل نص أحمر عائم
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (_msgOk ? XTheme.ok : XTheme.danger)
                              .withOpacity(.10),
                          borderRadius: BorderRadius.circular(XTheme.rSm),
                          border: Border.all(
                              color: (_msgOk ? XTheme.ok : XTheme.danger)
                                  .withOpacity(.26)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                                _msgOk
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                size: 17,
                                color: _msgOk ? XTheme.ok : XTheme.danger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_msg!,
                                  style: TextStyle(
                                      color:
                                          _msgOk ? XTheme.ok : XTheme.danger,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: XTheme.gradient,
                            borderRadius: BorderRadius.circular(XTheme.rMd),
                            boxShadow:
                                XTheme.glow(XTheme.accent, strength: .7)),
                        child: ElevatedButton(
                          onPressed:
                              _busy ? null : (_registerMode ? _doRegister : _login),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(XTheme.rMd)),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Text(_registerMode ? 'إرسال طلب الحساب' : 'دخول',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => setState(() {
                  _registerMode = !_registerMode;
                  _msg = null;
                }),
                icon: Icon(
                    _registerMode ? Icons.login : Icons.person_add_outlined,
                    size: 18),
                label: Text(_registerMode
                    ? 'لديك حساب؟ سجّل دخولك'
                    : 'إنشاء حساب جديد (بطلب للمالك)'),
              ),
              const SizedBox(height: 8),
              GlassCard(
                onTap: _openTelegram,
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                          color: const Color(0xFF229ED9).withOpacity(.15),
                          borderRadius: BorderRadius.circular(XTheme.rSm),
                          border: Border.all(
                              color: const Color(0xFF229ED9).withOpacity(.3))),
                      child: const Icon(Icons.send_rounded,
                          color: Color(0xFF229ED9), size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تواصل مع المالك',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text('عبر تيليجرام لتفعيل حسابك',
                              style: TextStyle(
                                  color: XTheme.textDim, fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.open_in_new,
                        size: 18, color: XTheme.textDim),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.public, size: 18),
                label: const Text('متابعة التصفح كزائر'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
