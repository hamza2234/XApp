import 'package:flutter/material.dart';
import '../core/app_config.dart';
import 'theme.dart';
import 'external_link.dart';

/// حوار انتهاء الحصة — اشترك/تواصل مع المالك لإنشاء حساب بلا حدود.
///
/// يُقرأ الرابط من الإعدادات المشتركة، فيتبعه تغيير المالك مباشرة بدل
/// قيمة مثبتة في الكود.
Future<void> showSubscribeDialog(BuildContext context,
    {String? telegram, String? title, String? body}) {
  final link = telegram ?? AppConfig.instance.telegram;
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
      decoration: BoxDecoration(
        color: XTheme.surface,
        borderRadius: BorderRadius.circular(XTheme.rXl),
        border: Border.all(color: XTheme.gold.withOpacity(.3)),
        boxShadow: XTheme.shadow(lift: 1.4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68, height: 68,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [XTheme.gold, XTheme.accent2],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: XTheme.glow(XTheme.gold, strength: .8),
            ),
            child: const Icon(Icons.workspace_premium,
                color: Colors.white, size: 34),
          ),
          const SizedBox(height: 18),
          Text(title ?? 'انتهت حصتك المجانية',
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            body ??
                'انتهت حصتك المجانية اليوم ولا توجد عملات في رصيدك. اشترِ باقة أو تواصل مع المالك عبر تيليجرام',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: XTheme.textDim, fontSize: 13.5, height: 1.7),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: XTheme.gradient,
                  borderRadius: BorderRadius.circular(XTheme.rMd),
                  boxShadow: XTheme.glow(XTheme.accent, strength: .7)),
              child: ElevatedButton.icon(
                onPressed: () =>
                    openExternal(context, link, label: 'تيليجرام'),
                icon: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 19),
                label: const Text('تواصل مع المالك — تيليجرام',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(XTheme.rMd)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('لاحقاً',
                style: TextStyle(color: XTheme.textDim)),
          ),
        ],
      ),
    ),
  );
}
