import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'theme.dart';
import 'brand_logo.dart';
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
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث عن شركة…',
                  prefixIcon: Icon(Icons.search_rounded,
                      color: XTheme.textDim, size: 21),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 19, color: XTheme.textDim),
                          onPressed: () {
                            setState(() => _filter = '');
                            FocusScope.of(context).unfocus();
                          },
                        ),
                  isDense: true,
                ),
              ),
            ),
          ),
          if (_error != null)
            SliverFillRemaining(
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 84, height: 84,
                decoration: BoxDecoration(
                  color: XTheme.gold.withOpacity(.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: XTheme.gold.withOpacity(.24)),
                ),
                child: const Icon(Icons.lock_outline,
                    color: XTheme.gold, size: 36),
              ),
              const SizedBox(height: 16),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: XTheme.textDim,
                          height: 1.6,
                          fontSize: 13.5))),
              const SizedBox(height: 12),
              TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة المحاولة')),
            ])))
          else if (_brands == null)
            SliverFillRemaining(
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
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: XTheme.isLight
                        ? Colors.white
                        : Colors.white.withOpacity(.06),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: XTheme.textDim.withOpacity(.12)),
                  ),
                  child: BrandLogo(name: b.name, size: 46),
                ),
                const SizedBox(height: 9),
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
