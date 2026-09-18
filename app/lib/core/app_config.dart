import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات عامة مشتركة بين كل الشاشات: رابط تيليجرام والباقات.
///
/// كانت النسخة السابقة تحتفظ برابط تيليجرام في كل شاشة على حدة، وبقيمة
/// افتراضية مثبتة في الكود. لذلك تغيير المالك للرابط لم يكن يصل لحوار
/// الاشتراك ولا بعض المسارات. الآن مصدر واحد، محفوظ محلياً ليُستخدم فوراً
/// عند الإقلاع، ومنعش من الخادم.
class AppConfig extends ChangeNotifier {
  AppConfig._();

  static final AppConfig instance = AppConfig._();

  static const _kTelegram = 'cfg_telegram';
  static const _kPackages = 'cfg_packages';
  static const _kDailyFree = 'cfg_daily_free';
  static const _kPrivacy = 'cfg_privacy';

  // لا رابط مثبت في الكود: الوجهة يحددها المالك من لوحته فقط. رابط مثبت
  // سابقاً كان يوجّه المستخدمين لحساب آخر عند تعطّل الشبكة أو نسيان الضبط.
  String _telegram = '';
  List<dynamic> _packages = const [];
  int _dailyFree = 5;
  String _privacy = '';
  bool _loadedFromCache = false;

  /// رابط تواصل المالك. فارغ يعني أن المالك لم يضبطه بعد.
  String get telegram => _telegram;
  bool get hasTelegram => _telegram.isNotEmpty;
  List<dynamic> get packages => _packages;

  /// المنحة اليومية الواحدة — تُطبَّق على المخططات والتوافقات معاً، ولكل
  /// الأدوار (زائر ومسجّل ومشترك). لا عدّاد ثانٍ ولا عملة ثانية.
  int get dailyFreeQuota => _dailyFree;
  bool get loadedFromCache => _loadedFromCache;

  /// سياسة الخصوصية كما كتبها المالك. نص فارغ يعني لم يضبطها بعد.
  String get privacyPolicy => _privacy;
  bool get hasPrivacy => _privacy.trim().isNotEmpty;

  /// يُحمّل من الذاكرة المحلية — يعمل بلا شبكة ويسد فجوة أول تشغيل.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _telegram = p.getString(_kTelegram) ?? '';
    _privacy = p.getString(_kPrivacy) ?? '';
    _dailyFree = p.getInt(_kDailyFree) ?? 5;
    final raw = p.getString(_kPackages);
    if (raw != null) {
      try {
        _packages = _decodePackages(raw);
      } catch (_) {
        _packages = const [];
      }
    }
    _loadedFromCache = true;
    notifyListeners();
  }

  /// يحدّث من ردّ `/v1/bootstrap` الذي جلبه المستدعي أصلاً.
  /// إن كان الردّ بلا إعدادات، تبقى القيم المحفوظة بلا تغيير.
  Future<void> applyBootstrap(Map<String, dynamic>? boot) async {
    final s = boot?['settings'];
    if (s is! Map) return;
    final tg = (s['telegramLink'] ?? '').toString().trim();
    final pk = s['packages'] is List ? s['packages'] as List : _packages;
    // الخادم الجديد يرسل dailyFreeQuota؛ والقديم يرسل الحقلين المنفصلين
    // فأخذ الأكبر يحفظ ما اعتاده المالك حتى بعد التحديث.
    final legacy = [
      (s['guestFileQuota'] as num?)?.toInt(),
      (s['guestCompatQuota'] as num?)?.toInt(),
    ].whereType<int>();
    final quota = (s['dailyFreeQuota'] as num?)?.toInt() ??
        (legacy.isEmpty ? _dailyFree : legacy.reduce((a, b) => a > b ? a : b));
    final privacy = (s['privacyPolicy'] ?? '').toString();
    await _apply(tg: tg, packages: pk, dailyFree: quota, privacy: privacy);
  }

  /// بعد حفظ المالك للإعدادات، يُحدَّث فوراً بلا انتظار دورة تحديث.
  Future<void> applyOwnerSettings({
    String? telegram,
    List<dynamic>? packages,
    int? dailyFree,
    String? privacy,
  }) =>
      _apply(
          tg: telegram ?? _telegram,
          packages: packages ?? _packages,
          dailyFree: dailyFree ?? _dailyFree,
          privacy: privacy ?? _privacy);

  Future<void> _apply({
    required String tg,
    required List<dynamic> packages,
    required int dailyFree,
    required String privacy,
  }) async {
    // رابط فارغ من الخادم لا يمحو رابطاً صالحاً محفوظاً.
    final nextTg = tg.trim().isEmpty ? _telegram : tg.trim();
    // سياسة فارغة كذلك: لو نسي المالك الضبط يبقى النص المحفوظ بدل صندوق فارغ.
    final nextPrivacy = privacy.trim().isEmpty ? _privacy : privacy;
    final changed = nextTg != _telegram ||
        nextPrivacy != _privacy ||
        !listEquals(_pkgKeys(packages), _pkgKeys(_packages)) ||
        dailyFree != _dailyFree;
    _telegram = nextTg;
    _packages = packages;
    _dailyFree = dailyFree;
    _privacy = nextPrivacy;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kTelegram, _telegram);
    await p.setInt(_kDailyFree, _dailyFree);
    await p.setString(_kPackages, jsonEncode(_packages));
    await p.setString(_kPrivacy, _privacy);

    if (changed) notifyListeners();
  }

  static List<String> _pkgKeys(List<dynamic> packages) => [
        for (final e in packages)
          if (e is Map) '${e['cards']}|${e['price']}|${e['days']}'
      ];

  static List<dynamic> _decodePackages(String raw) {
    final v = jsonDecode(raw);
    return v is List ? v : const [];
  }

  void reset() {
    _telegram = '';
    _packages = const [];
    notifyListeners();
  }
}
