import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// كاش صور: ذاكرة أولاً، ثم قرص، ثم شبكة.
///
/// لماذا لا نكتفي بـ`Image.network`؟ لأن القائمة تُبنى من جديد عند كل تحديث
/// دوري (كل بضع ثوانٍ)، وكل بناء بلا كاش مستقر يعني وميضاً: الصورة تختفي
/// لحظة ثم تُحمَّل من جديد. هنا تبقى البايتات في الذاكرة، فالبناء التالي
/// يرسم فوراً بلا وميض، والقرص يجعلها باقية بعد إغلاق التطبيق أيضاً.
///
/// المفتاح هو الرابط كاملاً (بما فيه أي توقيع)، فيكون لكل صورة مدخل واحد.
class AvatarCache {
  AvatarCache._(this._maxMemory);

  /// صور الأعضاء: صغيرة وكثيرة، فحدّها مدخلات كثيرة بحجم قليل.
  static final AvatarCache avatars = AvatarCache._(200);

  /// صور المحادثة المعروضة بملء الشاشة: قليلة لكنها أكبر بكثير، فحدّها
  /// مدخلات أقل — الاحتفاظ بعشرين صورة كاملة يكفي للتنقّل بينها بلا وميض.
  static final AvatarCache media = AvatarCache._(20);

  final int _maxMemory;

  final Map<String, Uint8List> _memory = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};
  final Set<String> _failed = <String>{};
  Directory? _dir;

  /// بايتات الصورة إن كانت محفوظة، وإلا null — بلا انتظار.
  ///
  /// النداء متزامن عن قصد: البانية تحتاج قراراً فورياً (رسم من الكاش أم
  /// بديل)، وإلا ظهر الوميض الذي نعالجه.
  Uint8List? peek(String url) => _memory[url];

  bool hasFailed(String url) => _failed.contains(url);

  /// يجمع كل الأصول المستخدمة فعلاً ويلغي ما شاخ منها.
  ///
  /// الدردشة تُبدّل صورة الملف الشخصي فيصير للرابط نفسه معنى آخر، والصور
  /// القديمة تبقى في الكاش بلا مستخدم. نطردها دورياً بدل تركها تتضخّم.
  void retainOnly(Set<String> urls) {
    _memory.removeWhere((k, _) => !urls.contains(k));
    _failed.removeWhere((k) => !urls.contains(k));
  }

  /// يجلب الصورة: من الذاكرة، ثم القرص، ثم الشبكة، ويحفظها في كل طبقة.
  ///
  /// الطلبات المتزامنة للرابط نفسه تُدمج في طلب واحد (`_inflight`)، وإلا
  /// صار لكل صفّ في القائمة طلب مستقل لنفس الصورة عند أول ظهور.
  Future<Uint8List?> load(
    String url, {
    Map<String, String>? headers,
  }) async {
    final cached = _memory[url];
    if (cached != null) return cached;
    if (_failed.contains(url)) return null;
    final running = _inflight[url];
    if (running != null) return running;
    final task = _loadOnce(url, headers).whenComplete(() {
      _inflight.remove(url);
    });
    _inflight[url] = task;
    return task;
  }

  Future<Uint8List?> _loadOnce(
    String url,
    Map<String, String>? headers,
  ) async {
    // 1) القرص: يعمل بلا شبكة ويُلوّن الأفاتار قبل وصول أي ردّ.
    try {
      final f = await _fileFor(url);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        if (bytes.isNotEmpty) {
          _remember(url, bytes);
          return bytes;
        }
      }
    } catch (_) {
      // تعذّر القرص لا يمنع الشبكة.
    }
    // 2) الشبكة.
    try {
      final res = await http.Client()
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400 || res.bodyBytes.isEmpty) {
        _failed.add(url);
        return null;
      }
      final bytes = res.bodyBytes;
      _remember(url, bytes);
      // الكتابة على القرص لا تُنتظر: الرسم لا يحتاجها.
      unawaited(_writeDisk(url, bytes));
      return bytes;
    } catch (_) {
      // فشل الشبكة لا يُسجَّل فشلاً دائماً: قد يكون انقطاعاً عارضاً.
      return null;
    }
  }

  void _remember(String url, Uint8List bytes) {
    if (_memory.length >= _maxMemory && !_memory.containsKey(url)) {
      _memory.remove(_memory.keys.first);
    }
    _memory[url] = bytes;
  }

  Future<File> _fileFor(String url) async {
    _dir ??= await getTemporaryDirectory();
    final name = md5.convert(utf8.encode(url)).toString();
    return File('${_dir!.path}/x_img_$name');
  }

  Future<void> _writeDisk(String url, Uint8List bytes) async {
    try {
      final f = await _fileFor(url);
      await f.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // التخزين المؤقت تحسين لا شرط.
    }
  }

  /// يُسقط صورة من كل الطبقات — عند تغيير المستخدم صورة حسابه.
  void evict(String url) {
    _memory.remove(url);
    _failed.remove(url);
    unawaited(() async {
      try {
        final f = await _fileFor(url);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }());
  }
}
