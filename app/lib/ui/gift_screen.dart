/// تبويب الهديّة — عجلة دوّارة بشكل فقط، لا حظّ فيها.
///
/// الفرق جوهري وأمني: العجلة هنا ليست مولّد عشوائي يُقرّر الجائزة. المبلغ
/// يقرّره المالك في اللوحة، والخادم يمنحه مرة واحدة في اليوم لكل محفظة. العجلة
/// ترسم هذا القرار الثابت بإحساس لعبة، ثم تستقرّ على القيمة نفسها — فلا يمكن
/// للعميل تعديل المبلغ ولا تكرار المنح، ولا معنى لمحاولة الغش لأن القرار لم
/// يكن في العجلة أصلاً.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class GiftScreen extends StatefulWidget {
  const GiftScreen({
    super.key,
    required this.amount,
    required this.claimed,
    required this.nextAt,
    required this.balance,
    required this.onClaim,
  });

  /// المبلغ الذي يمنحه الخادم اليوم. صفر أو أقل يعني أن الهديّة معطّلة.
  final int amount;

  /// هل استُلمت هديّة اليوم؟ يأتي من الخادم لا من تخمين محلي.
  final bool claimed;

  /// لحظة فتح هديّة الغد (ms منذ الحقبة). صفر = غير معروف، فلا عدّاد.
  final int nextAt;

  /// الرصيد الحالي — يُعرض ليظهر أثر الهديّة فوراً.
  final int balance;

  /// يطلب المنح من الخادم ويعيد النتيجة: نجاحاً بمبلغ، أو خطأً برسالة.
  final Future<GiftClaimResult> Function() onClaim;

  @override
  State<GiftScreen> createState() => _GiftScreenState();
}

/// نتيجة محاولة الاستلام كما تراها الواجهة.
class GiftClaimResult {
  const GiftClaimResult({required this.ok, this.amount = 0, this.message = ''});

  final bool ok;
  final int amount;
  final String message;
}

class _GiftScreenState extends State<GiftScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  /// زاوية العجلة المتراكمة. تُجمع ولا تُصفَّر، فالدورة التالية تكمل من حيث
  /// استقرّت بدل أن تقفز إلى الصفر فتبدو كأنها ارتدّت.
  double _angle = 0;

  /// الحالة الظاهرة الآن، منفصلة عن الوسائط: بعد نجاح الاستلام تبقى الهديّة
  /// معلّمة كمستلمة ولو لم يصل تحديث الأب بعد.
  late bool _claimed = widget.claimed;
  late int _amount = widget.amount;
  late int _balance = widget.balance;
  bool _busy = false;

  Timer? _tick;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(covariant GiftScreen old) {
    super.didUpdateWidget(old);
    // تحديث الخادم يتقدّم على الحالة المحلية: إن قال إن هديّة جديدة فُتحت
    // نُعيد الزر، وإن تأكّد الاستلام نُبقيه مغلقاً.
    if (widget.amount != old.amount ||
        widget.claimed != old.claimed ||
        widget.nextAt != old.nextAt ||
        widget.balance != old.balance) {
      setState(() {
        _amount = widget.amount;
        _claimed = widget.claimed;
        _balance = widget.balance;
      });
      _syncCountdown();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _spin.dispose();
    super.dispose();
  }

  /// يضبط العدّاد التنازلي. لا عدّاد بلا موعد معروف من الخادم: عرض وقت مخمّن
  /// أسوأ من عدم عرضه، لأن المستخدم سينتظر لحظة لا تفتح فيها الهديّة.
  void _syncCountdown() {
    _tick?.cancel();
    if (widget.nextAt <= 0) {
      _left = Duration.zero;
      return;
    }
    void step() {
      final ms = widget.nextAt - DateTime.now().millisecondsSinceEpoch;
      if (!mounted) return;
      setState(() => _left = ms > 0 ? Duration(milliseconds: ms) : Duration.zero);
      // انتهى الوقت: نطلب تحديثاً من الأب لجلب الرصيد والحالة الجديدة، بدل
      // أن نفتح الزر محلياً ثم يرفض الخادم عند الضغط.
      if (ms <= 0) {
        _tick?.cancel();
      }
    }

    step();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => step());
  }

  bool get _disabled => _busy || _amount <= 0;

  /// الضغط: ندير العجلة ونطلب المنح في التوازي.
  ///
  /// العجلة تدور مدة ثابتة بينما يصل ردّ الخادم، ثم تستقرّ على المبلغ الذي
  /// قرّره الخادم — لا مبلغ اختاره العميل. لو رفض الخادم (استُلمت اليوم مثلاً)
  /// تتوقف العجلة في مكانها ولا يُعلن أي ربح.
  Future<void> _spinAndClaim() async {
    if (_disabled || _claimed) return;
    setState(() => _busy = true);

    // دورتان كاملتان + ربع: وقفة أخيرة واضحة بدل توقّف مفاجئ في منتصف دورة.
    final turns = 2 * 2 * math.pi + math.pi / 2;
    final future = widget.onClaim();
    final animation = _spin.forward(from: 0);

    // ننتظر الاثنين معاً: لا نُعلن نتيجة قبل أن تستقرّ العجلة، ولا نُطيل
    // الدوران لو ردّ الخادم فوراً.
    final results = await Future.wait<Object?>([future, animation.then((_) => null)]);
    final r = results.first as GiftClaimResult;
    if (!mounted) return;

    setState(() {
      _busy = false;
      _angle += turns;
      if (r.ok) {
        _claimed = true;
        _balance += r.amount;
        _amount = widget.amount;
      }
    });

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(r.ok
            ? 'حصلت على ${r.amount} عملة هديّة اليوم'
            : (r.message.isEmpty ? 'تعذّر استلام الهديّة' : r.message)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: r.ok ? XTheme.ok.withOpacity(.9) : XTheme.danger,
      ));
    _syncCountdown();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          _header(),
          const SizedBox(height: 22),
          Center(child: _wheel()),
          const SizedBox(height: 22),
          _statusCard(),
          const SizedBox(height: 14),
          _claimButton(),
          if (_claimed && widget.nextAt > 0) ...[
            const SizedBox(height: 18),
            _countdown(),
          ],
          const SizedBox(height: 18),
          _notes(),
        ],
      ),
    );
  }

  Widget _header() => Column(children: [
        Text('هديّة اليوم',
            style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.w900, color: XTheme.text)),
        const SizedBox(height: 6),
        Text('دور واحد كل يوم — القيمة يحدّدها المالك مسبقاً',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: XTheme.textDim)),
      ]);

  /// العجلة المرسومة. القطاعات متساوية بصرياً لأن العجلة شكل لا قرعة: لا
  /// يوجد قطاع «أفضل» من غيره، فلا يُضلّل الشكل المستخدم.
  Widget _wheel() {
    const size = 240.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        AnimatedBuilder(
          animation: _spin,
          builder: (_, __) {
            // `Curves.easeOutCubic` يعطي تباطؤاً طبيعياً في آخر الدوران.
            final t = Curves.easeOutCubic.transform(_spin.value);
            final turns = 2 * 2 * math.pi + math.pi / 2;
            final a = _angle + turns * t;
            return Transform.rotate(
              angle: a,
              child: CustomPaint(
                size: const Size(size, size),
                painter: _WheelPainter(segments: 8),
              ),
            );
          },
        ),
        // المؤشّر أعلى العجلة، ثابت لا يدور معها.
        Positioned(
          top: 0,
          child: Icon(Icons.arrow_drop_down,
              size: 40, color: XTheme.gold.withOpacity(.95)),
        ),
        // القرص المركزي: يحمل المبلغ، فهو معلوم ومكتوب — لا مفاجأة.
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: XTheme.surface,
            border: Border.all(color: XTheme.gold.withOpacity(.55), width: 2),
            boxShadow: XTheme.glow(XTheme.gold, strength: .5),
          ),
          alignment: Alignment.center,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$_amount',
                style: const TextStyle(
                    fontSize: 25, fontWeight: FontWeight.w900, color: XTheme.gold)),
            Text('عملة',
                style: TextStyle(fontSize: 11, color: XTheme.textDim)),
          ]),
        ),
      ]),
    );
  }

  Widget _statusCard() => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: XTheme.surface,
          borderRadius: BorderRadius.circular(XTheme.rLg),
          border: Border.all(color: XTheme.textDim.withOpacity(.16)),
        ),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: XTheme.gold.withOpacity(.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.account_balance_wallet_outlined,
                color: XTheme.gold, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('رصيدك الحالي',
                  style: TextStyle(fontSize: 12, color: XTheme.textDim)),
              const SizedBox(height: 2),
              Text('$_balance عملة',
                  style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                      color: XTheme.text)),
            ]),
          ),
          if (_claimed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: XTheme.ok.withOpacity(.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.check_circle, size: 14, color: XTheme.ok),
                const SizedBox(width: 5),
                Text('استُلمت اليوم',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: XTheme.ok)),
              ]),
            ),
        ]),
      );

  Widget _claimButton() {
    final enabled = !_disabled && !_claimed;
    final label = _amount <= 0
        ? 'الهديّة معطّلة حالياً'
        : _claimed
            ? 'استلمت هديّة اليوم'
            : (_busy ? 'تدور العجلة…' : 'أدِر العجلة واستلم');
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? _spinAndClaim : null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          backgroundColor: enabled ? XTheme.gold : XTheme.surface2,
          foregroundColor: enabled ? Colors.black : XTheme.textDim,
          disabledBackgroundColor: XTheme.surface2,
          disabledForegroundColor: XTheme.textDim,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(XTheme.rLg)),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900)),
      ),
    );
  }

  /// العدّاد التنازلي حتى هديّة الغد. يظهر بعد الاستلام فقط لأنه لا معنى له
  /// قبلها، ويُبنى على موعد الخادم لا على عدّ محلي من منتصف الليل.
  Widget _countdown() {
    final total = _left.inSeconds;
    final h = (total ~/ 3600).toString().padLeft(2, '0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    final done = total <= 0;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          XTheme.gold.withOpacity(.14),
          XTheme.accent.withOpacity(.08),
        ]),
        borderRadius: BorderRadius.circular(XTheme.rLg),
        border: Border.all(color: XTheme.gold.withOpacity(.3)),
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(done ? Icons.celebration_outlined : Icons.schedule,
              size: 17, color: XTheme.gold),
          const SizedBox(width: 7),
          Text(done ? 'هديّة جديدة صارت متاحة' : 'تُفتح هديّة الغد بعد',
              style: TextStyle(
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                  color: XTheme.text)),
        ]),
        if (!done) ...[
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _timeBox(h, 'ساعة'),
            const SizedBox(width: 8),
            _timeBox(m, 'دقيقة'),
            const SizedBox(width: 8),
            _timeBox(s, 'ثانية'),
          ]),
        ],
      ]),
    );
  }

  Widget _timeBox(String value, String unit) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: XTheme.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: XTheme.textDim.withOpacity(.2)),
        ),
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: XTheme.text,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          Text(unit, style: TextStyle(fontSize: 9.5, color: XTheme.textDim)),
        ]),
      );

  Widget _notes() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: XTheme.surface2,
          borderRadius: BorderRadius.circular(XTheme.rMd),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _note(Icons.lock_outline, 'القيمة يحدّدها المالك ولا يمكن تغييرها من هنا'),
          const SizedBox(height: 7),
          _note(Icons.event_available_outlined, 'مرة واحدة فقط كل يوم لكل جهاز'),
          const SizedBox(height: 7),
          _note(Icons.savings_outlined, 'العملات تُضاف لرصيدك وتُخصم من حدّك اليومي'),
        ]),
      );

  Widget _note(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: XTheme.textDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 11.8, color: XTheme.textDim, height: 1.45)),
          ),
        ],
      );
}

/// يرسم قطاعات العجلة بألوان هوية التطبيق.
class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.segments});

  final int segments;

  /// الألوان تتناوب بين درجات الهوية، فلا يوجد قطاع مميّز يوهم بجائزة.
  static const _colors = [
    Color(0xFFFF7A18),
    Color(0xFF1B2236),
    Color(0xFFF5B942),
    Color(0xFF131826),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final sweep = 2 * math.pi / segments;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < segments; i++) {
      paint.color = _colors[i % _colors.length];
      canvas.drawArc(rect, i * sweep, sweep, true, paint);
    }
    // حلقة خارجية تفصل العجلة عن الخلفية وتشدّ الشكل.
    canvas.drawArc(
      rect.deflate(1),
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = const Color(0xFFF5B942).withOpacity(.7),
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.segments != segments;
}
