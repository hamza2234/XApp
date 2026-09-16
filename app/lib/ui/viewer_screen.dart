import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'theme.dart';
import 'subscribe_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
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
      return PdfViewer.data(_bytes!,
          sourceName: widget.entry.cleanName,
          params: const PdfViewerParams(
            backgroundColor: Colors.black,
            panEnabled: true,
            scaleEnabled: true,
            maxScale: 8,
          ));
    }
    // صورة — تكبير حر
    return InteractiveViewer(
      maxScale: 12,
      minScale: .4,
      child: Center(
        child: Image.memory(_bytes!, fit: BoxFit.contain),
      ),
    );
  }
}
