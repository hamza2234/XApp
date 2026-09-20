import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'theme.dart';
import 'brand_logo.dart';
import 'compat_brand_screen.dart';
import 'subscribe_dialog.dart';
import 'external_link.dart';

/// شاشة التوافقات — لوحة إعلانات أعلى + شبكة الشركات (توافقات نصية فقط)
class CompatScreen extends StatefulWidget {
  const CompatScreen({super.key, required this.api, this.store, this.onCharged});
  final Api api;
  final Store? store;

  /// يُنادى بعد أي خصم داخل شاشات التوافقات. بلا هذا يبقى الشريط العلوي
  /// يعرض رصيداً قديماً حتى إعادة تشغيل التطبيق — لأن الخصم يقع في شاشة
  /// فرعية لا تعرف الشريط، بخلاف المخططات التي مرّرت `refreshQuota`.
  final VoidCallback? onCharged;

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
    'infinix', 'tecno', 'honor', 'huawei', 'samsung',
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
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث عن شركة…',
                  prefixIcon:
                      Icon(Icons.search_rounded, color: XTheme.textDim, size: 21),
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
      height: 148,
      child: Column(
        children: [
          Expanded(
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
                      borderRadius: BorderRadius.circular(XTheme.rLg),
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
                                  Colors.black.withOpacity(.74),
                                  Colors.black.withOpacity(.10),
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                            ),
                          ),
                          Positioned(
                            right: 16, left: 16, bottom: 13,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(ad.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: Colors.white)),
                                if (ad.subtitle.isNotEmpty)
                                  Text(ad.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12)),
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
          ),
          // نقاط المؤشّر: بلاها لا يعرف المستخدم أن هناك إعلانات أخرى
          if (_ads.length > 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _ads.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      // النقطة النشطة أعرض — تمييز بلا لون إضافي
                      width: i == _adIndex ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        gradient: i == _adIndex ? XTheme.gradient : null,
                        color: i == _adIndex
                            ? null
                            : XTheme.textDim.withOpacity(.35),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
        ],
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
          builder: (_) =>
              CompatBrandScreen(api: widget.api, brand: b, store: widget.store,
                  onCharged: widget.onCharged))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // الشعار في حاوية مستديرة فاتحة — يفصل الشعارات الفاتحة عن
          // خلفية البطاقة بلا إطار ثقيل.
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
            child: BrandLogo(name: b.displayName, size: 46),
          ),
          const SizedBox(height: 9),
          Text(b.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 12.5)),
        ],
      ),
    );
  }
}
