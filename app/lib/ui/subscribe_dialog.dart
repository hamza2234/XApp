import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';

/// حوار انتهاء الحصة — اشترك/تواصل مع المالك لإنشاء حساب بلا حدود
Future<void> showSubscribeDialog(BuildContext context,
    {String telegram = 'https://t.me/phonex6'}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: XTheme.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: XTheme.gold.withOpacity(.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 62, height: 62,
            decoration: BoxDecoration(
              color: XTheme.gold.withOpacity(.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(Icons.workspace_premium,
                color: XTheme.gold, size: 32),
          ),
          const SizedBox(height: 16),
          const Text('انتهت حصة العرض اليومية',
              style:
                  TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'للتصفح وفتح المخططات بلا حدود، أنشئ حساباً بالتواصل مع المالك عبر تيليجرام',
            textAlign: TextAlign.center,
            style: TextStyle(color: XTheme.textDim, fontSize: 13.5),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: XTheme.gradient,
                  borderRadius: BorderRadius.circular(16)),
              child: ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(telegram);
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                label: const Text('تواصل مع المالك — تيليجرام',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
