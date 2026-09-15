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

  Future<void> clearSession() async {
    await _p.remove(_kToken);
    await _p.remove(_kUser);
  }
}
