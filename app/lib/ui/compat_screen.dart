import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import 'theme.dart';
import 'compat_brand_screen.dart';
import 'subscribe_dialog.dart';

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
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
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
                        style: const TextStyle(color: XTheme.textDim)),
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
            const SliverFillRemaining(
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
                  final uri = Uri.parse(ad.linkUrl);
                  if (await canLaunchUrl(uri)) launchUrl(uri);
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
                              const BoxDecoration(gradient: XTheme.gradient)),
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

  static const _brandColors = {
    'xiaomi': Color(0xFFFF6900), 'realme': Color(0xFFFFC915),
    'huawei': Color(0xFFCF0A2C), 'samsung': Color(0xFF1428A0),
    'infinix': Color(0xFF44B979), 'itel': Color(0xFF00A8E8),
    'tecno': Color(0xFF005EB8), 'vivo': Color(0xFF415FFF),
    'oppo': Color(0xFF2D683D), 'nokia': Color(0xFF0065A3),
    'oneplus': Color(0xFFEB0028), 'sony': Color(0xFF8A8A8A),
    'meizu': Color(0xFF008DEB), 'zte': Color(0xFF0A50A0),
    'google': Color(0xFF4285F4), 'reno': Color(0xFF2D683D),
    'motorola': Color(0xFF5B92E5),
  };

  Widget _brandCard(CompatBrand b) {
    final color = _brandColors[b.displayName.toLowerCase()] ??
        XTheme.accent2;
    return GlassCard(
      padding: const EdgeInsets.all(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CompatBrandScreen(api: widget.api, brand: b))),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: color.withOpacity(.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                b.displayName.isEmpty ? '?' : b.displayName[0].toUpperCase(),
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, color: color),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(b.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13)),
          Text('${b.models} موديل',
              style: const TextStyle(color: XTheme.textDim, fontSize: 10)),
        ],
      ),
    );
  }
}
