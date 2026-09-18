import 'package:flutter/material.dart';
import '../core/app_config.dart';
import 'theme.dart';

/// نافذة سياسة الخصوصية — تُفتح من خانة الموافقة عند التسجيل أو الدخول.
///
/// النص يكتبه المالك من لوحته، ويُعرض هنا نصاً خاماً بلا أي تفسير HTML:
/// لو فسّرناه لاستطاع المالك — أو من يسرق حسابه — حقن محتوى في التطبيق.
/// التنسيق يُطبَّق على مستوى الأسطر: سطر ينتهي بنقطتين يظهر عنواناً،
/// وسطر يبدأ بـ • يظهر بنداً، والباقي فقرة عادية.
class PrivacyPolicySheet extends StatelessWidget {
  const PrivacyPolicySheet({super.key});

  /// يفتح النافذة من أسفل الشاشة بارتفاع مريح للقراءة.
  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const PrivacyPolicySheet(),
      );

  @override
  Widget build(BuildContext context) {
    final text = AppConfig.instance.privacyPolicy;
    return DraggableScrollableSheet(
      initialChildSize: .85,
      minChildSize: .5,
      maxChildSize: .95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: BoxDecoration(
          color: XTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // مقبض السحب — يوضح أن النافذة قابلة للتمديد
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44, height: 4,
              decoration: BoxDecoration(
                color: XTheme.textDim.withOpacity(.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      gradient: XTheme.gradient,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.privacy_tip_outlined,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('سياسة الخصوصية',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'إغلاق',
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: XTheme.textDim.withOpacity(.15)),
            Expanded(
              child: text.trim().isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'لم تُضف سياسة الخصوصية بعد.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: XTheme.textDim),
                        ),
                      ),
                    )
                  : ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      children: _render(text),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// يحوّل النص الخام إلى فقرات وعناوين وبنددون بلا تفسير أي وسوم.
  static List<Widget> _render(String raw) {
    final out = <Widget>[];
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) {
        out.add(const SizedBox(height: 10));
        continue;
      }
      final isBullet = t.startsWith('•') || t.startsWith('-');
      final isHeading = t.endsWith(':') && t.length < 60;
      out.add(Padding(
        padding: EdgeInsets.only(
            right: isBullet ? 8 : 0, bottom: isHeading ? 4 : 6),
        child: Text(
          t,
          textAlign: TextAlign.start,
          style: TextStyle(
            fontSize: isHeading ? 15.5 : 14,
            height: 1.7,
            fontWeight: isHeading ? FontWeight.w800 : FontWeight.w400,
            color: isHeading ? XTheme.text : XTheme.text.withOpacity(.88),
          ),
        ),
      ));
    }
    return out;
  }
}

/// خانة الموافقة على السياسة — إلزامية قبل إنشاء الحساب.
///
/// لماذا إلزامية؟ لأن التسجيل يعني إنشاء حساب مرتبط بجهازك وحفظ بياناتك،
/// ولا يصح ذلك بلا علمك. الدخول لحساب قائم لا يشترطها: الموافقة أُخذت
/// عند التسجيل، وطلبها في كل دخول عبء بلا فائدة.
class PrivacyConsentTile extends StatelessWidget {
  const PrivacyConsentTile({
    super.key,
    required this.accepted,
    required this.onChanged,
    this.required = true,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  /// إلزامية عند التسجيل (إنشاء حساب جديد يحفظ بياناتك)، واختيارية عند
  /// الدخول: صاحب الحساب القائم وافق سابقاً، وإلزامه مجدداً عبء بلا معنى.
  final bool required;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!accepted),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            // خانة مخصّصة بدل Checkbox: حجم أوضح وضغطة أوسع على الجوال
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24, height: 24,
              decoration: BoxDecoration(
                gradient: accepted ? XTheme.gradient : null,
                color: accepted ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: accepted
                      ? Colors.transparent
                      : XTheme.textDim.withOpacity(.55),
                  width: 1.6,
                ),
              ),
              child: accepted
                  ? const Icon(Icons.check_rounded,
                      size: 17, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(required ? 'أوافق على ' : 'قرأت ',
                      style: TextStyle(
                          fontSize: 13, color: XTheme.text.withOpacity(.85))),
                  // زر نصي يفتح النافذة — لا يبدّل الموافقة بلمسة خاطئة
                  InkWell(
                    onTap: () => PrivacyPolicySheet.show(context),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 2),
                      child: Text(
                        'سياسة الخصوصية',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: XTheme.accent,
                          decoration: TextDecoration.underline,
                          decorationColor: XTheme.accent,
                        ),
                      ),
                    ),
                  ),
                  if (required)
                    Text(' وقرأتها',
                        style: TextStyle(
                            fontSize: 13, color: XTheme.text.withOpacity(.85))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
