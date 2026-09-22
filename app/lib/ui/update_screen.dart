import 'package:flutter/material.dart';
import '../core/app_config.dart';
import 'theme.dart';
import 'external_link.dart';

/// شاشة التحديث الإجباري — نص وصورة وزر يتحكم بها المالك من اللوحة
class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key, this.message, this.url, this.imageUrl, this.apiBase});
  final String? message;
  final String? url;
  final String? imageUrl;
  final String? apiBase;

  @override
  Widget build(BuildContext context) {
    final img = (imageUrl ?? '').startsWith('/')
        ? '${apiBase ?? ''}$imageUrl'
        : imageUrl ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (img.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(img,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _icon()),
                  )
                else
                  _icon(),
                const SizedBox(height: 26),
                const Text('تحديث مطلوب',
                    style: TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text(
                  (message?.isNotEmpty == true)
                      ? message!
                      : 'يتوفر إصدار جديد — حدّث التطبيق للمتابعة',
                  key: const Key('update-message'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: XTheme.textDim, fontSize: 15, height: 1.6),
                ),
                const SizedBox(height: 26),
                // حين لا يضبط المالك رابطاً (أو لم يصل بعد) لا نترك المستخدم
                // أمام نصّ بلا مخرج: نعطيه وصفاً واضحاً وقناة تواصل مع
                // الإدارة، بدل شاشة مسدودة لا يفهم منها ما يفعل.
                if ((url ?? '').isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: XTheme.gold.withOpacity(.10),
                        borderRadius: BorderRadius.circular(14)),
                    child: Column(children: [
                      Icon(Icons.info_outline, color: XTheme.gold, size: 22),
                      const SizedBox(height: 8),
                      const Text(
                        'هذه النسخة لم تعد مدعومة. حدّث التطبيق من مصدر '
                        'التحميل نفسه الذي حصلت منه عليه، ثم افتحه من جديد.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, height: 1.6),
                      ),
                      if (AppConfig.instance.hasTelegram) ...[
                        const SizedBox(height: 10),
                        Text('أو تواصل مع الإدارة لتصلك النسخة الجديدة',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: XTheme.textDim, fontSize: 12.5)),
                      ],
                    ]),
                  ),
                  if (AppConfig.instance.hasTelegram) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => openExternal(
                          context, AppConfig.instance.telegram,
                          label: 'تيليجرام'),
                      icon: const Icon(Icons.support_agent, size: 19),
                      label: const Text('تواصل مع الإدارة'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: XTheme.gold,
                          padding:
                              const EdgeInsets.symmetric(vertical: 13),
                          minimumSize: const Size(double.infinity, 0)),
                    ),
                  ],
                ],
                if ((url ?? '').isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: XTheme.gradient,
                          borderRadius: BorderRadius.circular(16)),
                      child: ElevatedButton.icon(
                        onPressed: () => openExternal(context, url!,
                            label: 'رابط التحديث'),
                        icon: const Icon(Icons.system_update_alt,
                            color: Colors.white),
                        label: const Text('تحديث الآن',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding:
                              const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon() => Container(
        width: 96, height: 96,
        decoration: BoxDecoration(
            gradient: XTheme.gradient,
            borderRadius: BorderRadius.circular(28)),
        child: const Icon(Icons.system_update_alt,
            size: 46, color: Colors.white),
      );
}
