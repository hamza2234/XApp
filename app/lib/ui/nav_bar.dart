
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

/// شريط تنقل سفلي زجاجي — انزلاق ولمعان بلا ذرّات ولا هالة.
///
/// الفكرة: مؤشّر زجاجي شفّاف ينزلق بين التبويبات، ولمعة تعبر الشريط عند كل
/// تغيير. كل هذه الحركات تُرسم في طبقات منفصلة عبر `AnimatedBuilder` فلا
/// يُعاد بناء محتوى الشاشة.
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

/// خلية تبويب — أيقونة ونص، بتكبير بسيط عند التحديد بلا توهّج.
class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
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
              // بلا ظل ولا نبض: الأيقونة النشطة تُميَّز باللون والحجم وحدهما.
              AnimatedSwitcher(
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

/// يرسم اللوح الزجاجي خلف التبويب النشط، واللمعان العابر عند التغيير.
class _NavIndicatorPainter extends CustomPainter {
  _NavIndicatorPainter({
    required this.position,
    required this.count,
    required this.sweep,
    required this.light,
    required this.direction,
  });

  /// موضع التبويب النشط بوحدات العناصر (قد يكون كسرياً أثناء الانزلاق).
  final double position;
  final int count;

  /// تقدّم اللمعان 0..1 (0 يعني انتهى).
  final double sweep;
  final bool light;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;
    final cell = size.width / count;
    final center = navIndicatorCenterX(size.width, count, position, direction);

    // ===== لوح زجاجي فوق التبويب النشط =====
    // الطلب: «معنان زجاج فقط» بلا ذرّات ولا مدارات. الزجاج هنا طبقة بيضاء
    // شبه شفافة داخل حدّ فاتح — تعطي عمقاً بلا أي توهّج حول الأيقونة.
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center, size.height * .52),
        width: cell * .70,
        height: size.height * .60,
      ),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      pill,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withOpacity(light ? .55 : .13),
            Colors.white.withOpacity(light ? .16 : .04),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(pill.outerRect),
    );
    // حدّ فاتح رفيع: يقرأ العينُ الحافةَ زجاجاً لا بقعةَ لون.
    canvas.drawRRect(
      pill,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withOpacity(light ? .75 : .16),
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
      old.count != count ||
      old.direction != direction;
}
