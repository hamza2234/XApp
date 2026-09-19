import 'package:flutter_chat_core/flutter_chat_core.dart' as fc;

import '../core/config.dart';
import '../core/models.dart' as app;

/// جسر بين نماذج التطبيق ونماذج `flutter_chat_core`.
///
/// نستخدم `Message.custom` لكل الرسائل ونضع originalen في `metadata`، لأن
/// الحقول القياسية في الحزمة لا تغطي ما نحتاجه: الرصيد، الإشراف، من رأى
/// الرسالة، ومخطط الموجة الموسّع. `metadata` يُحمل داخل الكائن ولا يُسلسل
/// إلى JSON في هذه الحزمة (لا `toJson` في مسار العرض)، فالكائنات تعيش كما هي.
///
/// المفتاح `app` يحمل نسخة `app.ChatMessage` نفسها، فلا نُكرّر التحويل عند
/// الرسم ونبقى على مصدر حقيقة واحد.
class ChatBridge {
  ChatBridge();

  static const String metadataKey = 'app';

  /// معرّف ثابت لصاحب التطبيق.
  ///
  /// لا نستخدم معرّف الجهاز: الحزمة تحسب `isSentByMe` بمقارنة
  /// `currentUserId == authorId`، ومعرّفنا يبدأ فارغاً قبل اكتمال الهوية ثم
  /// يتغيّر بعد التسجيل — فتنتقل فقاعاتنا من اليمين إلى اليسار فجأة. `mine`
  /// يأتي محسوباً من الخادم، فهو المرجع الوحيد المستقرّ.
  static const String myUserId = 'me';

  /// يحوّل رسالة تطبيق إلى رسالة حزمة. `id` يبقى نفسه فلا تفقد التحديثات
  /// اللاحقة (`poll`) مرجعها.
  fc.Message toCore(app.ChatMessage m, {required bool isMine}) {
    final metadata = <String, dynamic>{metadataKey: m};

    // الرسالة النظامية نصّ بلا مؤلّف — نضعها كنظام لا كفقاعة.
    if (m.kind == 'system') {
      return fc.Message.system(
        id: m.id,
        authorId: _authorId(m, isMine),
        createdAt: m.time,
        sentAt: m.time,
        text: m.body,
        metadata: metadata,
      );
    }

    switch (m.kind) {
      case 'image':
        return fc.Message.image(
          id: m.id,
          authorId: _authorId(m, isMine),
          createdAt: m.time,
          sentAt: m.time,
          source: _absolute(m.mediaUrl),
          text: m.body.isEmpty ? null : m.body,
          size: m.mediaSize == 0 ? null : m.mediaSize,
          metadata: metadata,
        );
      case 'video':
        return fc.Message.video(
          id: m.id,
          authorId: _authorId(m, isMine),
          createdAt: m.time,
          sentAt: m.time,
          source: _absolute(m.mediaUrl),
          text: m.body.isEmpty ? null : m.body,
          size: m.mediaSize == 0 ? null : m.mediaSize,
          metadata: metadata,
        );
      case 'audio':
        return fc.Message.audio(
          id: m.id,
          authorId: _authorId(m, isMine),
          createdAt: m.time,
          sentAt: m.time,
          source: _absolute(m.mediaUrl),
          duration: Duration(seconds: m.seconds),
          size: m.mediaSize == 0 ? null : m.mediaSize,
          waveform: m.waveform.isEmpty ? null : m.waveform,
          metadata: metadata,
        );
      default:
        // نصوصنا الصوتية/النصّية كلها `text`، والحزمة تتولّى التاريخ والتجميع.
        return fc.Message.text(
          id: m.id,
          authorId: _authorId(m, isMine),
          createdAt: m.time,
          sentAt: m.time,
          text: m.body,
          metadata: metadata,
        );
    }
  }

  /// رسالة قادمة من الحزمة (لم يرسلها التطبيق) — نستخرج الصورة الأصلية.
  /// تُستخدم لربط النقر على الرسالة بمنطقنا (الملف الشخصي، المشغّل…).
  static app.ChatMessage? unwrap(fc.Message m) {
    final meta = m.metadata;
    final raw = meta == null ? null : meta[metadataKey];
    return raw is app.ChatMessage ? raw : null;
  }

  /// رسائلي تحمل `myUserId` دائماً، ورسائل الآخرين معرّف جهازهم من الخادم.
  String _authorId(app.ChatMessage m, bool isMine) {
    if (isMine) return myUserId;
    return m.author.id.isEmpty ? 'anon' : m.author.id;
  }

  /// مسارات الوسائط نسبية (`/v1/media/...`) وتحتاج أصل الخادم.
  static String _absolute(String url) =>
      url.isEmpty || !url.startsWith('/') ? url : '$kApiBase$url';

  /// مستخدم الحزمة كما تعرضه الواجهة (الاسم والصورة).
  fc.User toUser(app.ChatAuthor a, {String id = ''}) => fc.User(
        id: id.isNotEmpty ? id : (a.id.isEmpty ? 'anon' : a.id),
        name: a.label,
        imageSource: a.avatarUrl.isEmpty ? null : _absolute(a.avatarUrl),
      );
}