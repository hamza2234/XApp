import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import 'theme.dart';
import 'brand_logo.dart';
import 'compat_brand_screen.dart';
import 'subscribe_dialog.dart';
import 'external_link.dart';

/// شاشة التوافقات — لوحة إعلانات أعلى + شبكة الشركات (توافقات نصية فقط)
class CompatScreen extends StatefulWidget {
  const CompatScreen({super.key, required this.api});
  final Api api;

  @override
  State<CompatScreen> createState() => _CompatScreenState();
}

class _CompatScreenState extends State<CompatScreen>
    with AutomaticKeepAliveClientMixin {
  List<CompatBrand>? _brands;
  List<Announcement> _ads = [];
  String? _error;
  bool _locked = false;
  String _filter = '';

  /// ترتيب مخصص: إنفنكس أولاً ثم الكبار ثم الفرعيات ثم الباقي أبجدياً
  static const _priority = [
    'infinix', 'honor', 'huawei', 'samsung',
    'oppo', 'poco', 'redmi', 'realme', 'vivo',
  ];

  int _brandOrder(CompatBrand a, CompatBrand b) {
    int rank(CompatBrand x) {
      final i = _priority.indexOf(x.displayName.toLowerCase());
      return i < 0 ? 100 : i;
    }
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : a.displayName.compareTo(b.displayName);
  }
  final _pageCtrl = PageController(viewportFraction: .92);
  int _adIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.compatBrands(),
        widget.api.bootstrap(),
      ]);
      if (!mounted) return;
      setState(() {
        _brands = (results[0] as List)
            .map((e) => CompatBrand.fromJson(e))
            .toList()
          ..sort(_brandOrder);
        _ads = (((results[1] as Map)['announcements'] as List?) ?? [])
            .map((e) => Announcement.fromJson(e))
            .toList();
        _error = null;
        _locked = false;
      });
      _autoScrollAds();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _locked = e.forbidden;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر تحميل البيانات');
    }
  }

  /// صورة الإعلان — الروابط النسبية /v1/media/ تُحمَّل بطلب موقّع
  Widget _adImage(String url) {
    if (url.startsWith('/')) {
      return Image.network(
        '$kApiBase$url',
        fit: BoxFit.cover,
        headers: widget.api.signFor('GET', url),
        errorBuilder: (_, __, ___) => Container(color: XTheme.surface2),
      );
    }
    return Image.network(url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(color: XTheme.surface2));
  }

  void _autoScrollAds() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 6));
      if (!mounted || _ads.length < 2) return false;
      _adIndex = (_adIndex + 1) % _ads.length;
      if (_pageCtrl.hasClients) {
        _pageCtrl.animateToPage(_adIndex,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut);
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _load,
      color: XTheme.accent,
      child: CustomScrollView(
        slivers: [
          // ── لوحة الإعلانات ──
          if (_ads.isNotEmpty)
            SliverToBoxAdapter(child: _adBanner()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v),
                decoration: InputDecoration(
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
                  Icon(
                      _locked
                          ? Icons.lock_outline
                          : Icons.cloud_off_outlined,
                      size: 48,
                      color: _locked ? XTheme.gold : XTheme.textDim),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: XTheme.textDim)),
                  ),
                  const SizedBox(height: 10),
                  if (_locked)
                    ElevatedButton.icon(
                      onPressed: () => showSubscribeDialog(context),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('تواصل مع المالك'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: XTheme.accent,
                          foregroundColor: Colors.white),
                    )
                  else
                    TextButton(
                        onPressed: _load,
                        child: const Text('إعادة المحاولة')),
                ]),
              ),
            )
          else if (_brands == null)
            SliverFillRemaining(
                child: Center(
                    child: CircularProgressIndicator(color: XTheme.accent)))
          else
            _brandGrid(),
        ],
      ),
    );
  }

  Widget _adBanner() {
    return SizedBox(
      height: 118,
      child: PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _adIndex = i),
        itemCount: _ads.length,
        itemBuilder: (context, i) {
          final ad = _ads[i];
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: GlassCard(
              padding: EdgeInsets.zero,
              onTap: () async {
                if (ad.linkUrl.isNotEmpty) {
                  await openExternal(context, ad.linkUrl);
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ad.imageUrl.isNotEmpty)
                      _adImage(ad.imageUrl)
                    else
                      Container(
                          decoration:
                              BoxDecoration(gradient: XTheme.gradient)),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withOpacity(.72),
                            Colors.transparent
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 16, left: 16, bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ad.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: Colors.white)),
                          if (ad.subtitle.isNotEmpty)
                            Text(ad.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _brandGrid() {
    final list = _brands!
        .where((b) =>
            _filter.isEmpty ||
            b.displayName.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .9),
        delegate: SliverChildBuilderDelegate(
          (context, i) => _brandCard(list[i]),
          childCount: list.length,
        ),
      ),
    );
  }

  Widget _brandCard(CompatBrand b) {
    return GlassCard(
      padding: const EdgeInsets.all(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CompatBrandScreen(api: widget.api, brand: b))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          BrandLogo(name: b.displayName, size: 56),
          const SizedBox(height: 8),
          Text(b.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }
}
