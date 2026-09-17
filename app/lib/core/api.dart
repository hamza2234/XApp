import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';
import 'store.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  bool get quotaExhausted => status == 429 || status == 402;
  bool get forbidden => status == 403;

  /// الخادم المنشور لا يعرف نقطة البحث المحصّنة بعد (نسخة قديمة).
  /// تُعرض للمستخدم رسالة مفهومة بدل خطأ عام غامض.
  bool get serverOutdated => status == 404;
  bool get updateRequired => status == 426;
  @override
  String toString() => message;
}

/// عميل HTTP يوقّع كل طلب بـ HMAC-SHA256 ويربطه بالجهاز والإصدار.
/// لا تُرسل أي طلبات خارج Worker التطبيق.
class Api {
  Api(this.store);
  final Store store;

  /// ترويسات توقيع جاهزة — تُستخدم لتحميل الصور الموقّعة (إعلانات المالك)
  Map<String, String> signFor(String method, String pathWithQuery) =>
      _sign(method, pathWithQuery);

  Map<String, String> _sign(String method, String pathWithQuery) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = '${store.deviceId}|$ts|$method|$pathWithQuery';
    final sig = Hmac(sha256, utf8.encode(SigKey.secret))
        .convert(utf8.encode(payload))
        .toString();
    return {
      'x-device-id': store.deviceId,
      'x-app-ts': ts,
      'x-app-sig': sig,
      'x-app-version': '$kAppVersion',
      'User-Agent': 'X-App/$kAppVersionName',
      if (store.token != null) 'Authorization': 'Bearer ${store.token}',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(kApiBase);
    return Uri(
        scheme: base.scheme,
        host: base.host,
        path: path,
        queryParameters: query);
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, String>? query}) async {
    final uri = _uri(path, query);
    final pq = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final res = await http
        .get(uri, headers: _sign('GET', pq))
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {Map<String, String>? query}) async {
    final uri = _uri(path, query);
    final pq = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final res = await http
        .post(uri,
            headers: {..._sign('POST', pq), 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) =>
      _send('PUT', path, body);
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path, null);

  Future<Map<String, dynamic>> _send(
      String method, String path, Map<String, dynamic>? body) async {
    final uri = _uri(path);
    final res = await (switch (method) {
      'PUT' => http.put(uri,
          headers: {..._sign('PUT', uri.path), 'Content-Type': 'application/json'},
          body: body == null ? null : jsonEncode(body)),
      'DELETE' => http.delete(uri, headers: _sign('DELETE', uri.path)),
      _ => throw ArgumentError(method),
    }).timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  /// تحميل ملف (PDF/PNG) موقّع ومشفّر — يُفك هنا فقط داخل التطبيق.
  Future<({Uint8List bytes, int quotaLeft, String contentType})> getBytes(
      String path) async {
    final uri = _uri(path);
    final res = await http
        .get(uri, headers: _sign('GET', uri.path))
        .timeout(const Duration(minutes: 3));
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, _errMsg(res));
    }
    var bytes = res.bodyBytes;
    var contentType = res.headers['content-type'] ?? '';

    // فك AES-CTR — الخادم يخدم الملفات مشفرة دائماً
    if (res.headers['x-enc'] == 'aes-ctr') {
      final nonceHex = res.headers['x-enc-nonce'] ?? '';
      final nonce = Uint8List.fromList(List<int>.generate(nonceHex.length ~/ 2,
          (i) => int.parse(nonceHex.substring(i * 2, i * 2 + 2), radix: 16)));
      final algo =
          cg.AesCtr.with256bits(macAlgorithm: cg.MacAlgorithm.empty);
      final box = cg.SecretBox(bytes, nonce: nonce, mac: cg.Mac.empty);
      bytes = Uint8List.fromList(
          await algo.decrypt(box, secretKey: cg.SecretKey(FileKey.bytes)));
      contentType = res.headers['x-orig-type'] ?? 'application/octet-stream';
    }
    return (
      bytes: bytes,
      quotaLeft: int.tryParse(res.headers['x-quota-remaining'] ?? '') ?? -1,
      contentType: contentType,
    );
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        return {'ok': true};
      }
    }
    throw ApiException(res.statusCode, _errMsg(res));
  }

  String _errMsg(http.Response res) {
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      return j['error']?.toString() ?? 'خطأ ${res.statusCode}';
    } catch (_) {
      return 'خطأ في الاتصال (${res.statusCode})';
    }
  }

  // ===== واجهات جاهزة =====

  Future<Map<String, dynamic>> bootstrap() => get('/v1/bootstrap');

  Future<void> registerInstall() => post('/v1/install', {
        'installId': store.deviceId,
        'appVersion': '$kAppVersion',
      });

  Future<Map<String, dynamic>> guest() => post('/v1/auth/guest', {});

  Future<Map<String, dynamic>> login(String username, String password) =>
      post('/v1/auth/login', {'username': username, 'password': password});

  Future<Map<String, dynamic>> register(
          String username, String password, String displayName, String note) =>
      post('/v1/auth/register', {
        'username': username,
        'password': password,
        'displayName': displayName,
        'note': note,
      });

  Future<Map<String, dynamic>> me() => get('/v1/me');

  Future<List<dynamic>> compatBrands() async =>
      (await get('/v1/data/brands'))['brands'] as List;

  /// بحث التوافقات — يتم على الخادم داخل نطاق الشركة والنوع.
  /// لا نجلب ملف الشركة كاملاً بعد الآن: كان ذلك ~65KB و0.9 ثانية لكل دخول،
  /// وهو ما كان يسبب إحساس «تحميل كل التوافقات»، وكان يسمح بسحب البيانات.
  /// يُعيد السجلات + أنواع القطع المتوفرة + ما إذا خُصمت عملة.
  Future<CompatSearchResult> searchCompatCharged(String q,
      {String? brand, String? type}) async {
    final body = <String, dynamic>{'q': q};
    if (brand != null && brand.isNotEmpty) body['brand'] = brand;
    if (type != null && type.isNotEmpty) body['type'] = type;
    // بلا مسار تراجع إلى القراءة العامة: كان يمنح كل السجلات بلا خصم
    // عند أي 404، فيُبطل نظام العملات كله.
    final j = await post('/v1/data/compat/search', body);
    return CompatSearchResult(
      records: (j['records'] as List?) ?? const [],
      types: ((j['types'] as List?) ?? const []).map((e) => '$e').toList(),
      charged: j['charged'] == true,
      remaining: (j['remaining'] as num?)?.toInt() ?? -1,
    );
  }

  Future<List<dynamic>> searchCompat(String q,
      {String? brand, String? type}) async {
    final r = await searchCompatCharged(q, brand: brand, type: type);
    return r.records;
  }

  /// كل سجلات شركة واحدة — حُذفت: القراءة الكاملة صارت مرفوضة على الخادم
  /// (استعلام فارغ = 400) لأنها كانت تسمح بسحب كل التوافقات مجاناً.

  Future<List<dynamic>> schemBrands() async =>
      (await get('/v1/schem/brands'))['brands'] as List;

  Future<List<dynamic>> schemModels(String brandId, {String q = ''}) async =>
      (await get('/v1/schem/brands/${Uri.encodeComponent(brandId)}/models',
          query: q.isEmpty ? null : {'q': q}))['models'] as List;

  Future<List<dynamic>> schemFiles(String folderId) async =>
      (await get(
              '/v1/schem/folders/${Uri.encodeComponent(folderId)}/files'))['files']
          as List;

  // ===== المالك =====
  Future<Map<String, dynamic>> ownerOverview() => get('/v1/owner/overview');
  Future<Map<String, dynamic>> ownerSettings() => get('/v1/owner/settings');
  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> s) =>
      put('/v1/owner/settings', s);
  Future<List<dynamic>> ownerUsers() async =>
      (await get('/v1/owner/users'))['users'] as List;
  Future<List<dynamic>> ownerRequests() async =>
      (await get('/v1/owner/requests'))['requests'] as List;
  /// سجل الأمان — الهجمات فقط افتراضياً، و`all` يكشف كل الأحداث.
  Future<List<dynamic>> ownerSecurity({bool all = false}) async =>
      (await get('/v1/owner/security', query: all ? {'all': '1'} : null))['events']
          as List;
  Future<void> userAction(String id, String action, {int? days}) =>
      post('/v1/owner/users/$id/$action', {if (days != null) 'days': days});
  Future<void> requestAction(String id, String action) =>
      post('/v1/owner/requests/$id/$action', {});
  Future<void> createUser(
          String username, String password, String displayName, int days,
          {int cards = 0, int cardDays = 0}) =>
      post('/v1/owner/users', {
        'username': username,
        'password': password,
        'displayName': displayName,
        'days': days,
        'cards': cards,
        'cardDays': cardDays,
      });

  /// شحن بطاقات مخططات لمستخدم — يضيف للرصيد ويحدد الصلاحية
  Future<void> grantQuota(String id, int cards, int days) =>
      post('/v1/owner/users/$id/quota', {'cards': cards, 'days': days});
  Future<List<dynamic>> ownerBans() async =>
      (await get('/v1/owner/bans'))['bans'] as List;
  Future<void> banDevice(String deviceId, String reason) =>
      post('/v1/owner/bans', {'deviceId': deviceId, 'reason': reason});

  /// حظر عنوان IP — يمنع المهاجم حتى لو غيّر جهازه.
  Future<void> banIp(String ip, String reason) =>
      post('/v1/owner/bans', {'ip': ip, 'reason': reason});
  Future<void> unbanDevice(String deviceId) =>
      delete('/v1/owner/bans/${Uri.encodeComponent(deviceId)}');
  Future<List<dynamic>> ownerAnnouncements() async =>
      (await get('/v1/owner/announcements'))['announcements'] as List;
  Future<Map<String, dynamic>> createAnnouncement(
          String title, String subtitle, String linkUrl,
          {String? imageB64, String? imageExt, String? imageUrl}) =>
      post('/v1/owner/announcements', {
        'title': title,
        'subtitle': subtitle,
        'linkUrl': linkUrl,
        if (imageB64 != null) 'imageB64': imageB64,
        if (imageExt != null) 'imageExt': imageExt,
        if (imageUrl != null) 'imageUrl': imageUrl,
      });
  Future<void> deleteAnnouncement(String id) =>
      delete('/v1/owner/announcements/$id');
}
