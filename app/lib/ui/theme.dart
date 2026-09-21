import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// هوية X البصرية — داكنة/فاتحة بتدرجات نيون.
class XTheme {
  // داكن (افتراضي)
  static const _dBg = Color(0xFF0B0E17);
  static const _dSurface = Color(0xFF131826);
  static const _dSurface2 = Color(0xFF1B2236);
  static const _dText = Color(0xFFEAEEF7);
  static const _dTextDim = Color(0xFF8A93A8);

  // فاتح (أبيض) — خلفية رمادية فاتحة حتى تبرز البطاقات البيضاء
  static const _lBg = Color(0xFFEDF0F7);
  static const _lSurface = Color(0xFFFFFFFF);
  static const _lSurface2 = Color(0xFFE4E8F2);
  static const _lText = Color(0xFF10141F);
  static const _lTextDim = Color(0xFF4E576C);

  // تبدأ داكنة: الوضع الافتراضي في التطبيق داكن. تهيئة الحالة الثابتة
  // تسبق قراءة تفضيل المستخدم، فالقيمة هنا تحدد ما يُعرض في أول إطار.
  static Color bg = _dBg;
  static Color surface = _dSurface;
  static Color surface2 = _dSurface2;
  static Color text = _dText;
  static Color textDim = _dTextDim;

  static const accent = Color(0xFFFF7A18);      // برتقالي دافئ — هوية التطبيق
  static const accent2 = Color(0xFFFFB020);     // كهرماني
  static const cyan = Color(0xFF22D3EE);
  static const gold = Color(0xFFF5B942);
  static const danger = Color(0xFFFF5470);
  static const ok = Color(0xFF2EE6A8);

  static const gradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  /// تدرّج بارد للعناصر المعلوماتية (الأمان، السجل، الحالات المحايدة) —
  /// يفصلها بصرياً عن البرتقالي الذي يعني «إجراء».
  static const coolGradient = LinearGradient(
    colors: [Color(0xFF22D3EE), Color(0xFF6366F1)],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  /// نصف قطر موحّد — كل الحواف في التطبيق من هنا، فلا تتنافر الأرقام.
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 26;

  /// ظل ناعم متدرّج حسب الثيم. الظل الثقيل في الوضع الفاتح يبدو متسخاً،
  /// وفي الداكن يبدو حلقة رمادية — فلكل وضع قيمه.
  static List<BoxShadow> shadow({double lift = 1}) => isLight
      ? [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(.05 * lift),
            blurRadius: 10 * lift,
            offset: Offset(0, 3 * lift),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(.04 * lift),
            blurRadius: 24 * lift,
            offset: Offset(0, 10 * lift),
          ),
        ]
      : [
          BoxShadow(
            color: Colors.black.withOpacity(.34 * lift),
            blurRadius: 16 * lift,
            offset: Offset(0, 6 * lift),
          ),
        ];

  /// توهّج ملوّن — للعناصر النشطة فقط (الزر الرئيسي، الشريحة المحددة).
  /// هالة ضوئية ناعمة.
  ///
  /// الشفافية والضباب يتناسبان مع القوة، والضباب مسقوف: الظل المُضبَّب
  /// يُرسم على وحدة الرسوم في كل إطار، وضباب واسع داخل عنصر متحرّك يُسقط
  /// الإطارات على الأجهزة الضعيفة. السقف يحفظ النعومة بلا هذا الثمن.
  static List<BoxShadow> glow(Color c, {double strength = 1}) => [
        BoxShadow(
          color: c.withOpacity((isLight ? .20 : .30) * strength),
          blurRadius: (14 * strength).clamp(4.0, 18.0),
          offset: Offset(0, 5 * strength),
        ),
      ];

  /// تعبئة زجاجية للبطاقات الداخلية — تدرّج خفيف بدل لون مسطّح.
  static BoxDecoration panel({double radius = rLg, Color? tint}) =>
      BoxDecoration(
        gradient: LinearGradient(
          colors: isLight
              ? [surface, surface2.withOpacity(.55)]
              : [surface2.withOpacity(.72), surface.withOpacity(.42)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: (tint ?? (isLight ? Colors.black : Colors.white))
              .withOpacity(isLight ? .07 : .08),
        ),
      );

  static bool isLight = false;

  static void apply(bool light) {
    isLight = light;
    if (light) {
      bg = _lBg; surface = _lSurface; surface2 = _lSurface2;
      text = _lText; textDim = _lTextDim;
    } else {
      bg = _dBg; surface = _dSurface; surface2 = _dSurface2;
      text = _dText; textDim = _dTextDim;
    }
  }

  static ThemeData theme() {
    final light = isLight;
    return ThemeData(
      useMaterial3: true,
      brightness: light ? Brightness.light : Brightness.dark,
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(
          (light ? ThemeData.light() : ThemeData.dark())
              .textTheme
              .apply(bodyColor: text, displayColor: text)),
      colorScheme: (light
              ? const ColorScheme.light()
              : const ColorScheme.dark())
          .copyWith(
        surface: surface,
        primary: accent,
        secondary: accent2,
        error: danger,
        onSurface: text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: text),
        iconTheme: IconThemeData(color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: TextStyle(color: textDim, fontSize: 14),
        labelStyle: TextStyle(color: textDim),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(rMd),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(rMd),
            borderSide: BorderSide(
                color: (light ? Colors.black : Colors.white).withOpacity(.06))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(rMd),
            borderSide: const BorderSide(color: accent, width: 1.6)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: accent.withOpacity(.18),
        labelTextStyle: WidgetStateProperty.all(
            TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: text)),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: surface),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: TextStyle(
            color: text, fontSize: 13.5, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rXl)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(rXl))),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          textStyle:
              const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        side: BorderSide.none,
        labelStyle: TextStyle(
            color: text, fontSize: 12, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rSm)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: textDim,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
      listTileTheme: ListTileThemeData(
        iconColor: textDim,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rMd)),
      ),
      iconTheme: IconThemeData(color: text),
      dividerColor: textDim.withOpacity(.2),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}

/// متحكّم الثيم — يحفظ الاختيار ويُبلغ التطبيق
class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._();
  ThemeController._();

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    XTheme.apply(p.getBool('light_theme') ?? false);
    notifyListeners();
  }

  Future<void> setLight(bool light) async {
    XTheme.apply(light);
    final p = await SharedPreferences.getInstance();
    await p.setBool('light_theme', light);
    notifyListeners();
  }

  bool get isLight => XTheme.isLight;
}

/// بطاقة زجاجية متدرجة الحواف — الوحدة البصرية الأساسية في التطبيق.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.accent,
    this.radius = XTheme.rLg,
  });

  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  /// لون شريط جانبي رفيع — يميّز البطاقة بلا زخرفة زائدة.
  final Color? accent;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      decoration: XTheme.panel(radius: radius, tint: accent),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          splashColor: (accent ?? XTheme.accent).withOpacity(.07),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );

    final shadowed = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: XTheme.shadow(),
      ),
      child: inner,
    );

    if (accent == null) return shadowed;
    // الشريط الجانبي يُرسم داخل حدود البطاقة نفسها فلا يزيح المحتوى.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          shadowed,
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            child: Container(width: 3.5, color: accent),
          ),
        ],
      ),
    );
  }
}

/// عنوان قسم — سطر واحد بوزن ثقيل وخط سفلي متدرّج قصير.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                gradient: XTheme.gradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w900)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// شريحة حالة ملوّنة — للحالات (نشط، موقوف، منتهي) بدل نص عارٍ.
class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.13),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11.5, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
