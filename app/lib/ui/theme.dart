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

  // فاتح (أبيض)
  static const _lBg = Color(0xFFF4F6FB);
  static const _lSurface = Color(0xFFFFFFFF);
  static const _lSurface2 = Color(0xFFECEFF6);
  static const _lText = Color(0xFF141A2A);
  static const _lTextDim = Color(0xFF5D6679);

  static Color bg = _dBg;
  static Color surface = _dSurface;
  static Color surface2 = _dSurface2;
  static Color text = _dText;
  static Color textDim = _dTextDim;

  static const accent = Color(0xFF4D8DFF);
  static const accent2 = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF22D3EE);
  static const gold = Color(0xFFF5B942);
  static const danger = Color(0xFFFF5470);
  static const ok = Color(0xFF2EE6A8);

  static const gradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
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
      textTheme: GoogleFonts.tajawalTextTheme(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: TextStyle(color: textDim),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: accent, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      iconTheme: IconThemeData(color: text),
      dividerColor: textDim.withOpacity(.2),
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

/// بطاقة زجاجية متدرجة الحواف
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding, this.onTap});
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: XTheme.surface.withOpacity(.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: (XTheme.isLight ? Colors.black : Colors.white)
                .withOpacity(.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }
}
