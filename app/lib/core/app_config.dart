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
  static const _kQuota = 'cfg_guest_quota';

  // لا رابط مثبت في الكود: الوجهة يحددها المالك من لوحته فقط. رابط مثبت
  // سابقاً كان يوجّه المستخدمين لحساب آخر عند تعطّل الشبكة أو نسيان الضبط.
  String _telegram = '';
  List<dynamic> _packages = const [];
  int _guestQuota = 5;
  bool _loadedFromCache = false;

  /// رابط تواصل المالك. فارغ يعني أن المالك لم يضبطه بعد.
  String get telegram => _telegram;
  bool get hasTelegram => _telegram.isNotEmpty;
  List<dynamic> get packages => _packages;
  int get guestQuota => _guestQuota;
  bool get loadedFromCache => _loadedFromCache;

  /// يُحمّل من الذاكرة المحلية — يعمل بلا شبكة ويسد فجوة أول تشغيل.
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _telegram = p.getString(_kTelegram) ?? '';
    _guestQuota = p.getInt(_kQuota) ?? 5;
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
    final quota = (s['guestFileQuota'] as num?)?.toInt() ?? _guestQuota;
    await _apply(tg: tg, packages: pk, guestQuota: quota);
  }

  /// بعد حفظ المالك للإعدادات، يُحدَّث فوراً بلا انتظار دورة تحديث.
  Future<void> applyOwnerSettings({
    String? telegram,
    List<dynamic>? packages,
    int? guestQuota,
  }) =>
      _apply(
          tg: telegram ?? _telegram,
          packages: packages ?? _packages,
          guestQuota: guestQuota ?? _guestQuota);

  Future<void> _apply({
    required String tg,
    required List<dynamic> packages,
    required int guestQuota,
  }) async {
    // رابط فارغ من الخادم لا يمحو رابطاً صالحاً محفوظاً.
    final nextTg = tg.trim().isEmpty ? _telegram : tg.trim();
    final changed = nextTg != _telegram ||
        !listEquals(_pkgKeys(packages), _pkgKeys(_packages)) ||
        guestQuota != _guestQuota;
    _telegram = nextTg;
    _packages = packages;
    _guestQuota = guestQuota;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kTelegram, _telegram);
    await p.setInt(_kQuota, _guestQuota);
    await p.setString(_kPackages, jsonEncode(_packages));

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
