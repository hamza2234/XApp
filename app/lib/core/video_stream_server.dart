/// تشغيل سريع للفيديوهات: خادم محلي يخدم الملف أثناء اكتماله.
///
/// الفيديو يصل مشفّراً AES-CTR، و`video_player` لا يفكّ تشفيراً. الحل السابق
/// كان تنزيل الملف كاملاً ثم تشغيله: مستخدم ينتظر دقائق قبل أول إطار، وملف
/// ضخم يشغل شبكة الجهاز بلا فائدة إن توقّف في المنتصف.
///
/// هنا يُفكّ التشفير إلى ملف محلي **متزايد**، ويُقدَّم للمشغّل عبر HTTP محلي
/// على 127.0.0.1. فيقرأ المشغّل الرأس (moov) مبكراً ويبدأ العرض، ويواصل
/// التنزيل في الخلفية. لا يمرّ الفيديو كاملاً في الذاكرة أبداً — لا نسخة
/// مشفّرة ولا مفكوكة — وهذا ما يمنع الانهيار على الأجهزة الصغيرة.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// جلسة بثّ واحدة: ملف يزيد بايتاً بايت بينما يقرأه المشغّل.
class StreamSession {
  StreamSession({required this.file, required this.part, required this.key});

  final File file;
  final File part;
  final String key;

  int? total;
  int downloaded = 0;
  bool done = false;
  bool failed = false;
  String error = '';

  final _waiters = <void Function()>[];

  /// آخر ملف يُقرأ منه: `.part` أثناء التنزيل، والملف النهائي بعده.
  File get readable => done ? file : part;

  void _wake() {
    final w = List<void Function()>.from(_waiters);
    _waiters.clear();
    for (final f in w) {
      f();
    }
  }

  void onProgress(int received, int t) {
    downloaded = received;
    if (t > 0) total = t;
    _wake();
  }

  void finish() {
    done = true;
    _wake();
  }

  void fail(String e) {
    failed = true;
    error = e;
    _wake();
  }

  /// ينتظر تغيّراً في الحالة أو انتهاء المهلة. يُستخدم في الحلقة التي تخدم
  /// القراءة بدل الاستقصاء المحموم.
  Future<void> changed(Duration timeout) async {
    final c = Completer<void>();
    void w() {
      if (!c.isCompleted) c.complete();
    }

    _waiters.add(w);
    try {
      await c.future.timeout(timeout, onTimeout: () {});
    } finally {
      _waiters.remove(w);
    }
  }
}

/// خادم البثّ المحلي. يعمل طوال عمر التطبيق ومربوط على 127.0.0.1 وحده.
class VideoStreamServer {
  VideoStreamServer._();
  static final VideoStreamServer instance = VideoStreamServer._();

  HttpServer? _server;
  final _sessions = <String, StreamSession>{};

  /// يضمن تشغيل الخادم ويعيد منفذه.
  Future<int> _ensure() async {
    final s = _server;
    if (s != null) return s.port;
    // loopback فقط: لا يُفتح للشبكة، فالمحتوى لا يخرج من الجهاز.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen((req) {
      unawaited(_handle(req));
    }, onError: (_) {});
    return server.port;
  }

  /// يسجّل جلسة ويعيد عنواناً محلياً يشغّله المشغّل.
  Future<String> urlFor(StreamSession session) async {
    final port = await _ensure();
    _sessions[session.key] = session;
    return 'http://127.0.0.1:$port/v/${session.key}';
  }

  /// مسح الجلسة بعد إغلاق المشغّل. الملف يبقى في الكاش للمشاهدة التالية.
  void release(String key) => _sessions.remove(key);

  Future<void> _handle(HttpRequest req) async {
    final response = req.response;
    try {
      final seg = req.uri.pathSegments;
      final session = seg.length == 2 ? _sessions[seg[1]] : null;
      if (session == null) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      await _serve(req, response, session);
    } catch (_) {
      // المشغّل يغلق الاتصال عند التوقّف أو التقديم — ليس خطأً يُسجَّل.
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serve(
      HttpRequest req, HttpResponse response, StreamSession s) async {
    // ننتظر معرفة الحجم الكلي: بدونه لا نستطيع إعلان طول المحتوى، وبدون
    // الطول يعجز المشغّل عن تحديد مواضع الطلب فيبدأ من الصفر كل مرة.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (s.total == null && !s.failed && !s.done) {
      if (DateTime.now().isAfter(deadline)) break;
      await s.changed(const Duration(milliseconds: 200));
    }

    if (s.failed && s.downloaded == 0) {
      response.statusCode = HttpStatus.badGateway;
      await response.close();
      return;
    }

    final total = s.total;
    var start = 0;
    var end = total != null ? total - 1 : -1;
    var partial = false;

    final range = req.headers.value('range');
    if (range != null && total != null) {
      final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range.trim());
      if (m != null && (m.group(1)!.isNotEmpty || m.group(2)!.isNotEmpty)) {
        if (m.group(1)!.isNotEmpty) {
          start = int.parse(m.group(1)!);
          if (m.group(2)!.isNotEmpty) end = int.parse(m.group(2)!);
        } else {
          start = total - int.parse(m.group(2)!);
          if (start < 0) start = 0;
        }
        if (end >= total) end = total - 1;
        partial = !(start == 0 && end == total - 1);
      }
    }
    if (total != null && (start > end || start >= total)) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set('content-range', 'bytes */$total');
      await response.close();
      return;
    }

    response.headers.contentType = ContentType.binary;
    response.headers.set('accept-ranges', 'bytes');
    response.headers.set('cache-control', 'no-store');
    if (total != null) {
      response.headers.contentLength = end - start + 1;
      if (partial) {
        response.headers.set('content-range', 'bytes $start-$end/$total');
      }
      response.statusCode =
          partial ? HttpStatus.partialContent : HttpStatus.ok;
    }

    var pos = start;
    while (end < 0 || pos <= end) {
      final read = s.readable;
      int available;
      try {
        available = await read.exists() ? await read.length() : 0;
      } catch (_) {
        available = 0;
      }
      if (pos < available) {
        final stop = end < 0 ? available - 1 : end;
        final len = (stop - pos + 1).clamp(1, 256 * 1024);
        try {
          final raf = await read.open();
          try {
            await raf.setPosition(pos);
            final bytes = await raf.read(len);
            if (bytes.isEmpty) break;
            response.add(bytes);
            pos += bytes.length;
            continue;
          } finally {
            await raf.close();
          }
        } catch (_) {
          // التنزيل يسمّي الملف النهائي عند اكتماله، فقد يختفي `.part` لحظة
          // النقل. إن انتهى التنزيل نقرأ من الملف النهائي، وإلا ننتظر قليلاً
          // بدل إنهاء الاتصال — وهو ما كان يُظهر خطأً في آخر ثانية.
          if (s.done) continue;
          if (s.failed) break;
          await s.changed(const Duration(milliseconds: 200));
          continue;
        }
      }
      // لا مزيد من البايتات الآن: إمّا انتهى التنزيل أو ننتظر القطعة القادمة.
      if (s.done) break;
      if (s.failed) break;
      await s.changed(const Duration(milliseconds: 300));
    }
    await response.flush();
    await response.close();
  }
}