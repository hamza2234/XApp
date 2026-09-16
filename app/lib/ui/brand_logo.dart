import 'package:flutter/material.dart';
import 'theme.dart';

/// شعار شركة حقيقي من الأصول، أو حرف احتياطي إن لم يوجد
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.name, this.size = 46});
  final String name;
  final double size;

  /// أسماء بديلة → ملف الأصل
  static const _alias = {
    'mi': 'xiaomi', 'redmi': 'xiaomi', 'xiaomi': 'xiaomi',
    'iphone': 'iphone', 'apple': 'iphone',
    'oneplus': 'oneplus', 'one_plus': 'oneplus', 'one plus': 'oneplus',
    'pixel': 'google', 'google': 'google',
    'poco': 'poco', 'pocophone': 'poco',
    'tecno': 'tecno', 'itel': 'itel', 'infinix': 'infinix',
    'samsung': 'samsung', 'huawei': 'huawei', 'honor': 'honor',
    'oppo': 'oppo', 'realme': 'realme', 'vivo': 'vivo',
    'nokia': 'nokia', 'sony': 'sony', 'motorola': 'motorola',
    'zte': 'zte', 'meizu': 'meizu', 'reno': 'oppo',
    'black shark': 'xiaomi', 'blackshark': 'xiaomi',
  };

  static const _available = {
    'xiaomi', 'iphone', 'tecno', 'honor', 'oneplus', 'vivo', 'google',
    'huawei', 'realme', 'poco', 'motorola', 'nokia', 'sony', 'samsung',
    'oppo', 'itel',
  };

  static const _colors = {
    'xiaomi': Color(0xFFFF6900), 'realme': Color(0xFFFFC915),
    'huawei': Color(0xFFCF0A2C), 'samsung': Color(0xFF1428A0),
    'infinix': Color(0xFF44B979), 'itel': Color(0xFF00A8E8),
    'tecno': Color(0xFF005EB8), 'vivo': Color(0xFF415FFF),
    'oppo': Color(0xFF2D683D), 'nokia': Color(0xFF0065A3),
    'oneplus': Color(0xFFEB0028), 'sony': Color(0xFF8A8A8A),
    'meizu': Color(0xFF008DEB), 'zte': Color(0xFF0A50A0),
    'google': Color(0xFF4285F4), 'reno': Color(0xFF2D683D),
    'motorola': Color(0xFF5B92E5), 'iphone': Color(0xFF555555),
    'apple': Color(0xFF555555), 'honor': Color(0xFF00C4D8),
    'poco': Color(0xFFFFD900),
  };

  String get _key {
    var k = name.replaceAll(RegExp(r'^\d+'), '').toLowerCase().trim();
    k = _alias[k] ?? k;
    return k;
  }

  @override
  Widget build(BuildContext context) {
    final k = _key;
    final color = _colors[k] ?? XTheme.accent2;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _available.contains(k)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Image.asset('assets/brands/$k.jpg',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _letter(color)),
              ),
            )
          : _letter(color),
    );
  }

  Widget _letter(Color color) {
    final n = name.replaceAll(RegExp(r'^\d+'), '').trim();
    return Center(
      child: Text(
        n.isEmpty ? '?' : n[0].toUpperCase(),
        style: TextStyle(
            fontSize: size * .48, fontWeight: FontWeight.w900, color: color),
      ),
    );
  }
}
