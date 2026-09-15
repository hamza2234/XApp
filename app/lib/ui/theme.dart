import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// هوية X البصرية — داكنة، حديثة، بتدرجات نيون.
class XTheme {
  static const bg = Color(0xFF0B0E17);
  static const surface = Color(0xFF131826);
  static const surface2 = Color(0xFF1B2236);
  static const accent = Color(0xFF4D8DFF);
  static const accent2 = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF22D3EE);
  static const gold = Color(0xFFF5B942);
  static const danger = Color(0xFFFF5470);
  static const ok = Color(0xFF2EE6A8);
  static const text = Color(0xFFEAEEF7);
  static const textDim = Color(0xFF8A93A8);

  static const gradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topRight,
    end: Alignment.bottomLeft,
  );

  static ThemeData dark() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        textTheme: GoogleFonts.tajawalTextTheme(
            ThemeData.dark().textTheme.apply(
                bodyColor: text, displayColor: text)),
        colorScheme: const ColorScheme.dark(
          surface: surface,
          primary: accent,
          secondary: accent2,
          error: danger,
          onSurface: text,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle:
              TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text),
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface2,
          hintStyle: const TextStyle(color: textDim),
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
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: surface),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surface2,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
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
        border: Border.all(color: Colors.white.withOpacity(.06)),
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
