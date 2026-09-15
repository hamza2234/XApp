import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'theme.dart';
import 'browser_screen.dart';

/// شاشة المخططات — شبكة الشركات (من كتالوج R2 بترتيبه الأصلي)
class SchemScreen extends StatefulWidget {
  const SchemScreen({super.key, required this.api, required this.onFileOpened});
  final Api api;
  final VoidCallback onFileOpened;

  @override
  State<SchemScreen> createState() => _SchemScreenState();
}

class _SchemScreenState extends State<SchemScreen>
    with AutomaticKeepAliveClientMixin {
  List<SchemBrand>? _brands;
  String? _error;
  String _filter = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.schemBrands();
      if (!mounted) return;
      setState(() {
        _brands = list.map((e) => SchemBrand.fromJson(e)).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل الشركات');
    }
  }

  static const _icons = {
    'iphone': Icons.apple,
    'samsung': Icons.phone_android,
    'huawei': Icons.smartphone,
    'infinix': Icons.smartphone_outlined,
    'itel': Icons.phone_iphone,
    'tecno': Icons.phonelink,
    'vivo': Icons.smartphone,
    'realme': Icons.phone_android_outlined,
    'mi': Icons.smartphone,
    'redmi': Icons.smartphone_outlined,
    'poco': Icons.phonelink_outlined,
    'black shark': Icons.sports_esports,
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      color: XTheme.accent,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                decoration: const InputDecoration(
                  hintText: 'ابحث عن شركة…',
                  prefixIcon: Icon(Icons.search, color: XTheme.textDim),
                  isDense: true,
                ),
              ),
            ),
          ),
          if (_error != null)
            SliverFillRemaining(
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, color: XTheme.gold, size: 44),
              const SizedBox(height: 12),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: XTheme.textDim))),
              TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
            ])))
          else if (_brands == null)
            const SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(color: XTheme.accent)))
          else
            _grid(),
        ],
      ),
    );
  }

  Widget _grid() {
    final list = _brands!
        .where((b) =>
            _filter.isEmpty ||
            b.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .9),
        delegate: SliverChildBuilderDelegate((context, i) {
          final b = list[i];
          final icon =
              _icons[b.name.toLowerCase()] ?? Icons.folder_special_outlined;
          return GlassCard(
            padding: const EdgeInsets.all(10),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BrowserScreen(
                    api: widget.api,
                    brand: b,
                    onFileOpened: widget.onFileOpened))),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: XTheme.cyan.withOpacity(.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: XTheme.cyan, size: 24),
                ),
                const SizedBox(height: 8),
                Text(b.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5)),
              ],
            ),
          );
        }, childCount: list.length),
      ),
    );
  }
}
