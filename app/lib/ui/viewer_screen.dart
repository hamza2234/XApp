import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'theme.dart';
import 'subscribe_dialog.dart';
import 'secure_screen.dart';

/// عارض الملفات داخل التطبيق — PDF و PNG/صور، مع تكبير كامل.
/// الملف يُحمَّل عبر طلب موقّع فقط — لا روابط عامة.
class ViewerScreen extends StatefulWidget {
  const ViewerScreen(
      {super.key,
      required this.api,
      required this.entry,
      required this.onOpened});
  final Api api;
  final SchemEntry entry;
  final VoidCallback onOpened;

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  Uint8List? _bytes;
  String? _error;
  bool _quotaOut = false;

  /// عامل التكبير للصور — يُدار بأنفسنا لندعم الزوم اللانهائي فعلاً:
  /// إن دفع المستخدم إصبعيه إلى أقصى الحدّ نرفع السقف بدل أن يتوقّف.
  final TransformationController _imgCtrl = TransformationController();
  double _imgMaxScale = 20;

  @override
  void initState() {
    super.initState();
    // حجب التقاط الشاشة طوال بقاء المخطط مفتوحاً، ويُرفع عند الخروج.
    SecureScreen.on();
    _imgCtrl.addListener(_growZoomIfNeeded);
    _load();
  }

  @override
  void dispose() {
    SecureScreen.off();
    _imgCtrl.removeListener(_growZoomIfNeeded);
    _imgCtrl.dispose();
    super.dispose();
  }

  /// يرفع سقف التكبير تلقائياً عند بلوغ الحدّ.
  ///
  /// مخططات الأجهزة تفاصيلها دقيقة (مسارات وأرقام قطع)، وحدّ ثابت يمنع
  /// تكبير جزء صغير لقراءته. هنا كلما بلغ المستخدم السقف رُفع ضعفاً، فيقترب
  /// من تفصيل دقيق بلا سقف عملي — مع بقاء الأداء سليماً لأن الصورة تُرسم
  /// مُكبَّرة لا تُعاد قراءتها.
  void _growZoomIfNeeded() {
    if (!mounted) return;
    final s = _imgCtrl.value.getMaxScaleOnAxis();
    if (s > _imgMaxScale * .98) {
      setState(() => _imgMaxScale = _imgMaxScale * 2);
    }
  }

  Future<void> _load() async {
    try {
      final res = await widget.api
          .getBytes('/v1/file/${Uri.encodeComponent(widget.entry.id)}');
      if (!mounted) return;
      setState(() => _bytes = res.bytes);
      widget.onOpened();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _quotaOut = e.quotaExhausted;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر فتح الملف');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.entry.cleanName,
            style: const TextStyle(fontSize: 14)),
        backgroundColor: XTheme.surface,
        actions: [
          IconButton(
            tooltip: 'تصغير',
            icon: const Icon(Icons.zoom_out, size: 20),
            onPressed: () {
              final s = _imgCtrl.value.getMaxScaleOnAxis();
              final t = (s / 1.6).clamp(1.0, _imgMaxScale);
              _imgCtrl.value = Matrix4.identity()..scaleByDouble(t, t, t, 1);
            },
          ),
          IconButton(
            tooltip: 'تكبير',
            icon: const Icon(Icons.zoom_in, size: 20),
            onPressed: () {
              final s = _imgCtrl.value.getMaxScaleOnAxis();
              final t = (s * 1.6).clamp(1.0, _imgMaxScale);
              _imgCtrl.value = Matrix4.identity()..scaleByDouble(t, t, t, 1);
            },
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                _quotaOut
                    ? Icons.workspace_premium_outlined
                    : Icons.error_outline,
                size: 52,
                color: _quotaOut ? XTheme.gold : XTheme.danger),
            const SizedBox(height: 14),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: XTheme.text, fontSize: 15)),
            const SizedBox(height: 18),
            if (_quotaOut)
              ElevatedButton.icon(
                onPressed: () => showSubscribeDialog(context),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('تواصل مع المالك'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: XTheme.accent,
                    foregroundColor: Colors.white),
              )
            else
              TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
          ]),
        ),
      );
    }
    if (_bytes == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: XTheme.accent),
          SizedBox(height: 14),
          Text('جاري فتح الملف…',
              style: TextStyle(color: XTheme.textDim)),
        ]),
      );
    }
    if (widget.entry.isPdf) {
      // سقف التكبير مرتفع جداً للمخططات: التفاصيل (أرقام القطع والمسارات)
      // لا تُقرأ على التكبير العادي. 60× مقصود — المخططات الهندسية تُقرأ
      // بالاقتراب الشديد، وحدّ 8× السابق كان يجعل النص غير مقروء.
      return PdfViewer.data(_bytes!,
          sourceName: widget.entry.cleanName,
          params: const PdfViewerParams(
            backgroundColor: Colors.black,
            panEnabled: true,
            scaleEnabled: true,
            sizeDelegateProvider:
                PdfViewerSizeDelegateProviderLegacy(maxScale: 60, minScale: .5),
          ));
    }
    // صورة — تكبير بسقف متزايد: كلما بلغ المستخدم الحدّ رُفع تلقائياً،
    // فيقترب من أي تفصيل بلا سقف عملي.
    return InteractiveViewer(
      transformationController: _imgCtrl,
      maxScale: _imgMaxScale,
      minScale: .2,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      child: Center(
        child: Image.memory(_bytes!, fit: BoxFit.contain),
      ),
    );
  }
}
