import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// عنصر واحد في شريط التنقل السفلي.
class NavItem {
  const NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// شريط تنقل سفلي حيّ — حركة ولمعان بدل الأيقونات الساكنة.
///
/// الفكرة: مؤشّر متدرّج ينزلق بين التبويبات، والأيقونة النشطة تكبر قليلاً
/// مع هالة توهّج، ولمعة تعبر الشريط عند كل تغيير. كل هذه الحركات تُرسم في
/// طبقات منفصلة عبر `AnimatedBuilder` فلا يُعاد بناء محتوى الشاشة.
///
/// لماذا لا نستخدم `NavigationBar` الجاهز؟ لأنه يثبّت المؤشّر ويحرّكه بلا
/// انزلاق حقيقي بين العناصر. هذا الشريط يمنح التبويب النشط حضوراً بصرياً
/// واضحاً — وهو أول ما يراه المستخدم عند فتح التطبيق.
class AnimatedNavBar extends StatefulWidget {
  const AnimatedNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  State<AnimatedNavBar> createState() => _AnimatedNavBarState();
}

class _AnimatedNavBarState extends State<AnimatedNavBar>
    with TickerProviderStateMixin {
  /// انزلاق المؤشّر بين التبويبات.
  late final AnimationController _slide;

  /// لمعان يعبر الشريط عند كل تغيير تبويب.
  late final AnimationController _sweep;

  /// نبض مستمر خفيف على الأيقونة النشطة — يبقي الشريط حياً بلا إزعاج.
  late final AnimationController _pulse;

  int _from = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.index;
    _slide = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380))
      ..value = 1;
    _sweep = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AnimatedNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
      _slide.forward(from: 0);
      _sweep.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;

    return Container(
      decoration: BoxDecoration(
        color: XTheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(XTheme.isLight ? .10 : .38),
            blurRadius: 22,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Stack(
            children: [
              // طبقة المؤشّر واللمعان — منفصلة عن الأيقونات
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _slide,
                  builder: (context, _) {
                    // حركة انزلاق ناعمة بين العنصرين
                    final t = Curves.easeOutCubic.transform(_slide.value);
                    final pos = _from + (widget.index - _from) * t;
                    return CustomPaint(
                      painter: _NavIndicatorPainter(
                        position: pos,
                        count: n,
                        sweep: _sweep.value,
                        pulse: _pulse.value,
                        light: XTheme.isLight,
                        direction: Directionality.of(context),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: _NavCell(
                        item: widget.items[i],
                        selected: i == widget.index,
                        // نبض متدرّج: التبويب النشط وحده ينبض
                        pulse: _pulse,
                        onTap: () => widget.onSelect(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// خلية تبويب — أيقونة ونص، بتكبير وتوهّج عند التحديد.
class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.pulse,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final Animation<double> pulse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      // لا splash داكن فوق المؤشّر الملوّن
      splashColor: XTheme.accent.withOpacity(.10),
      highlightColor: Colors.transparent,
      child: Center(
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          offset: selected ? const Offset(0, -.06) : Offset.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: pulse,
                builder: (context, child) {
                  // تكبير 1.0 → 1.08 للتبويب النشط فقط
                  final bump = selected ? 1 + pulse.value * .08 : 1.0;
                  return Transform.scale(scale: bump, child: child);
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child: Icon(
                    selected ? item.activeIcon : item.icon,
                    // key لازم ليعرف AnimatedSwitcher أن الأيقونة تغيّرت
                    key: ValueKey('${item.label}-$selected'),
                    size: 24,
                    color: selected ? XTheme.accent : XTheme.textDim,
                    shadows: selected
                        ? [
                            Shadow(
                                color: XTheme.accent.withOpacity(.55),
                                blurRadius: 12),
                          ]
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 240),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? XTheme.accent : XTheme.textDim,
                  fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                ),
                child: Text(item.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مركز المؤشّر الأفقي لتبويب نشط.
///
/// `position` بوحدات العناصر (قد يكون كسرياً أثناء الانزلاق). الاتجاه مهم:
/// في RTL العمود 0 يقع على اليمين لا اليسار، فالمرآة ضرورية وإلا استقر الخط
/// تحت التبويب المعاكس (كان يظهر تحت «الدردشة» عند الضغط على «التوافقات»).
double navIndicatorCenterX(
  double width,
  int count,
  double position,
  TextDirection direction,
) {
  if (count == 0) return 0;
  final cell = width / count;
  final leftBased = cell * (position + .5);
  return direction == TextDirection.rtl ? width - leftBased : leftBased;
}

/// يرسم المؤشّر المنزلق هالةً متدرّجة خلف التبويب النشط، واللمعان العابر.
class _NavIndicatorPainter extends CustomPainter {
  _NavIndicatorPainter({
    required this.position,
    required this.count,
    required this.sweep,
    required this.pulse,
    required this.light,
    required this.direction,
  });

  /// موضع التبويب النشط بوحدات العناصر (قد يكون كسرياً أثناء الانزلاق).
  final double position;
  final int count;

  /// تقدّم اللمعان 0..1 (0 يعني انتهى).
  final double sweep;
  final double pulse;
  final bool light;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final cell = size.width / count;
    final center = navIndicatorCenterX(size.width, count, position, direction);
    // إشارة الاتجاه: تُحرك الجسيمات مع اتجاه القراءة لا عكسه.
    final dir = direction == TextDirection.rtl ? -1.0 : 1.0;

    // ===== هالة متدرّجة خلف التبويب النشط =====
    final haloW = cell * .92;
    final halo = Rect.fromCenter(
      center: Offset(center, size.height * .52),
      width: haloW,
      height: size.height * .74,
    );
    final rrect = RRect.fromRectAndRadius(halo, const Radius.circular(18));

    // التوهّج ينبض بين .10 و .18 — حضور واضح لا إزعاج
    final glow = light ? .10 + pulse * .08 : .16 + pulse * .10;
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            XTheme.accent.withOpacity(glow),
            XTheme.accent2.withOpacity(glow * .7),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ).createShader(halo)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 7 + pulse * 4),
    );

    // ===== نواة ذرّية: مدارات وجسيمات تدور حول التبويب النشط =====
    // `pulse` متحرّك دائماً، فالمدارات لا تتوقف أبداً — حركة مستمرة لا وميض.
    final orbitCenter = Offset(center, size.height * .52);
    for (var o = 0; o < 3; o++) {
      // مدارات بأقطار مختلفة واتجاهات متعاكسة لإحساس ذرّي حقيقي.
      final radius = cell * (.30 + o * .16);
      final spin = pulse * 2 * 3.14159265 * (o.isEven ? 1 : -1) + o * 2.1;
      final ellY = .55 + o * .05;

      // حلقة المدار — باهتة حتى لا تزاحم الأيقونة.
      canvas.drawOval(
        Rect.fromCenter(
          center: orbitCenter,
          width: radius * 2,
          height: radius * 2 * ellY,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = XTheme.accent.withOpacity(light ? .16 : .22),
      );

      // جسيم واحد يدور على كل مدار.
      final p = Offset(
        orbitCenter.dx + dir * radius * _cos(spin),
        orbitCenter.dy + radius * ellY * _sin(spin),
      );
      // وهج خفيف حول الجسيم ثم الجسيم نفسه.
      canvas.drawCircle(
        p,
        2.6,
        Paint()
          ..color = XTheme.accent.withOpacity(light ? .45 : .6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        p,
        1.5,
        Paint()..color = XTheme.accent.withOpacity(.95),
      );
    }

    // خط سفلي رفيع تحت التبويب النشط — يثبّت المؤشّر بصرياً
    final barW = cell * .34;
    final barRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center, size.height - 7),
        width: barW,
        height: 3,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      barRect,
      Paint()
        ..shader = XTheme.gradient.createShader(barRect.outerRect),
    );

    // ===== اللمعان العابر عند تغيير التبويب =====
    if (sweep > 0 && sweep < 1) {
      final x = -cell + (size.width + cell * 2) * sweep;
      final shineW = cell * 1.5;
      final rect = Rect.fromLTWH(x, 0, shineW, size.height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withOpacity(0),
              Colors.white.withOpacity(light ? .28 : .16),
              Colors.white.withOpacity(0),
            ],
          ).createShader(rect)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  @override
  bool shouldRepaint(_NavIndicatorPainter old) =>
      old.position != position ||
      old.sweep != sweep ||
      old.pulse != pulse ||
      old.count != count ||
      old.direction != direction;
}

// دوال مثلثية محلية — تتجنّب استيراد dart:math كلّه من أجل دالتين.
double _sin(double x) => math.sin(x);
double _cos(double x) => math.cos(x);
