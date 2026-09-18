import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// تخزين محلي آمن للجلسة والجهاز.
/// التوكن والهوية لا تغادران الجهاز إلا عبر الطلبات الموقّعة.
class Store {
  Store._(this._p);
  final SharedPreferences _p;

  static Future<Store> init() async =>
      Store._(await SharedPreferences.getInstance());

  static const _kDevice = 'x_device_id';
  static const _kToken = 'x_token';
  static const _kUser = 'x_user';
  static const _kInstallSent = 'x_install_sent';

  /// هوية الجهاز — تُولَّد مرة واحدة وتبقى ثابتة (تُستخدم للتوقيع والحصص).
  String get deviceId {
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
