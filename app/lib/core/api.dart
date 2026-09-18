import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cg;
import 'package:http/http.dart' as http;
import 'config.dart';
import 'models.dart';
import 'store.dart';

/// فك تشفير ردود لوحة المالك.
///
/// المفتاح مشتق من جلسة المالك: SHA-256 على `xapp-owner-panel-v1|<token>`،
/// مطابقاً لحساب الخادم. لا يوجد مفتاح ثابت مضمَّن في التطبيق — أي سرّ
/// مضمَّن يمكن استخراجه من الـAPK، أما جلسة المالك فلا يملكها غيره.
class OwnerCrypto {
  const OwnerCrypto._();

  static Future<cg.SecretKey> _key(String token) async {
    final digest = await cg.Sha256().hash(
        utf8.encode('xapp-owner-panel-v1|$token'));
    return cg.SecretKey(digest.bytes);
  }

  /// يفكّ `nonce.ciphertext` (base64url) ويعيد الخريطة المفكوكة.
  static Future<Map<String, dynamic>> open(
      String token, String sealed) async {
    final dot = sealed.indexOf('.');
    if (dot <= 0) throw const FormatException('sealed payload');
    final nonce = _b64u(sealed.substring(0, dot));
    final data = _b64u(sealed.substring(dot + 1));
    final algo = cg.AesGcm.with256bits();
    final clear = await algo.decrypt(
      cg.SecretBox(data, nonce: nonce, mac: cg.Mac.empty),
      secretKey: await _key(token),
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  static List<int> _b64u(String s) {
    final padded = s.replaceAll('-', '+').replaceAll('_', '/');
    final pad = (4 - padded.length % 4) % 4;
    return base64.decode(padded + '=' * pad);
  }
}

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
    final dev = store.deviceId;
    final fp = store.fingerprint;
    // البصمة داخل التوقيع حين تتوفر: تُربط بالطلب فلا يستطيع أحد تبديلها
    // للحصول على منحة يومية جديدة.
    final payload = fp.isEmpty
        ? '$dev|$ts|$method|$pathWithQuery'
        : '$dev|$fp|$ts|$method|$pathWithQuery';
    final sig = Hmac(sha256, utf8.encode(SigKey.secret))
        .convert(utf8.encode(payload))
        .toString();
    return {
      'x-device-id': dev,
      if (fp.isNotEmpty) 'x-device-fp': fp,
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
      {Map<String, String>? query, Duration? timeout}) async {
    final uri = _uri(path, query);
    final pq = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final res = await http
        .get(uri, headers: _sign('GET', pq))
        .timeout(timeout ?? const Duration(seconds: 30));
    return _decode(res);
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body,
      {Map<String, String>? query, Duration? timeout}) async {
    final uri = _uri(path, query);
    final pq = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final res = await http
        .post(uri,
            headers: {..._sign('POST', pq), 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(timeout ?? const Duration(seconds: 30));
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
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return body;
      } catch (_) {
        return {'ok': true};
      }
    }
    throw ApiException(res.statusCode, _errMsg(res));
  }

  // ===== لوحة المالك: جلسة معزولة وردود مشفّرة =====

  /// ترويسات جلسة المالك — تُستخدم لطلبات اللوحة وحدها.
  Map<String, String> _ownerSign(String method, String pathWithQuery) {
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final dev = store.deviceId;
    final fp = store.fingerprint;
    final payload = fp.isEmpty
        ? '$dev|$ts|$method|$pathWithQuery'
        : '$dev|$fp|$ts|$method|$pathWithQuery';
    final sig = Hmac(sha256, utf8.encode(SigKey.secret))
        .convert(utf8.encode(payload))
        .toString();
    return {
      'x-device-id': dev,
      if (fp.isNotEmpty) 'x-device-fp': fp,
      'x-app-ts': ts,
      'x-app-sig': sig,
      'x-app-version': '$kAppVersion',
      'User-Agent': 'X-App/$kAppVersionName',
      'Authorization': 'Bearer ${store.ownerToken}',
    };
  }

  /// دخول المالك — مسار معزول يعيد جلسة بسرّ مستقل.
  Future<Map<String, dynamic>> ownerLogin(
      String username, String password) async {
    final uri = _uri('/v1/owner/login');
    final res = await http
        .post(uri,
            headers: {
              ..._sign('POST', uri.path),
              'Content-Type': 'application/json'
            },
            body: jsonEncode({'username': username, 'password': password}))
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  /// يفكّ رد لوحة المالك المشفّر.
  ///
  /// المفتاح مشتق من جلسة المالك نفسها (SHA-256 على وسم ثابت + الرمز)،
  /// مطابقاً لما يفعله الخادم. هذا يعني أن استجابة مسرّبة إلى سجل أو نسخة
  /// احتياطية تبقى غير مقروءة بلا الجلسة.
  Future<Map<String, dynamic>> _ownerDecode(http.Response res) async {
    final body = _decode(res);
    final enc = body['enc'];
    if (enc is! String) return body;
    final token = store.ownerToken;
    if (token == null) throw ApiException(401, 'انتهت جلسة المالك — أعد الدخول');
    try {
      return await OwnerCrypto.open(token, enc);
    } catch (_) {
      throw ApiException(401, 'تعذر فك رد اللوحة — أعد الدخول');
    }
  }

  Future<Map<String, dynamic>> ownerGet(String path,
      {Map<String, String>? query}) async {
    final uri = _uri(path, query);
    final pq = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    final res = await http
        .get(uri, headers: _ownerSign('GET', pq))
        .timeout(const Duration(seconds: 30));
    return _ownerDecode(res);
  }

  Future<Map<String, dynamic>> ownerSend(
      String method, String path, Map<String, dynamic>? body) async {
    final uri = _uri(path);
    final res = await (switch (method) {
      'POST' => http.post(uri,
          headers: {
            ..._ownerSign('POST', uri.path),
            'Content-Type': 'application/json'
          },
          body: body == null ? null : jsonEncode(body)),
      'PUT' => http.put(uri,
          headers: {
            ..._ownerSign('PUT', uri.path),
            'Content-Type': 'application/json'
          },
          body: body == null ? null : jsonEncode(body)),
      'DELETE' => http.delete(uri, headers: _ownerSign('DELETE', uri.path)),
      _ => throw ArgumentError(method),
    }).timeout(const Duration(seconds: 30));
    return _ownerDecode(res);
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

  /// مهلة الإقلاع قصيرة عمداً: أول تشغيل على شبكة ضعيفة يجب أن يُظهر زر
  /// إعادة المحاولة بسرعة بدل تدوير 30 ثانية × 5 محاولات.
  static const _bootTimeout = Duration(seconds: 12);

  Future<Map<String, dynamic>> bootstrap() =>
      get('/v1/bootstrap', timeout: _bootTimeout);

  Future<void> registerInstall() => post('/v1/install', {
        'installId': store.deviceId,
        'appVersion': '$kAppVersion',
      }, timeout: _bootTimeout);

  Future<Map<String, dynamic>> guest() =>
      post('/v1/auth/guest', {}, timeout: _bootTimeout);

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

  /// دخول شركة: هنا يقع الخصم الوحيد (مرة لكل شركة في اليوم).
  /// يُستدعى عند فتح شاشة الشركة، فيرى المستخدم رصيده قبل أن يكتب أي حرف.
  Future<CompatOpenResult> openCompat(String? brand) async {
    final j = await post('/v1/data/compat/open',
        {'brand': brand ?? ''}, timeout: const Duration(seconds: 20));
    return CompatOpenResult(
      charged: j['charged'] == true,
      remaining: (j['remaining'] as num?)?.toInt() ?? -1,
      balance: (j['balance'] as num?)?.toInt() ?? -1,
      source: '${j['source'] ?? ''}',
    );
  }

  /// بحث التوافقات — يتم على الخادم داخل نطاق الشركة والنوع.
  /// لا نجلب ملف الشركة كاملاً بعد الآن: كان ذلك ~65KB و0.9 ثانية لكل دخول،
  /// وهو ما كان يسبب إحساس «تحميل كل التوافقات»، وكان يسمح بسحب البيانات.
  /// ولا يخصم: الخصم وقع عند دخول الشركة (openCompat).
  Future<CompatSearchResult> searchCompatCharged(String q,
      {String? brand, String? type}) async {
    final body = <String, dynamic>{'q': q};
    if (brand != null && brand.isNotEmpty) body['brand'] = brand;
    if (type != null && type.isNotEmpty) body['type'] = type;
    final j = await post('/v1/data/compat/search', body);
    return CompatSearchResult(
      records: (j['records'] as List?) ?? const [],
      types: ((j['types'] as List?) ?? const []).map((e) => '$e').toList(),
      charged: j['charged'] == true,
      remaining: (j['remaining'] as num?)?.toInt() ?? -1,
      balance: (j['balance'] as num?)?.toInt() ?? -1,
      source: '${j['source'] ?? ''}',
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
  Future<Map<String, dynamic>> ownerOverview() => ownerGet('/v1/owner/overview');
  Future<Map<String, dynamic>> ownerSettings() => ownerGet('/v1/owner/settings');
  Future<Map<String, dynamic>> saveSettings(Map<String, dynamic> s) =>
      ownerSend('PUT', '/v1/owner/settings', s);
  Future<List<dynamic>> ownerUsers() async =>
      (await ownerGet('/v1/owner/users'))['users'] as List;
  Future<List<dynamic>> ownerRequests() async =>
      (await ownerGet('/v1/owner/requests'))['requests'] as List;
  /// سجل الأمان — الهجمات فقط افتراضياً، و`all` يكشف كل الأحداث.
  Future<List<dynamic>> ownerSecurity({bool all = false}) async =>
      (await ownerGet('/v1/owner/security', query: all ? {'all': '1'} : null))['events']
          as List;
  Future<void> userAction(String id, String action, {int? days}) =>
      ownerSend('POST', '/v1/owner/users/$id/$action', {if (days != null) 'days': days});
  Future<void> requestAction(String id, String action) =>
      ownerSend('POST', '/v1/owner/requests/$id/$action', {});
  Future<void> createUser(
          String username, String password, String displayName, int days,
          {int cards = 0, int cardDays = 0}) =>
      ownerSend('POST', '/v1/owner/users', {
        'username': username,
        'password': password,
        'displayName': displayName,
        'days': days,
        'cards': cards,
        'cardDays': cardDays,
      });

  /// شحن بطاقات مخططات لمستخدم — يضيف للرصيد ويحدد الصلاحية
  Future<void> grantQuota(String id, int cards, int days) =>
      ownerSend('POST', '/v1/owner/users/$id/quota', {'cards': cards, 'days': days});

  /// محافظ الزوار: عملات لزائر بلا حساب، مفتاحها معرّف الجهاز.
  Future<List<dynamic>> ownerWallets() async =>
      (await ownerGet('/v1/owner/wallets'))['wallets'] as List;
  Future<void> grantWallet(String deviceId, int coins, int days) =>
      ownerSend('POST', '/v1/owner/wallets', {
        'deviceId': deviceId,
        'coins': coins,
        'days': days,
      });

  /// تعديل محفظة: تعيين الرصيد والصلاحية إلى قيم محددة.
  Future<void> editWallet(String deviceId, int coins, int days) =>
      ownerSend('PUT', '/v1/owner/wallets', {
        'deviceId': deviceId,
        'coins': coins,
        'days': days,
      });

  /// إنقاص أو إضافة بجرعة (delta سالب للإنقاص).
  Future<Map<String, dynamic>> adjustWallet(String deviceId, int delta,
          {int days = 0}) =>
      ownerSend('POST', '/v1/owner/wallets/adjust', {
        'deviceId': deviceId,
        'delta': delta,
        'days': days,
      });

  /// حذف محفظة بالكامل.
  Future<void> deleteWallet(String deviceId) => ownerSend(
      'DELETE', '/v1/owner/wallets/${Uri.encodeComponent(deviceId)}', null);
  Future<List<dynamic>> ownerBans() async =>
      (await ownerGet('/v1/owner/bans'))['bans'] as List;
  Future<void> banDevice(String deviceId, String reason) =>
      ownerSend('POST', '/v1/owner/bans', {'deviceId': deviceId, 'reason': reason});

  /// حظر عنوان IP — يمنع المهاجم حتى لو غيّر جهازه.
  Future<void> banIp(String ip, String reason) =>
      ownerSend('POST', '/v1/owner/bans', {'ip': ip, 'reason': reason});
  Future<void> unbanDevice(String deviceId) => ownerSend(
      'DELETE', '/v1/owner/bans/${Uri.encodeComponent(deviceId)}', null);
  Future<List<dynamic>> ownerAnnouncements() async =>
      (await ownerGet('/v1/owner/announcements'))['announcements'] as List;
  Future<Map<String, dynamic>> createAnnouncement(
          String title, String subtitle, String linkUrl,
          {String? imageB64, String? imageExt, String? imageUrl}) =>
      ownerSend('POST', '/v1/owner/announcements', {
        'title': title,
        'subtitle': subtitle,
        'linkUrl': linkUrl,
        if (imageB64 != null) 'imageB64': imageB64,
        if (imageExt != null) 'imageExt': imageExt,
        if (imageUrl != null) 'imageUrl': imageUrl,
      });
  Future<void> deleteAnnouncement(String id) =>
      ownerSend('DELETE', '/v1/owner/announcements/$id', null);

  // ===== الدردشة =====

  Future<ChatState> chatState() async =>
      ChatState.fromJson(await get('/v1/chat/state'));

  /// رسائل قسم.
  ///
  /// ثلاثة أنماط، وكلها محدودة:
  ///   [since]  الجديد بعد ختم زمني — يُستدعى كل بضع ثوانٍ، وعادةً يعود فارغاً.
  ///   [before] دفعة أقدم عند التمرير للأعلى.
  ///   بلا شيء  أحدث صفحة عند أول فتح.
  /// هذا ما يمنع تحميل المحادثة كاملة كل مرة، فلا تثقل الشبكة ولا الذاكرة.
  Future<ChatPage> chatMessages(
    String room, {
    int since = 0,
    int before = 0,
    int limit = 40,
  }) async {
    final j = await get('/v1/chat/messages', query: {
      'room': room,
      if (since > 0) 'since': '$since',
      if (before > 0) 'before': '$before',
      'limit': '$limit',
    });
    return ChatPage(
      messages: ((j['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(e.cast<String, dynamic>()))
          .toList(),
      hasMore: j['hasMore'] == true,
    );
  }

  /// إعلام الخادم أن المستخدم بلغ آخر رسالة — أساس «من رأى الرسالة».
  Future<void> chatSeen(String room, int at) =>
      post('/v1/chat/seen', {'room': room, 'at': at});

  /// إرسال رسالة. [mediaB64] صورة أو مقطع، و[mediaSeconds] مدة المقطع.
  Future<ChatMessage> chatSend(
    String room, {
    String text = '',
    String? mediaB64,
    int mediaSeconds = 0,
  }) async {
    final j = await post(
      '/v1/chat/send',
      {
        'room': room,
        'text': text,
        if (mediaB64 != null) 'mediaB64': mediaB64,
        if (mediaSeconds > 0) 'mediaSeconds': mediaSeconds,
      },
      // رفع مقطع يحتاج مهلة أطول من رسالة نصية.
      timeout: mediaB64 == null
          ? const Duration(seconds: 30)
          : const Duration(minutes: 3),
    );
    return ChatMessage.fromJson(
        (j['message'] as Map?)?.cast<String, dynamic>() ?? const {});
  }

  /// حفظ ملف الدردشة: كنية، صورة شخصية، وكتم الإشعارات.
  Future<Map<String, dynamic>> chatProfile({
    String? nickname,
    String? imageB64,
    bool clearAvatar = false,
    bool? notify,
  }) =>
      put('/v1/chat/profile', {
        if (nickname != null) 'nickname': nickname,
        if (imageB64 != null) 'imageB64': imageB64,
        if (clearAvatar) 'clearAvatar': true,
        if (notify != null) 'notify': notify,
      });

  // ===== إشراف المالك على الدردشة =====

  Future<List<dynamic>> ownerChatMessages({String room = ''}) async =>
      (await ownerGet('/v1/owner/chat/messages',
              query: room.isEmpty ? null : {'room': room}))['messages']
          as List;

  Future<void> ownerDeleteChatMessage(String id) =>
      ownerSend('DELETE', '/v1/owner/chat/messages/$id', null);

  Future<void> ownerPurgeRoom(String room) =>
      ownerSend('POST', '/v1/owner/chat/purge', {'room': room});

  /// كتم أو طرد عضو. [room] فارغ = كل الأقسام، و[minutes] 0 للكتم الدائم.
  Future<void> ownerChatAction({
    required String userId,
    required String kind,
    String room = '',
    String reason = '',
    int minutes = 0,
  }) =>
      ownerSend('POST', '/v1/owner/chat/action', {
        'userId': userId,
        'kind': kind,
        'room': room,
        'reason': reason,
        'minutes': minutes,
      });

  Future<void> ownerClearChatAction(String userId, {String kind = ''}) =>
      ownerSend('POST', '/v1/owner/chat/action/clear', {
        'userId': userId,
        if (kind.isNotEmpty) 'kind': kind,
      });

  Future<List<ChatAction>> ownerChatActions() async =>
      ((await ownerGet('/v1/owner/chat/actions'))['actions'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => ChatAction.fromJson(e.cast<String, dynamic>()))
          .toList();
}
