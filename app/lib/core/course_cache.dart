/// كاش ذكي لفيديوهات الدورات.
///
/// الفيديو يصل من الخادم مشفّراً AES-CTR، و`video_player` لا يفكّ تشفيراً في
/// الطيران. لذا يُنزَّل مرة، يُفكّ، ثم يُحفظ ملفاً محلياً لتشغيله. هذا الملف
/// هو ما يجعل المشاهدة الثانية فورية.
///
/// القواعد التي تمنع الانهيار — وهي جوهر هذا الملف:
///   • سقف حجم ثابت: الكاش لا ينمو بلا نهاية فيملأ تخزين الجهاز.
///   • إخلاء LRU: عند بلوغ السقف تُحذف أقدم المشاهدات لا أحدثها.
///   • تنزيل واحد لكل فيديو: طلبان متزامنان يتشاركان التنزيل نفسه بدل
///     مضاعفة الشبكة والذاكرة.
///   • لا استثناء يصل للواجهة: كل فشل يعود كـ[CacheResult] فيُعرض برسالة،
///     بدل أن يُسقط الشاشة.
///   • تنظيف عند التلف: ملف ناقص أو مشوّه يُحذف بدل تشغيل نصف فيديو.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'video_stream_server.dart';

/// نتيجة محاولة توفير فيديو. لا يُطلق استثناء أبداً.
class CacheResult {
  const CacheResult._(this.file, this.error);

  const CacheResult.ok(File f) : this._(f, '');
  const CacheResult.fail(String e) : this._(null, e);

  final File? file;
  final String error;

  bool get ok => file != null;
}

/// مدير كاش الفيديوهات — مفرد لكل تطبيق.
class CourseCache {
  CourseCache._();
  static final CourseCache instance = CourseCache._();

  /// سقف الكاش بالبايت. 600MB تكفي عشرات الدروس القصيرة، وتبقى دون الحد
  /// الذي تعتبره أندرويد ضغطاً كبيراً على تخزين الجهاز.
  static const int maxBytes = 600 * 1024 * 1024;

  /// أقصى حجم لفيديو واحد يُفكّ في الذاكرة مرة واحدة.
  ///
  /// الفكّ يمرّ بالذاكرة بالضرورة، فملف ضخم قد يُنهي التطبيق. الحدّ يمنع
  /// امتلاء الذاكرة على الأجهزة الصغيرة مع بقاء المساحة للدروس المعقولة.
  static const int maxSingleBytes = 350 * 1024 * 1024;

  Directory? _dir;

  /// التنزيلات الجارية — يشاركها الطلب المتكرر بدل تكرار العمل.
  final Map<String, Future<CacheResult>> _inflight = {};

  Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    // مجلد النظام المؤقت: أندرويد ينظّفه عند الحاجة، فلا يتراكم بلا رقابة
    // حتى لو تعطّل منطق الإخلاء لأي سبب.
    final base = await getTemporaryDirectory();
    final d = Directory('${base.path}/learn_cache');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  /// اسم ملف مشتق من مسار البث — ثابت للفيديو نفسه، فلا تكرار.
  ///
  /// لا نستعمل اسم الفيديو الخام: المسار قد يحمل محارف لا تصلح كاسم ملف على
  /// نظام معيّن، والتجزئة تُزيل هذا الاحتمال كلياً.
  String _nameFor(String streamPath) =>
      sha1.convert(streamPath.codeUnits).toString();

  /// يوفّر ملف الفيديو جاهزاً للتشغيل.
  ///
  /// إن كان في الكاش عاد مباشرة — وهذا مسار المشاهدة الثانية، وهو الأهم:
  /// يجب ألا يلمس الشبكة إطلاقاً. وإلا نزّله وفكّه وحفظه.
  Future<CacheResult> provide(
    Api api,
    String streamPath, {
    void Function(int received, int total)? onProgress,
  }) {
    // طلب جارٍ لنفس الفيديو: نتشاركه. هذا ما يمنع تنزيلين متوازيين عند ضغط
    // المستخدم مرتين بسرعة، وهو ما يُثقل الشبكة والذاكرة معاً.
    final existing = _inflight[streamPath];
    if (existing != null) return existing;

    final job = _provide(api, streamPath, onProgress: onProgress)
        .whenComplete(() => _inflight.remove(streamPath));
    _inflight[streamPath] = job;
    return job;
  }

  Future<CacheResult> _provide(
    Api api,
    String streamPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    File? target;
    try {
      final dir = await _ensureDir();
      target = File('${dir.path}/${_nameFor(streamPath)}');

      final cached = await target.exists() ? await target.length() : 0;
      if (cached > 0) {
        // اللمس يؤخّر إخلاءه: الملفات المستعملة حديثاً تبقى.
        await _touch(target);
        return CacheResult.ok(target);
      }

      // التنزيل والفكّ يجريان في دفق واحد إلى الملف: لا تُحمَّل النسخة
      // المشفّرة في الذاكرة ولا النسخة المفكوكة. `downloadCourseVideoToFile`
      // تكتب إلى ملف جانبي ثم تنقل، فلا يبقى ملف ناقص عند الانقطاع.
      final r = await api.downloadCourseVideoToFile(
        streamPath,
        target,
        onProgress: onProgress,
      );

      if (r.bytes == 0) return const CacheResult.fail('الفيديو فارغ');
      if (r.bytes > maxSingleBytes) {
        return const CacheResult.fail('الفيديو أكبر من الحد المسموح');
      }

      await _touch(target);
      // الإخلاء بعد الإضافة لا قبلها: لو فشل التنزيل لما حذفنا شيئاً.
      unawaited(_evict());
      return CacheResult.ok(target);
    } catch (e) {
      // ملف تالف أو انقطاع: ننظّف حتى لا يُشغَّل نصف فيديو لاحقاً.
      try {
        if (target != null) {
          final tmp = File('${target.path}.part');
          if (await tmp.exists()) await tmp.delete();
          if (await target.exists() && await target.length() == 0) {
            await target.delete();
          }
        }
      } catch (_) {}
      if (e is ApiException) return CacheResult.fail(e.message);
      return const CacheResult.fail('تعذر تحضير الفيديو — تحقق من الإنترنت');
    }
  }

  /// يحدّث وقت آخر استخدام. فشل هذا لا يُفشل المشاهدة أبداً.
  Future<void> _touch(File f) async {
    try {
      await f.setLastAccessed(DateTime.now());
    } catch (_) {}
  }

  /// الجلسات الجارية للتشغيل المتزايد — مفتاحها مسار البثّ.
  final _live = <String, StreamSession>{};

  /// يوفّر تشغيلاً فورياً: يعيد ملفاً كاملاً إن كان في الكاش، وإلا يبدأ
  /// تنزيلاً متزايداً ويعيد جلسته ليُخدم منها المشغّل وهو يُكتب.
  ///
  /// هذا هو الفرق الجوهري عن [provide]: ذاك ينتظر اكتمال الملف قبل أول إطار،
  /// وهذا يعرض من أول ميغابايت ويواصل في الخلفية.
  Future<({File? cached, StreamSession? session})> provideProgressive(
    Api api,
    String streamPath,
  ) async {
    try {
      final dir = await _ensureDir();
      final target = File('${dir.path}/${_nameFor(streamPath)}');

      final cached = await target.exists() ? await target.length() : 0;
      if (cached > 0) {
        await _touch(target);
        return (cached: target, session: null);
      }

      final running = _live[streamPath];
      if (running != null && !running.failed) {
        return (cached: null, session: running);
      }

      final part = File('${target.path}.part');
      // مخلّفات محاولة سابقة: تُحذف كي لا يُخلط فيديو ناقص بجديد.
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {}

      // لا يشترك طلبان في تنزيل واحد: الثاني يخدم نفس الجلسة بدل مضاعفة
      // الشبكة والقرص.
      final session = StreamSession(
          file: target, part: part, key: _nameFor(streamPath));
      _live[streamPath] = session;
      unawaited(_pump(api, streamPath, target, session));
      return (cached: null, session: session);
    } catch (_) {
      return (cached: null, session: null);
    }
  }

  /// ينزّل ويفكّ إلى الملف المتزايد، ويبلّغ الجلسة بالتقدّم والنهاية.
  Future<void> _pump(
      Api api, String streamPath, File target, StreamSession session) async {
    try {
      await api.downloadCourseVideoToFile(
        streamPath,
        target,
        // فحص الحجم مبكراً: ملف أكبر من السقف يُقطع عند أول قطعة بدل أن
        // يُنزَّل كاملاً ثم يُرفض — لا نستهلك قرصاً ولا شبكة بلا فائدة.
        onProgress: (received, total) {
          if (total > maxSingleBytes) throw StateError('too_big');
          session.onProgress(received, total);
        },
      );
      await _touch(target);
      session.finish();
      unawaited(_evict());
    } catch (e) {
      if (e is StateError && e.message == 'too_big') {
        session.fail('الفيديو أكبر من الحد المسموح');
      } else if (e is ApiException) {
        session.fail(e.message);
      } else {
        session.fail('تعذر تشغيل الفيديو — تحقق من الإنترنت');
      }
    } finally {
      _live.remove(streamPath);
    }
  }

  /// المسارات التي تُخدم الآن — تُستثنى من الإخلاء والمسح كي لا يُحذف ملف
  /// تحت المشغّل مباشرة فيتوقف العرض فجأة.
  Set<String> get _servingPaths =>
      _live.values.expand((s) => [s.file.path, s.part.path]).toSet();

  /// يُخلي أقدم الملفات حتى ينزل الحجم تحت السقف.
  ///
  /// يعمل على القرص مباشرة لا على فهرس محفوظ: الفهرس قد ينحرف إن حُذف ملف
  /// من خارج التطبيق، والقراءة الفعلية هي الحقيقة الوحيدة الموثوقة.
  Future<void> _evict() async {
    try {
      final dir = await _ensureDir();
      final files = <File>[];
      var total = 0;
      final serving = _servingPaths;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        // ملفات `.part` قيد التنزيل: تُترك، وحجمها لا يُحسب.
        if (e.path.endsWith('.part')) continue;
        // ملف يُبثّ الآن لا يُحذف ولا يدخل في الحساب: حذفه يُفسد المشاهدة.
        if (serving.contains(e.path)) continue;
        final len = await e.length();
        files.add(e);
        total += len;
      }
      if (total <= maxBytes) return;

      files.sort((a, b) =>
          a.statSync().accessed.compareTo(b.statSync().accessed));
      for (final f in files) {
        if (total <= maxBytes) break;
        // لا نحذف ما يُنزَّل الآن: حذفه يُفسد مشاهدة جارية.
        if (_inflight.containsKey(f.path)) continue;
        try {
          total -= await f.length();
          await f.delete();
        } catch (_) {}
      }
    } catch (_) {
      // الإخلاء تحسين لا وظيفة: فشله لا يُعطّل المشاهدة.
    }
  }

  /// حجم الكاش الحالي بالبايت — لعرضه أو لتصفيره.
  Future<int> sizeBytes() async {
    try {
      final dir = await _ensureDir();
      var total = 0;
      await for (final e in dir.list()) {
        if (e is File && !e.path.endsWith('.part')) {
          total += await e.length();
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// يمسح الكاش كاملاً ما عدا ما يُنزَّل الآن.
  Future<void> clear() async {
    try {
      final dir = await _ensureDir();
      final serving = _servingPaths;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        if (_inflight.containsKey(e.path)) continue;
        if (serving.contains(e.path)) continue;
        try {
          await e.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }
}