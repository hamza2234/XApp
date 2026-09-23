import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// تخزين محلي آمن للجلسة والجهاز.
/// التوكن والهوية لا تغادران الجهاز إلا عبر الطلبات الموقّعة.
class Store {
  Store._(this._p, this._fingerprint);
  final SharedPreferences _p;

  static const _channel = MethodChannel('x_app/device');

  /// بصمة الجهاز الأصلية (ANDROID_ID) — تُقرأ من النظام لا من بيانات التطبيق.
  final String? _fingerprint;

  static Future<Store> init() async {
    final p = await SharedPreferences.getInstance();
    return Store._(p, await _readFingerprint());
  }

  static Future<String?> _readFingerprint() async {
    try {
      final fp = await _channel.invokeMethod<String>('fingerprint');
      final v = (fp ?? '').trim().toLowerCase();
      return RegExp(r'^[0-9a-f]{16,64}$').hasMatch(v) ? v : null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // اختبارات Dart بلا قناة أصلية — الحصص تُفرض على الخادم في كل حال.
      return null;
    }
  }

  static const _kDevice = 'x_device_id';
  static const _kToken = 'x_token';
  static const _kUser = 'x_user';
  static const _kInstallSent = 'x_install_sent';
  static const _kOwnerToken = 'x_owner_token';
  static const _kOwnerTokenAt = 'x_owner_token_at';

  /// ── هوية التثبيت ومفتاح التوقيع ──
  ///
  /// لماذا مفتاح لكل تثبيت بدل سرّ مضمّن في الحزمة: السرّ المضمّن واحد
  /// لكل النسخ، فمن استخرجه من الحزمة وقّع أي طلب من أي مكان، ولا سبيل
  /// لإبطاله إلا بتحديث الجميع. هنا يولّد التطبيق زوج مفاتيح Ed25519 محلياً،
  /// يبقى الخاص على الجهاز ولا يُرسل أبداً، ويرسل العام مرة واحدة. تسريب
  /// الحزمة كلها لا يمنح أحداً مفتاح تثبيت غيره، والإبطال صار لكل تثبيت.
  static const _kInstallId = 'x_install_id';
  static const _kSignSeed = 'x_sign_seed';
  static const _kSignPub = 'x_sign_pub';

  /// معرّف التثبيت — عشوائي ومحلي، لا يُشتق من الجهاز.
  ///
  /// لماذا لا البصمة: إعادة تثبيت التطبيق تولّد مفتاحاً جديداً، فلو كان
  /// المعرّف ثابتاً لاصطدم المفتاح الجديد بالمسجَّل ورُفض التسجيل. معرّف
  /// عشوائي لكل تثبيت يجعل كل تثبيت وحدة مستقلة بمفتاحها — وربط الجهاز
  /// يبقى على `deviceId` كما هو، فلا يفقد المالك قدرته على حظر جهاز.
  String get installId {
    var id = _p.getString(_kInstallId);
    if (id == null) {
      id = const Uuid().v4().replaceAll('-', '').substring(0, 24);
      _p.setString(_kInstallId, id);
    }
    return id;
  }

  /// البذرة المفكوكة — في الذاكرة بعد `warmSignKey`، ولا تُقرأ من التخزين
  /// في كل توقيع (فكّ Keystore عملية ثقيلة).
  String? get signSeed => _seedCache;

  /// بادئة تدلّ أن القيمة لم تُغلَّف — تُستعمل في الاختبارات وسطح المكتب
  /// حيث لا Keystore. على أندرويد لا تُكتب هذه البادئة أبداً.
  static const _plainPrefix = 'plain:';

  /// المفتاح العام المسجَّل — سداسي عشري، أو null إن لم يُولَّد بعد.
  String? get signPublicKey => _p.getString(_kSignPub);

  bool get installKeySent => _p.getBool(_kInstallSent) ?? false;
  Future<void> markInstallKeySent() => _p.setBool(_kInstallSent, true);

  /// يضمن وجود زوج مفاتيح ويعيد (البذرة، المفتاح العام).
  ///
  /// التوليد مرة واحدة: وجود البذرة يعني زوجاً قائماً، فلا يُولَّد غيره —
  /// وإلا تغيّر المفتاح العام وصار كل توقيع سابق باطلاً.
  Future<({String seed, String publicKey})> ensureSignKey(
      Future<({String seed, String publicKey})> Function() generate) async {
    final existingSeed = _seedCache;
    final existingPub = signPublicKey;
    if (existingSeed != null && existingPub != null) {
      return (seed: existingSeed, publicKey: existingPub);
    }
    final made = await generate();
    _seedCache = made.seed;
    await _p.setString(_kSignSeed, await _seal(made.seed));
    await _p.setString(_kSignPub, made.publicKey);
    return made;
  }

  /// التغليف يُنفَّذ على المنصة: المفتاح الرئيسي لا يغادر Keystore.
  Future<String> _seal(String value) async {
    try {
      final out = await _channel.invokeMethod<String>('sealSecret', {'value': value});
      if (out != null && out.isNotEmpty) return out;
    } catch (_) {
      // لا قناة أصلية (اختبارات) — نكتب نصّاً بادئته تدلّ عليه.
    }
    return '$_plainPrefix$value';
  }

  String? _seedCache;

  /// يفكّ البذرة مرة واحدة عند الإقلاع ويحفظها في الذاكرة.
  Future<void> warmSignKey() async {
    final sealed = _p.getString(_kSignSeed);
    if (sealed == null) return;
    if (sealed.startsWith(_plainPrefix)) {
      _seedCache = sealed.substring(_plainPrefix.length);
      return;
    }
    try {
      final plain = await _channel
          .invokeMethod<String>('unsealSecret', {'value': sealed});
      if (plain != null && plain.isNotEmpty) _seedCache = plain;
    } catch (_) {
      // فشل الفكّ يعني مفتاحاً تالفاً أو Keystore مُصفَّراً: يُعاد التوليد
      // عند الطلب التالي، فلا يبقى التطبيق عالقاً بلا توقيع.
    }
  }

  /// بصمة الجهاز للتوقيع وربط المنحة — فارغة إن لم تتوفر.
  String get fingerprint => _fingerprint ?? '';

  /// هوية الجهاز: البصمة الأصلية أولاً كي تبقى بعد مسح البيانات، وإلا
  /// المعرّف المخزَّن (نسخ/أجهزة بلا بصمة) ثم معرّف جديد يُولَّد مرة واحدة.
  String get deviceId {
    final fp = _fingerprint;
    if (fp != null) return fp;
    var id = _p.getString(_kDevice);
    if (id == null) {
      id = const Uuid().v4().replaceAll('-', '').substring(0, 24);
      _p.setString(_kDevice, id);
    }
    return id;
  }

  String? get token => _p.getString(_kToken);
  Future<void> setToken(String? t) async =>
      t == null ? _p.remove(_kToken) : _p.setString(_kToken, t);

  Map<String, dynamic>? get user {
    final raw = _p.getString(_kUser);
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> setUser(Map<String, dynamic>? u) async =>
      u == null ? _p.remove(_kUser) : _p.setString(_kUser, jsonEncode(u));

  bool get installSent => _p.getBool(_kInstallSent) ?? false;
  Future<void> markInstallSent() => _p.setBool(_kInstallSent, true);

  bool get isGuest => (user?['role'] ?? 'guest') == 'guest';
  bool get isOwner => user?['role'] == 'owner';
  bool get hasSession => token != null;

  /// جلسة المالك — منفصلة تماماً عن جلسة المستخدم.
  ///
  /// لماذا منفصلة؟ لأن جلسة المالك توقّعها الخادم بسرّ مستقل وتحمل
  /// `typ=owner`، فسرقتها لا تفيد مهاجماً يحاول التظاهر بحساب عادي،
  /// وسرقة جلسة عادية لا تفتح اللوحة. تنتهي بعد 12 ساعة ويُطلب الدخول
  /// من جديد — فترة قصيرة مقصودة لأخطر حساب في النظام.
  String? get ownerToken {
    final t = _p.getString(_kOwnerToken);
    if (t == null) return null;
    final at = _p.getInt(_kOwnerTokenAt) ?? 0;
    // انتهاء محلي عند 12 ساعة مطابق لعمر الرمز على الخادم.
    if (DateTime.now().millisecondsSinceEpoch - at > 12 * 3600 * 1000) return null;
    return t;
  }

  Future<void> setOwnerToken(String? t) async {
    if (t == null) {
      await _p.remove(_kOwnerToken);
      await _p.remove(_kOwnerTokenAt);
    } else {
      await _p.setString(_kOwnerToken, t);
      await _p.setInt(
          _kOwnerTokenAt, DateTime.now().millisecondsSinceEpoch);
    }
  }

  bool get hasOwnerSession => ownerToken != null;

  /// إنهاء جلسة اللوحة من داخل اللوحة نفسها.
  ///
  /// ثابتة لأن قسم أمان اللوحة لا يحمل نسخة من `Store`؛ والجلسة كلها في
  /// `SharedPreferences`، فمحوها لا يحتاج كائن التخزين.
  static Future<void> clearOwnerSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kOwnerToken);
    await p.remove(_kOwnerTokenAt);
    await p.remove(_kOwnerUnlockAt);
  }

  /// ختم زمني لآخر فتح ناجح للوحة المالك — يُستخدم لقفل البصمة.
  static const _kOwnerUnlockAt = 'x_owner_unlock_at';

  int get ownerUnlockedAt => _p.getInt(_kOwnerUnlockAt) ?? 0;
  Future<void> markOwnerUnlocked() => _p.setInt(
      _kOwnerUnlockAt, DateTime.now().millisecondsSinceEpoch);

  static const _kCompatDay = 'x_compat_day';
  static const _kCompatUsed = 'x_compat_used';

  /// عدّاد بحوث التوافقات المجانية لليوم الحالي.
  ///
  /// هذا فرض على الجهاز، لا على الخادم. وجوده لأن الخادم المنشور لا يفرض
  /// حصة التوافقات إطلاقاً، فبدونه يستطيع الزائر سحب كل التوافقات مجاناً.
  /// حين يُنشر الخادم المحصّن يتقدّم فرضه على هذا تلقائياً، لأن كل رد يحمل
  /// `remaining` الحقيقي. فائدتان هنا: منع السحب المجاني فوراً، ومنع إغراق
  /// الشبكة بطلبات مرفوضة.
  int compatUsedToday() {
    if (_p.getString(_kCompatDay) != _today()) return 0;
    return _p.getInt(_kCompatUsed) ?? 0;
  }

  /// يسجّل بحثاً استُهلك من حصة اليوم. يُعيد عدد ما تبقّى.
  Future<int> recordCompatSearch(int limit) async {
    final used = compatUsedToday() + 1;
    await _p.setString(_kCompatDay, _today());
    await _p.setInt(_kCompatUsed, used);
    final left = limit - used;
    return left < 0 ? 0 : left;
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> clearSession() async {
    await _p.remove(_kToken);
    await _p.remove(_kUser);
  }
}
