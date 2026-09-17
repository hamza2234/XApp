import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'theme.dart';
import 'subscribe_dialog.dart';

/// بحث موديل داخل شركة → يعرض التوافقات النصية مجمّعة حسب نوع القطعة
class CompatBrandScreen extends StatefulWidget {
  const CompatBrandScreen({super.key, required this.api, required this.brand});
  final Api api;
  final CompatBrand brand;

  @override
  State<CompatBrandScreen> createState() => _CompatBrandScreenState();
}

class _CompatBrandScreenState extends State<CompatBrandScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<CompatRecord>? _results;
  bool _loading = false;
  String? _error;
  bool _locked = false;

  static const _types = {
    'SCREEN': ('شاشة', Icons.smartphone, Color(0xFF4D8DFF)),
    'BATTERY': ('بطارية', Icons.battery_full, Color(0xFF2EE6A8)),
    'battery': ('بطارية', Icons.battery_full, Color(0xFF2EE6A8)),
    'GLASS': ('زجاج', Icons.shield_outlined, Color(0xFF8B5CF6)),
    'INCASSABLE': ('ضد الكسر', Icons.verified_outlined, Color(0xFFF5B942)),
  };

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      // لا نتائج قبل الكتابة — صندوق بحث نظيف
      setState(() {
        _results = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.api
          .searchCompat(q.trim(),
              brand: widget.brand.id.startsWith('v_')
                  ? widget.brand.id
                  : widget.brand.file);
      if (!mounted) return;
      setState(() {
        _results =
            list.map((e) => CompatRecord.fromJson(e)).toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
          _locked = e.forbidden;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر البحث';
        });
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.brand.displayName)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _onQuery,
              decoration: InputDecoration(
                hintText: 'اكتب موديل الجهاز… (مثال: A57)',
                prefixIcon:
                    Icon(Icons.search, color: XTheme.textDim),
                suffixIcon: _q.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () {
                          _q.clear();
                          _onQuery('');
                        })
                    : null,
              ),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: XTheme.accent));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_locked ? Icons.lock_outline : Icons.error_outline,
              size: 44, color: _locked ? XTheme.gold : XTheme.danger),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: XTheme.textDim)),
          ),
          if (_locked)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ElevatedButton.icon(
                onPressed: () => showSubscribeDialog(context),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('تواصل مع المالك'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: XTheme.accent,
                    foregroundColor: Colors.white),
              ),
            ),
        ]),
      );
    }
    if (_results == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.manage_search, size: 54,
              color: XTheme.textDim.withOpacity(.5)),
          const SizedBox(height: 10),
          Text('اكتب موديل الجهاز للبحث',
              style: TextStyle(color: XTheme.textDim)),
        ]),
      );
    }
    final list = _results!;
    if (list.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 52, color: XTheme.textDim.withOpacity(.5)),
          const SizedBox(height: 10),
          Text('لا توجد توافقات مطابقة',
              style: TextStyle(color: XTheme.textDim)),
        ]),
      );
    }

    // تجميع حسب نوع القطعة
    final grouped = <String, List<CompatRecord>>{};
    for (final r in list) {
      grouped.putIfAbsent(r.componentType, () => []).add(r);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: grouped.length,
      itemBuilder: (context, gi) {
        final type = grouped.keys.elementAt(gi);
        final recs = grouped[type]!;
        final meta = _types[type] ?? (type, Icons.build_outlined, XTheme.accent);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Row(children: [
                Icon(meta.$2, size: 18, color: meta.$3),
                const SizedBox(width: 8),
                Text(meta.$1,
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: meta.$3,
                        fontSize: 15)),
                const SizedBox(width: 8),
                Text('${recs.length}',
                    style: TextStyle(
                        color: XTheme.textDim, fontSize: 12)),
              ]),
            ),
            ...recs.map(_recordCard),
          ],
        );
      },
    );
  }

  Widget _recordCard(CompatRecord r) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.subCategory != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(r.subCategory!,
                  style: TextStyle(
                      color: XTheme.cyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: r.models
                .map((m) => _modelChip(m))
                .toList(),
          ),
        ],
      ),
    );
  }

  /// رقاقة موديل — تُلوّن الجزء المطابق لكلمة البحث بلون مميز
  Widget _modelChip(String m) {
    final q = _q.text.trim().toLowerCase();
    final match =
        q.isNotEmpty && m.toLowerCase().contains(q);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: match
            ? XTheme.accent.withOpacity(.28)
            : XTheme.accent.withOpacity(.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: match
                ? XTheme.accent.withOpacity(.65)
                : XTheme.accent.withOpacity(.22)),
      ),
      child: Text.rich(_highlighted(m, q),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }

  TextSpan _highlighted(String text, String q) {
    if (q.isEmpty) return TextSpan(text: text);
    final lower = text.toLowerCase();
    final idx = lower.indexOf(q);
    if (idx < 0) return TextSpan(text: text);
    return TextSpan(children: [
      TextSpan(text: text.substring(0, idx)),
      TextSpan(
          text: text.substring(idx, idx + q.length),
          style: TextStyle(
              color: XTheme.accent,
              fontWeight: FontWeight.w900,
              backgroundColor: XTheme.accent.withOpacity(.18))),
      TextSpan(text: text.substring(idx + q.length)),
    ]);
  }
}
