import 'package:flutter/material.dart';
import 'theme.dart';

/// عملة ذهبية أنيقة لرصيد بطاقات المخططات
class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Color(0xFFFFE29A), Color(0xFFF5B942), Color(0xFFB8860B)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [
          BoxShadow(color: Color(0x66F5B942), blurRadius: 6, spreadRadius: 0)
        ],
      ),
      child: Center(
        child: Container(
          width: size * .78, height: size * .78,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF8A6410), width: size * .07),
          ),
          child: Center(
            child: Text('M',
                style: TextStyle(
                    fontSize: size * .52,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF6B4C08),
                    height: 1)),
          ),
        ),
      ),
    );
  }
}

/// شعار شركة حقيقي من الأصول، أو حرف احتياطي إن لم يوجد
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, required this.name, this.size = 56});
  final String name;
  final double size;

  /// أسماء بديلة → ملف الأصل
  static const _alias = {
    'mi': 'xiaomi', 'xiaomi': 'xiaomi',
    'redmi': 'redmi',
    'black shark': 'blackshark', 'blackshark': 'blackshark',
    'black shark 3': 'blackshark',
    'iphone': 'iphone', 'apple': 'iphone',
    'oneplus': 'oneplus', 'one_plus': 'oneplus', 'one plus': 'oneplus',
    'pixel': 'google', 'google': 'google',
    'poco': 'poco', 'pocophone': 'poco',
    'tecno': 'tecno', 'itel': 'itel', 'infinix': 'infinix',
    'samsung': 'samsung', 'huawei': 'huawei', 'honor': 'honor',
    'oppo': 'oppo', 'realme': 'realme', 'vivo': 'vivo',
    'nokia': 'nokia', 'sony': 'sony', 'motorola': 'motorola',
    'zte': 'zte', 'meizu': 'meizu', 'reno': 'oppo',
  };

  static const _available = {
    'xiaomi', 'redmi', 'blackshark', 'infinix', 'iphone', 'tecno',
    'honor', 'oneplus', 'vivo', 'google', 'huawei', 'realme', 'poco',
    'motorola', 'nokia', 'sony', 'samsung', 'oppo', 'itel',
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
    'poco': Color(0xFFFFD900), 'redmi': Color(0xFFE00040),
    'blackshark': Color(0xFF00C060),
  };

  /// يحل اسم الشركة إلى مفتاح الأصل: يزيل بادئة الترتيب الرقمية ويوحّد
  /// الأسماء البديلة. عام ليسهل اختباره.
  static String assetKeyFor(String name) {
    var k = name.replaceAll(RegExp(r'^\d+'), '').toLowerCase().trim();
    return _alias[k] ?? k;
  }

  static bool hasAsset(String name) => _available.contains(assetKeyFor(name));

  String get _key => assetKeyFor(name);

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
              borderRadius: BorderRadius.circular(15),
              child: Image.asset('assets/brands/$k.jpg',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _letter(color)),
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
