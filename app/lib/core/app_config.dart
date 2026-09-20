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
  static const _kGift = 'cfg_daily_gift';
  static const _kVideoHidden = 'cfg_video_hidden';
  static const _kVideoHiddenMsg = 'cfg_video_hidden_msg';
  static const _kChatWriteScope = 'cfg_chat_write_scope';
  static const _kChatReadOnly = 'cfg_chat_read_only';

  // لا رابط مثبت في الكود: الوجهة يحددها المالك من لوحته فقط. رابط مثبت
  // سابقاً كان يوجّه المستخدمين لحساب آخر عند تعطّل الشبكة أو نسيان الضبط.
  String _telegram = '';
  List<dynamic> _packages = const [];
  int _dailyFree = 5;
  int _dailyGift = 0;
  bool _videosHidden = false;
  String _videosHiddenMessage = '';
  String _chatWriteScope = 'registered';
  bool _chatReadOnly = false;
  String _privacy = '';
  bool _loadedFromCache = false;

  /// رابط تواصل المالك. فارغ يعني أن المالك لم يضبطه بعد.
  String get telegram => _telegram;
  bool get hasTelegram => _telegram.isNotEmpty;
  List<dynamic> get packages => _packages;

  /// المنحة اليومية الواحدة — تُطبَّق على المخططات والتوافقات معاً، ولكل
  /// الأدوار (زائر ومسجّل ومشترك). لا عدّاد ثانٍ ولا عملة ثانية.
  int get dailyFreeQuota => _dailyFree;

  /// عملات هديّة اليوم كما ضبطها المالك. صفر يعني أن الزر لا يظهر أصلاً —
  /// الخادم يرفض المطالبة بهذه القيمة، فلا معنى لإظهاره معطّلاً.
  int get dailyGift => _dailyGift;
  bool get hasGift => _dailyGift > 0;

  /// مفتاح المالك لإيقاف الفيديوهات. حين يكون مفعّلاً لا يبني الخادم أي رابط
  /// بثّ إطلاقاً، وهذه القيمة تُستخدم لعرض سبب التوقف بدل مؤشر تحميل أبدي.
  bool get videosHidden => _videosHidden;
  String get videosHiddenMessage => _videosHiddenMessage;

  /// هل يسمح المالك للزوار بالكتابة في الدردشة؟
  ///
  /// الواجهة كانت ترفض الزائر دائماً بحجّة «أنشئ حساباً»، ولو اختار المالك
  /// «الجميع» في اللوحة. القرار هنا يتبع إعداد المالك لا حالة الحساب.
  bool get guestsCanChat => _chatWriteScope == 'all' && !_chatReadOnly;
  bool get chatReadOnly => _chatReadOnly;
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
    _dailyGift = p.getInt(_kGift) ?? 0;
    _videosHidden = p.getBool(_kVideoHidden) ?? false;
    _videosHiddenMessage = p.getString(_kVideoHiddenMsg) ?? '';
    _chatWriteScope = p.getString(_kChatWriteScope) ?? 'registered';
    _chatReadOnly = p.getBool(_kChatReadOnly) ?? false;
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
    final gift = (s['dailyGiftAmount'] as num?)?.toInt() ?? _dailyGift;
    // القيمة القادمة من الخادم هي المرجع؛ إن غابت نُبقي آخر قيمة معروفة كي
    // لا يعود الفيديو للظهور بخطأ شبكة عابر أثناء الإيقاف.
    final hidden = s.containsKey('videosHidden')
        ? s['videosHidden'] == true : _videosHidden;
    final hiddenMsg = (s['videosHiddenMessage'] ?? '').toString();
    // إعداد الدردشة يأتي من الخادم؛ وإن غاب نُبقي آخر قيمة معروفة كي لا
    // يرتد الزائر عن الكتابة بسبب ردّ قديم أو شبكة عابرة.
    final scope = (s['chatWriteScope'] ?? '').toString();
    final readOnly = s.containsKey('chatReadOnly')
        ? s['chatReadOnly'] == true : _chatReadOnly;
    await _apply(tg: tg, packages: pk, dailyFree: quota, privacy: privacy,
        dailyGift: gift, videosHidden: hidden, videosHiddenMessage: hiddenMsg,
        chatWriteScope: scope.isEmpty ? _chatWriteScope : scope,
        chatReadOnly: readOnly);
  }

  /// بعد حفظ المالك للإعدادات، يُحدَّث فوراً بلا انتظار دورة تحديث.
  Future<void> applyOwnerSettings({
    String? telegram,
    List<dynamic>? packages,
    int? dailyFree,
    int? dailyGift,
    bool? videosHidden,
    String? videosHiddenMessage,
    String? privacy,
    String? chatWriteScope,
    bool? chatReadOnly,
  }) =>
      _apply(
          tg: telegram ?? _telegram,
          packages: packages ?? _packages,
          dailyFree: dailyFree ?? _dailyFree,
          dailyGift: dailyGift ?? _dailyGift,
          videosHidden: videosHidden ?? _videosHidden,
          videosHiddenMessage: videosHiddenMessage ?? _videosHiddenMessage,
          chatWriteScope: chatWriteScope ?? _chatWriteScope,
          chatReadOnly: chatReadOnly ?? _chatReadOnly,
          privacy: privacy ?? _privacy);

  Future<void> _apply({
    required String tg,
    required List<dynamic> packages,
    required int dailyFree,
    required int dailyGift,
    required bool videosHidden,
    required String videosHiddenMessage,
    String? chatWriteScope,
    bool? chatReadOnly,
    required String privacy,
  }) async {
    // رابط فارغ من الخادم لا يمحو رابطاً صالحاً محفوظاً.
    final nextTg = tg.trim().isEmpty ? _telegram : tg.trim();
    // سياسة فارغة كذلك: لو نسي المالك الضبط يبقى النص المحفوظ بدل صندوق فارغ.
    final nextPrivacy = privacy.trim().isEmpty ? _privacy : privacy;
    // رسالة الإيقاف الفارغة لا تمحو رسالة سابقة: نُبقيها كما كتبها المالك.
    final nextHiddenMsg = videosHiddenMessage.trim().isEmpty
        ? _videosHiddenMessage : videosHiddenMessage.trim();
    final nextScope = chatWriteScope ?? _chatWriteScope;
    final nextReadOnly = chatReadOnly ?? _chatReadOnly;
    final changed = nextTg != _telegram ||
        nextScope != _chatWriteScope ||
        nextReadOnly != _chatReadOnly ||
        nextPrivacy != _privacy ||
        !listEquals(_pkgKeys(packages), _pkgKeys(_packages)) ||
        dailyFree != _dailyFree ||
        dailyGift != _dailyGift ||
        videosHidden != _videosHidden ||
        nextHiddenMsg != _videosHiddenMessage;
    _telegram = nextTg;
    _packages = packages;
    _dailyFree = dailyFree;
    _dailyGift = dailyGift;
    _videosHidden = videosHidden;
    _videosHiddenMessage = nextHiddenMsg;
    _chatWriteScope = nextScope;
    _chatReadOnly = nextReadOnly;
    _privacy = nextPrivacy;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kTelegram, _telegram);
    await p.setInt(_kDailyFree, _dailyFree);
    await p.setInt(_kGift, _dailyGift);
    await p.setBool(_kVideoHidden, _videosHidden);
    await p.setString(_kVideoHiddenMsg, _videosHiddenMessage);
    await p.setString(_kPackages, jsonEncode(_packages));
    await p.setString(_kPrivacy, _privacy);
    await p.setString(_kChatWriteScope, _chatWriteScope);
    await p.setBool(_kChatReadOnly, _chatReadOnly);

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
