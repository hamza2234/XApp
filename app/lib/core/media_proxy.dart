/// وكيل وسائط محلي: ينقل طلبات المشغّل إلى الخادم موقّعةً طازجة كل مرة.
///
/// لماذا وكيل أصلاً: `video_player` لا يستطيع إرسال ترويسات مخصّصة في كل طلب
/// قطعة، والخادم يرفض الطلبات غير الموقّعة. ترويسة موقّعة واحدة لا تكفي لأن
/// التوقيع يحمل طابعاً زمنياً ينتهي بعد 10 دقائق — وهو بالضبط سبب «يشتغل ثم
/// يفشل» في الفيديوهات الطويلة. الوكيل يوقّع عند كل طلب، فيبقى التوقيع صالحاً
/// مهما طال التشغيل.
///
/// لماذا هذا ليس كاشاً: لا يُكتب أي بايت على القرص. القطع تمرّ من الذاكرة إلى
/// المشغّل مباشرة، ولا يوجد ملف فيديو في التخزين إطلاقاً.
library;

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api.dart';

/// خادم محلي يخدم مساراً واحداً موقّعاً من الخادم الحقيقي.
class MediaProxy {
  MediaProxy._();
  static final MediaProxy instance = MediaProxy._();

  HttpServer? _server;

  /// عميل الخادم — التوقيع يحتاج حالة الجهاز والجلسة، فلا يكفي مسار وحده.
  Api? _api;

  /// المسار الحقيقي الموقّع المقابل لكل مفتاح محلي.
  final _paths = <String, String>{};
  final _clients = <http.Client>{};
  int _session = 0;

  void clear() {
    _session++;
    _paths.clear();
    _api = null;
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }

  Future<int> _ensure() async {
    final s = _server;
    if (s != null) return s.port;
    // loopback فقط: لا يُفتح للشبكة، والمسار لا يخرج من الجهاز.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((req) {
      unawaited(_handle(req));
    }, onError: (_) {});
    return server.port;
  }

  /// يسجّل مساراً ويعيد عنواناً محلياً يصلح لـ`video_player`.
  Future<String> urlFor(Api api, String path) async {
    final port = await _ensure();
    _api = api;
    final key = path.hashCode.toRadixString(16);
    _paths[key] = path;
    return 'http://127.0.0.1:$port/m/$key';
  }

  void release(String url) {
    final i = url.lastIndexOf('/m/');
    if (i < 0) return;
    _paths.remove(url.substring(i + 3));
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    final session = _session;
    http.Client? client;
    try {
      final seg = req.uri.pathSegments;
      final path = seg.length == 2 && seg[0] == 'm' ? _paths[seg[1]] : null;
      final api = _api;
      if (path == null || api == null) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }

      // طلب GET بلا جسم: المشغّل يقرأ فقط. نُمرّر ما يحتاجه وحده — نطاق
      // البايتات (لتقديم/تأخير) والنوع المُعلن. ترويسة موقّعة قادمة من العميل
      // لا تُنقل: أجلها ينقضي، والتوقيع يُبنى هنا طازجاً لهذا الطلب بعينه.
      final proxied = http.Request('GET', api.streamUriFor(path));
      final range = req.headers.value('range');
      if (range != null) proxied.headers['range'] = range;
      final accept = req.headers.value('accept');
      if (accept != null) proxied.headers['accept'] = accept;
      proxied.headers.addAll(await api.streamHeadersFor(path));
      if (session != _session) throw StateError('session ended');

      client = http.Client();
      _clients.add(client);
      final upstream = await client
          .send(proxied)
          .timeout(const Duration(seconds: 30));

      res.statusCode = upstream.statusCode;
      upstream.headers.forEach((k, v) {
        // `transfer-encoding` يُعاد حسابه محلياً؛ تمريره كما هو يُفسد الإطار.
        if (k == 'transfer-encoding') return;
        res.headers.set(k, v);
      });
      // البثّ إلى المشغّل وهو يصل: لا يُجمع الملف في الذاكرة ولا على القرص.
      await res.addStream(upstream.stream);
    } catch (_) {
      // المشغّل يقطع الاتصال عند التقديم أو الإغلاق — ليس خطأً يُبلَّغ عنه.
      try {
        res.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      _clients.remove(client);
      client?.close();
      try {
        await res.close();
      } catch (_) {}
    }
  }
}
