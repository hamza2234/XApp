import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as fc;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:material_ui/material_ui.dart' as mui;

import 'theme.dart';

/// يعزل الحزمة عن ثيم التطبيق ويمنحها ثيم Material خاصاً بها.
///
/// الحزمة مبنية على `material_ui` (المكتبة الرسمية التي تُفصل عن SDK)، وهي
/// تقرأ `Theme.of` من نسختها هي. ثيم تطبيقنا من نوع آخر فلا تراه، فترجع إلى
/// ثيمها الافتراضي **الفاتح**. النتيجة في الوضع الداكن: نصّ غامق فوق سطح
/// غامق — لا يُقرأ. لذلك نلفّ الحزمة بثيم Material صريح مطابق للوضع الحالي.
///
/// `TextStyle` و`Directionality` مشتركان (من `flutter/widgets`)، فالنص العربي
/// واتجاه RTL يمرّان كما هما بلا إعداد إضافي.
class XChatScope extends StatelessWidget {
  const XChatScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final light = XTheme.isLight;
    final brightness = light ? Brightness.light : Brightness.dark;
    // ننسخ حجم الخط من ثيم التطبيق ونبدّل الألوان فقط، حتى تبقى المقاسات
    // موحّدة مع بقية الشاشات.
    final app = Theme.of(context).textTheme;
    final family = app.bodyMedium?.fontFamily;

    mui.TextStyle style(double size, {FontWeight weight = FontWeight.w400}) =>
        mui.TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: XTheme.text,
        );

    return mui.Theme(
      data: mui.ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: mui.ColorScheme.fromSeed(
          seedColor: XTheme.accent,
          brightness: brightness,
        ),
        scaffoldBackgroundColor: XTheme.bg,
        canvasColor: XTheme.surface,
        textTheme: mui.TextTheme(
          bodyLarge: style(16),
          bodyMedium: style(15),
          bodySmall: style(12.5),
          labelLarge: style(14, weight: FontWeight.w600),
          labelMedium: style(12, weight: FontWeight.w600),
          labelSmall: style(10.5),
        ),
      ),
      // تعريب أدوات النظام داخل الحقل (قائمة النسخ واللصق، تلميحات a11y).
      // `MaterialApp` عندنا يوفّر نسخة `flutter` من هذه الترجمات، والحزمة
      // تبحث عن نسخة `material_ui` فلا تجدها وتُطلق استثناءً.
      child: mui.Localizations(
        locale: const Locale('ar'),
        delegates: [
          mui.GlobalMaterialLocalizations.delegate,
          // `Localizations` تشترط وجود مترجم `WidgetsLocalizations` واحد على
          // الأقل وإلا فشل الإطار في التجميع. هذا من `flutter_localizations`.
          GlobalWidgetsLocalizations.delegate,
        ],
        // `mui.Material` لازم أيضاً: حقول الإدخال في الحزمة تطلبه كسلف
        // مباشر، ولا تجده من `Scaffold` العادي لأنه من نسخة Material أخرى.
        child: mui.Material(
          color: XTheme.bg,
          child: child,
        ),
      ),
    );
  }
}

/// نصّ الفقاعة الصادرة: غامق على البرتقالي.
///
/// الأبيض فوق `XTheme.accent` تباينه 2.61 فقط (غير مقروء)، والغامق 8.05.
/// ثابت مشترك لأن موضعين يرسمانه: ثيم الحزمة وفقاعتنا.
const Color chatOnAccent = Color(0xFF2B1A05);

/// يشتقّ ثيم الدردشة من ثيم التطبيق نفسه.
///
/// الألوان تُبنى من `XTheme` صراحةً لتبقى الهوية البرتقالية، وكل الأسطح
/// **معتمة** — لا شفافية ولا زجاج. الزجاج فوق ثيم معتم يمحو المحتوى في الوضع
/// الفاتح (أبيض على أبيض).
fc.ChatTheme xChatTheme(BuildContext context) {
  final appText = Theme.of(context).textTheme;
  // عائلة الخط الفعلية من ثيم التطبيق، لا اسم مفترض.
  final family = appText.bodyMedium?.fontFamily ?? 'Tajawal';

  return fc.ChatTheme(
    shape: BorderRadius.all(Radius.circular(XTheme.rLg)),
    colors: fc.ChatColors(
      // رسائلي: برتقالي الهوية.
      primary: XTheme.accent,
      onPrimary: chatOnAccent,
      // خلفية مساحة الدردشة.
      surface: XTheme.bg,
      onSurface: XTheme.text,
      // فقاعة الطرف الآخر — سطح معتم واضح لا شبه شفّاف.
      surfaceContainer: XTheme.surface,
      surfaceContainerLow: XTheme.surface,
      surfaceContainerHigh: XTheme.surface2,
    ),
    typography: fc.ChatTypography(
      bodyLarge: TextStyle(fontFamily: family, fontSize: 16, height: 1.45),
      bodyMedium: TextStyle(fontFamily: family, fontSize: 15, height: 1.45),
      bodySmall: TextStyle(fontFamily: family, fontSize: 12.5),
      labelLarge: TextStyle(
          fontFamily: family, fontSize: 14, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(
          fontFamily: family, fontSize: 12, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontFamily: family, fontSize: 10.5),
    ),
  );
}