import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';

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
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: XTheme.textDim, fontSize: 15, height: 1.6),
                ),
                const SizedBox(height: 26),
                if ((url ?? '').isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: XTheme.gradient,
                          borderRadius: BorderRadius.circular(16)),
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final uri = Uri.parse(url!);
                          if (await canLaunchUrl(uri)) {
                            launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
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
