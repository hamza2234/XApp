/// نماذج البيانات لتطبيق X
library;

class CompatBrand {
  CompatBrand(this.id, this.name, this.file, this.models, this.records);
  final String id;
  final String name;
  final String file;
  final int models;
  final int records;

  /// الاسم المعروض بدون البادئة الرقمية (02realme → Realme)
  String get displayName {
    final n = name.replaceAll(RegExp(r'^\d+'), '');
    return n.isEmpty ? name : n[0].toUpperCase() + n.substring(1);
  }

  /// معرّف الطلب: الشركات الفرعية تُطلب بـ`v_*` ليصفّيها الخادم على كلمتها،
  /// وإلا تُطلب باسم ملف الشركة كما هو.
  String get ref => id.startsWith('v_') ? id : file;

  factory CompatBrand.fromJson(Map<String, dynamic> j) => CompatBrand(
        '${j['id']}',
        j['name'] ?? '',
        j['file'] ?? '',
        (j['models'] as num?)?.toInt() ?? 0,
        (j['records'] as num?)?.toInt() ?? 0,
      );
}

class CompatRecord {
  CompatRecord(this.id, this.componentType, this.models, this.subCategory);
  final String id;
  final String componentType;
  final List<String> models;
  final String? subCategory;

  factory CompatRecord.fromJson(Map<String, dynamic> j) => CompatRecord(
        '${j['id']}',
        j['componentType']?.toString() ?? '',
        ((j['compatibleModels'] as List?) ?? [])
            .map((e) => e.toString().replaceAll('​', '').trim())
            .toList(),
        j['subCategory'] is Map ? j['subCategory']['name']?.toString() : null,
      );
}

class SchemBrand {
  SchemBrand(this.id, this.name);
  final String id;
  final String name;
  factory SchemBrand.fromJson(Map<String, dynamic> j) =>
      SchemBrand(j['id'] ?? '', j['name'] ?? '');
}

class SchemModel {
  SchemModel(this.name, this.folders);
  final String name;
  final List<SchemFolder> folders;
  factory SchemModel.fromJson(Map<String, dynamic> j) => SchemModel(
        j['name'] ?? '',
        ((j['folders'] as List?) ?? [])
            .map((f) => SchemFolder(f['category'] ?? '', f['id'] ?? ''))
            .toList(),
      );
}

class SchemFolder {
  SchemFolder(this.category, this.id);
  final String category;
  final String id;
}

class SchemEntry {
  SchemEntry(this.id, this.name, this.mimeType, this.size);
  final String id;
  final String name;
  final String mimeType;
  final String? size;

  bool get isFolder => mimeType == 'application/vnd.google-apps.folder';
  bool get isPdf => mimeType == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
  bool get isImage => mimeType.startsWith('image/') ||
      RegExp(r'\.(png|jpe?g|gif|webp|svg)$', caseSensitive: false).hasMatch(name);

  String get cleanName => name.replaceAll(RegExp(r' /$'), '');

  String? get sizeText {
    final s = int.tryParse(size ?? '');
    if (s == null) return null;
    if (s > 1048576) return '${(s / 1048576).toStringAsFixed(1)} MB';
    if (s > 1024) return '${(s / 1024).toStringAsFixed(0)} KB';
    return '$s B';
  }

  factory SchemEntry.fromJson(Map<String, dynamic> j) => SchemEntry(
        j['id'] ?? '', j['name'] ?? '', j['mimeType'] ?? '', j['size']?.toString());
}

class Announcement {
  Announcement(this.title, this.subtitle, this.linkUrl, this.imageUrl);
  final String title;
  final String subtitle;
  final String linkUrl;
  final String imageUrl;
  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        j['title']?.toString() ?? '',
        j['subtitle']?.toString() ?? '',
        j['linkUrl']?.toString() ?? '',
        j['imageUrl']?.toString() ?? '',
      );
}

class XSettings {
  XSettings({
    this.dailyFreeQuota = 5,
    this.minVersion = 1,
    this.blockedVersions = const [],
    this.telegramLink = '',
    this.schematicsLocked = false,
    this.compatLocked = false,
    this.compatSearchCost = 1,
    this.schemFilePrice = 1,
    this.dailyGiftAmount = 0,
    this.videosHidden = false,
    this.videosHiddenMessage = '',
    this.appLocked = false,
    this.lockMessage = '',
    this.updateMessage = '',
    this.updateUrl = '',
    this.updateImageUrl = '',
    List<XPackage>? packages,
    this.chatEnabled = true,
    this.chatReadOnly = false,
    this.chatTheme = 'bubble',
    this.chatWelcome = '',
    this.chatMaxLength = 1000,
    this.chatImagesEnabled = true,
    this.chatWriteScope = 'registered',
    this.chatMediaScope = 'subscribers',
    this.chatMaxMediaMb = 12,
    this.chatMediaSeconds = 120,
    this.chatPollMs = 4000,
    List<ChatRoom>? chatRooms,
  })  : packages = packages ?? [],
        chatRooms = chatRooms ?? [];
  /// المنحة اليومية الواحدة — تُخصم منها المخططات والتوافقات معاً،
  /// ولكل الأدوار (زائر ومسجّل ومشترك).
  int dailyFreeQuota;
  int minVersion;
  List<int> blockedVersions;
  String telegramLink;
  bool schematicsLocked;
  bool compatLocked;

  /// ثمن دخول الشركة في التوافقات بالعملات.
  int compatSearchCost;

  /// ثمن فتح ملف مخطط بالعملات. صفر يعني أن الفتح يعتمد المنحة اليومية فقط.
  int schemFilePrice;

  /// عملات الهديّة اليومية. صفر يعني أن زر الهديّة لا يظهر.
  int dailyGiftAmount;

  /// مفتاح المالك: إيقاف عرض الفيديوهات فوراً للجميع.
  bool videosHidden;
  String videosHiddenMessage;
  bool appLocked;
  String lockMessage;
  String updateMessage;
  String updateUrl;
  String updateImageUrl;
  List<XPackage> packages;

  /// إعدادات الدردشة — يحرّرها المالك من تبويب الدردشة في اللوحة.
  bool chatEnabled;
  bool chatReadOnly;
  String chatTheme;
  String chatWelcome;
  int chatMaxLength;
  bool chatImagesEnabled;

  /// all | registered | subscribers
  String chatWriteScope;

  /// subscribers | none
  String chatMediaScope;
  int chatMaxMediaMb;
  int chatMediaSeconds;
  int chatPollMs;
  List<ChatRoom> chatRooms;

  factory XSettings.fromJson(Map<String, dynamic> j) => XSettings(
        // الخادم الجديد يرسل dailyFreeQuota؛ والقديم يرسل الحقلين المنفصلين
        // فأخذ الأكبر يحفظ ما اعتاده المالك.
        dailyFreeQuota: (j['dailyFreeQuota'] as num?)?.toInt() ??
            [j['guestFileQuota'], j['guestCompatQuota']]
                .whereType<num>()
                .fold<int>(5, (a, b) => b.toInt() > a ? b.toInt() : a),
        minVersion: (j['minVersion'] as num?)?.toInt() ?? 1,
        blockedVersions:
            ((j['blockedVersions'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
        telegramLink: j['telegramLink']?.toString() ?? '',
        schematicsLocked: j['schematicsLocked'] == true,
        compatLocked: j['compatLocked'] == true,
        compatSearchCost: (j['compatSearchCost'] as num?)?.toInt() ?? 1,
        schemFilePrice: (j['schemFilePrice'] as num?)?.toInt() ??
            (j['compatSearchCost'] as num?)?.toInt() ??
            1,
        dailyGiftAmount: (j['dailyGiftAmount'] as num?)?.toInt() ?? 0,
        videosHidden: j['videosHidden'] == true,
        videosHiddenMessage: j['videosHiddenMessage']?.toString() ?? '',
        appLocked: j['appLocked'] == true,
        lockMessage: j['lockMessage']?.toString() ?? '',
        updateMessage: j['updateMessage']?.toString() ?? '',
        updateUrl: j['updateUrl']?.toString() ?? '',
        updateImageUrl: j['updateImageUrl']?.toString() ?? '',
        packages: ((j['packages'] as List?) ?? const [])
            .whereType<Map>()
            .map((p) => XPackage(
                  cards: (p['cards'] as num?)?.toInt() ?? 0,
                  price: p['price']?.toString() ?? '',
                  days: (p['days'] as num?)?.toInt() ?? 0,
                  desc: p['desc']?.toString() ?? '',
                ))
            .toList(),
        chatEnabled: j['chatEnabled'] != false,
        chatReadOnly: j['chatReadOnly'] == true,
        chatTheme: j['chatTheme']?.toString() ?? 'bubble',
        chatWelcome: j['chatWelcome']?.toString() ?? '',
        chatMaxLength: (j['chatMaxLength'] as num?)?.toInt() ?? 1000,
        chatImagesEnabled: j['chatImagesEnabled'] != false,
        chatWriteScope: j['chatWriteScope']?.toString() ?? 'registered',
        chatMediaScope: j['chatMediaScope']?.toString() ?? 'subscribers',
        chatMaxMediaMb: (j['chatMaxMediaMb'] as num?)?.toInt() ?? 12,
        chatMediaSeconds: (j['chatMediaSeconds'] as num?)?.toInt() ?? 120,
        chatPollMs: (j['chatPollMs'] as num?)?.toInt() ?? 4000,
        chatRooms: ((j['chatRooms'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ChatRoom.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'dailyFreeQuota': dailyFreeQuota,
        'minVersion': minVersion,
        'blockedVersions': blockedVersions,
        'telegramLink': telegramLink,
        'schematicsLocked': schematicsLocked,
        'compatLocked': compatLocked,
        'compatSearchCost': compatSearchCost,
        'schemFilePrice': schemFilePrice,
        'dailyGiftAmount': dailyGiftAmount,
        'videosHidden': videosHidden,
        'videosHiddenMessage': videosHiddenMessage,
        'appLocked': appLocked,
        'lockMessage': lockMessage,
        'updateMessage': updateMessage,
        'updateUrl': updateUrl,
        'updateImageUrl': updateImageUrl,
        'packages': packages
            .map((p) => {
                  'cards': p.cards,
                  'price': p.price,
                  'days': p.days,
                  'desc': p.desc,
                })
            .toList(),
        'chatEnabled': chatEnabled,
        'chatReadOnly': chatReadOnly,
        'chatTheme': chatTheme,
        'chatWelcome': chatWelcome,
        'chatMaxLength': chatMaxLength,
        'chatImagesEnabled': chatImagesEnabled,
        'chatWriteScope': chatWriteScope,
        'chatMediaScope': chatMediaScope,
        'chatMaxMediaMb': chatMaxMediaMb,
        'chatMediaSeconds': chatMediaSeconds,
        'chatPollMs': chatPollMs,
        'chatRooms': chatRooms
            .map((r) => {'id': r.id, 'name': r.name, 'icon': r.icon})
            .toList(),
      };
}

/// باقة بطاقات مخططات — يتحكم بها المالك من اللوحة
class XPackage {
  XPackage({this.cards = 0, this.price = '', this.days = 0, this.desc = ''});
  int cards;
  String price;
  int days;
  String desc;
}

/// نتيجة دخول شركة في التوافقات — الخصم يقع هنا مرة واحدة في اليوم.
class CompatOpenResult {
  const CompatOpenResult({
    this.charged = false,
    this.remaining = -1,
    this.balance = -1,
    this.source = '',
  });

  final bool charged;

  /// ما تبقّى من المنحة اليومية، أو -1 إذا غير معروف.
  final int remaining;

  /// رصيد العملات المتبقي، أو -1 إذا غير معروف.
  final int balance;

  /// من أين خُصم: free (المنحة اليومية) أو coins (العملات) أو غير ذلك.
  final String source;
}

class CompatSearchResult {
  const CompatSearchResult({
    required this.records,
    required this.types,
    this.charged = false,
    this.remaining = -1,
    this.balance = -1,
    this.source = '',
  });

  final List<dynamic> records;

  /// أنواع القطع الموجودة فعلاً لهذه الشركة — تُشتق على الخادم بلا أعداد.
  final List<String> types;
  final bool charged;

  /// ما تبقّى من الحصة المجانية اليومية، أو -1 إذا لا حصة/غير معروف.
  final int remaining;

  /// رصيد العملات المتبقي، أو -1 إذا لا رصيد/غير معروف.
  final int balance;

  /// من أين خُصم: free (الحصة المجانية) أو coins (العملات) أو غير ذلك.
  final String source;
}

// ══════════════════════════ الدردشة ══════════════════════════

/// قسم دردشة — معرّف واسم وأيقونة، يعدّلها المالك من لوحته.
class ChatRoom {
  const ChatRoom({required this.id, required this.name, required this.icon});
  final String id;
  final String name;
  final String icon;

  factory ChatRoom.fromJson(Map<String, dynamic> j) => ChatRoom(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        icon: j['icon']?.toString() ?? 'chat',
      );
}

/// كاتب الرسالة: كنية وصورة شخصية من ملف الدردشة.
class ChatAuthor {
  const ChatAuthor({this.id = '', this.nickname = '', this.avatarUrl = ''});
  final String id;
  final String nickname;
  final String avatarUrl;

  /// الاسم المعروض: الكنية إن وُجدت، وإلا «عضو».
  String get label => nickname.trim().isEmpty ? 'عضو' : nickname.trim();

  factory ChatAuthor.fromJson(Map<String, dynamic> j) => ChatAuthor(
        id: j['id']?.toString() ?? '',
        nickname: j['nickname']?.toString() ?? '',
        avatarUrl: j['avatarUrl']?.toString() ?? '',
      );
}

/// رسالة دردشة: نص أو صورة أو صوت أو فيديو، مع من رآها.
/// مقتطف الرسالة المقتبَسة في ردّ.
///
/// يأتي جاهزاً من الخادم مع كل ردّ: عرضه في العميل يعني أن الردّ يظل مفهوماً
/// ولو كانت الرسالة الأصلية حُذفت أو خرجت من الصفحة المحمّلة.
class ChatReplyPreview {
  const ChatReplyPreview({
    required this.id,
    this.body = '',
    this.kind = 'text',
    this.nickname = '',
  });

  final String id;
  final String body;
  final String kind;
  final String nickname;

  /// نصّ معروض بدل الفراغ حين لا يكون للرسالة المقتبَسة نصّ.
  String get label {
    final t = body.trim();
    if (t.isNotEmpty) return t;
    switch (kind) {
      case 'image':
        return 'صورة';
      case 'video':
        return 'مقطع فيديو';
      case 'audio':
        return 'رسالة صوتية';
      default:
        return 'رسالة';
    }
  }

  factory ChatReplyPreview.fromJson(Map<String, dynamic> j) =>
      ChatReplyPreview(
        id: j['id']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'text',
        nickname: j['nickname']?.toString() ?? '',
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.kind,
    required this.body,
    required this.mediaUrl,
    required this.mediaMime,
    required this.mediaSize,
    required this.at,
    this.seconds = 0,
    required this.mine,
    required this.author,
    this.seenBy = const [],
    this.waveform = const [],
    this.pending = false,
    this.failed = false,
    this.replyTo = '',
    this.replyPreview,
  });

  final String id;
  final String roomId;

  /// text | image | audio | video | system
  final String kind;
  final String body;
  final String mediaUrl;
  final String mediaMime;
  final int mediaSize;
  final int at;
  final bool mine;
  final ChatAuthor author;

  /// من رأى الرسالة (حتى 8 صور مصغّرة).
  final List<ChatAuthor> seenBy;

  /// مخطط موجة الرسالة الصوتية — قيم 0..1. فارغ يعني مخططاً افتراضياً.
  final List<double> waveform;
  /// مدة المقطع بالثواني كما أرسلها صاحبها — تُعرض قبل بدء التشغيل.
  final int seconds;

  /// أُرسلت محلياً ولم يتأكد وصولها بعد — تُعرض باهتة.
  final bool pending;
  final bool failed;

  /// معرّف الرسالة التي يردّ عليها هذا المستخدم (فارغ إن لم يكن ردّاً).
  final String replyTo;

  /// مقتطف الرسالة المقتبَسة كما أرسله الخادم — يُعرض في رأس الردّ بلا
  /// نداء إضافي، ولو كانت الرسالة الأصلية خارج الصفحة المحمّلة.
  final ChatReplyPreview? replyPreview;

  bool get isText => kind == 'text' || kind == 'system';
  bool get isImage => kind == 'image';
  bool get isAudio => kind == 'audio';
  bool get isVideo => kind == 'video';

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(at);

  /// سطر مختصر للرسالة يُعرض في إشعار الهاتف.
  ///
  /// رسالة الوسائط جسدها فارغ غالباً، فتظهر في الإشعار فراغاً بلا معنى.
  /// نستبدلها بوصف قصير، ونجعل الوصف بلا علامة «صورة:» المكرّرة.
  String get preview {
    final text = body.trim();
    if (text.isNotEmpty) {
      return text.length <= 120 ? text : '${text.substring(0, 120)}…';
    }
    if (isImage) return 'أرسل صورة';
    if (isVideo) return 'أرسل مقطع فيديو';
    if (isAudio) {
      final d = seconds > 0 ? ' ($seconds ث)' : '';
      return 'أرسل رسالة صوتية$d';
    }
    return '';
  }

  ChatMessage copyWith({
    String? id,
    String? mediaUrl,
    List<ChatAuthor>? seenBy,
    List<double>? waveform,
    bool? pending,
    bool? failed,
    String? replyTo,
    ChatReplyPreview? replyPreview,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        roomId: roomId,
        kind: kind,
        body: body,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        mediaMime: mediaMime,
        mediaSize: mediaSize,
        at: at,
        seconds: seconds,
        mine: mine,
        author: author,
        seenBy: seenBy ?? this.seenBy,
        waveform: waveform ?? this.waveform,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
        replyTo: replyTo ?? this.replyTo,
        replyPreview: replyPreview ?? this.replyPreview,
      );

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: j['id']?.toString() ?? '',
        roomId: j['roomId']?.toString() ?? '',
        kind: j['kind']?.toString() ?? 'text',
        body: j['body']?.toString() ?? '',
        mediaUrl: j['mediaUrl']?.toString() ?? '',
        mediaMime: j['mediaMime']?.toString() ?? '',
        mediaSize: (j['mediaSize'] as num?)?.toInt() ?? 0,
        at: (j['at'] as num?)?.toInt() ?? 0,
        seconds: (j['seconds'] as num?)?.toInt() ?? 0,
        mine: j['mine'] == true,
        author: ChatAuthor.fromJson(
            (j['author'] as Map?)?.cast<String, dynamic>() ?? const {}),
        seenBy: ((j['seenBy'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ChatAuthor.fromJson(e.cast<String, dynamic>()))
            .toList(),
        waveform: _parseWaveform(j['waveform']),
        replyTo: j['replyTo']?.toString() ?? '',
        replyPreview: j['replyPreview'] is Map
            ? ChatReplyPreview.fromJson(
                (j['replyPreview'] as Map).cast<String, dynamic>())
            : null,
      );

  /// يفكّ مخطط الموجة من سلسلة «0.120,0.480,...».
  ///
  /// صيغة نصّية لأن JSON يحوّل كل رقم إلى عنصر مستقل، ورسالة صوتية بعشرات
  /// النقاط تُثقل الرد بلا سبب. القيم خارج النطاق أو غير الرقمية تُسقَط بدل
  /// أن تُرسم مشوّهة.
  static List<double> _parseWaveform(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    final out = <double>[];
    for (final part in raw.split(',')) {
      final v = double.tryParse(part);
      if (v != null) out.add(v.clamp(0.0, 1.0));
    }
    return out;
  }
}

/// حالة الدردشة كما يراها المستخدم الحالي: الصلاحيات والأقسام والقيود.
class ChatState {
  const ChatState({
    this.enabled = false,
    this.readOnly = false,
    this.theme = 'bubble',
    this.welcome = '',
    this.maxLength = 1000,
    this.imagesEnabled = true,
    this.writeScope = 'registered',
    this.mediaScope = 'subscribers',
    this.maxMediaMb = 200,
    this.mediaSeconds = 120,
    // 7 ثوان لا 4: كل دورة تكلّف طلبين (الرسائل والحالة)، و4 ثوان تضاعف
    // الطلبات بلا فرق محسوس — الرسالة تصل خلال ثوان في الحالتين.
    this.pollMs = 7000,
    this.rooms = const [],
    this.canWrite = false,
    this.writeBlockedReason = '',
    this.canSendMedia = false,
    this.mediaBlockedReason = '',
    this.isSubscriber = false,
    this.myNickname = '',
    this.myAvatarUrl = '',
    this.notify = true,
    this.role = 'guest',
    this.muted = false,
    this.kicked = false,
    this.restrictionReason = '',
  });

  final bool enabled;
  final bool readOnly;
  final String theme;
  final String welcome;
  final int maxLength;
  final bool imagesEnabled;
  final String writeScope;
  final String mediaScope;
  final int maxMediaMb;
  final int mediaSeconds;
  final int pollMs;
  final List<ChatRoom> rooms;
  final bool canWrite;
  final String writeBlockedReason;
  final bool canSendMedia;
  final String mediaBlockedReason;
  final bool isSubscriber;
  final String myNickname;
  final String myAvatarUrl;
  final bool notify;
  final String role;
  final bool muted;
  final bool kicked;
  final String restrictionReason;

  factory ChatState.fromJson(Map<String, dynamic> j) {
    final me = (j['me'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rest =
        (j['restriction'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ChatState(
      enabled: j['enabled'] == true,
      readOnly: j['readOnly'] == true,
      theme: j['theme']?.toString() ?? 'bubble',
      welcome: j['welcome']?.toString() ?? '',
      maxLength: (j['maxLength'] as num?)?.toInt() ?? 1000,
      imagesEnabled: j['imagesEnabled'] != false,
      writeScope: j['writeScope']?.toString() ?? 'registered',
      mediaScope: j['mediaScope']?.toString() ?? 'subscribers',
      maxMediaMb: (j['maxMediaMb'] as num?)?.toInt() ?? 200,
      mediaSeconds: (j['mediaSeconds'] as num?)?.toInt() ?? 120,
      pollMs: (j['pollMs'] as num?)?.toInt() ?? 7000,
      rooms: ((j['rooms'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => ChatRoom.fromJson(e.cast<String, dynamic>()))
          .toList(),
      canWrite: j['canWrite'] == true,
      writeBlockedReason: j['writeBlockedReason']?.toString() ?? '',
      canSendMedia: j['canSendMedia'] == true,
      mediaBlockedReason: j['mediaBlockedReason']?.toString() ?? '',
      isSubscriber: j['isSubscriber'] == true,
      myNickname: me['nickname']?.toString() ?? '',
      myAvatarUrl: me['avatarUrl']?.toString() ?? '',
      notify: me['notify'] != false,
      role: me['role']?.toString() ?? 'guest',
      muted: rest['muted'] == true,
      kicked: rest['kicked'] == true,
      restrictionReason: rest['reason']?.toString() ?? '',
    );
  }
}

/// صفحة رسائل من الخادم: الرسائل وهل توجد أقدم منها.
class ChatPage {
  const ChatPage({
    required this.messages,
    this.hasMore = false,
    this.members,
    this.online,
  });
  final List<ChatMessage> messages;
  final bool hasMore;

  /// عدد من شاركوا في القسم، وعدد المتصلين الآن.
  ///
  /// يُرسلهما الخادم في وضع الفتح وحده (لا في التحديث الدوري) فيكونان
  /// null في معظم النبضات — والقيمة القديمة تبقى معروضة حتى يتغيّر القسم.
  final int? members;
  final int? online;
}

/// إجراء إشراف على عضو: كتم أو طرد، وقد يكون مقيّداً بقسم واحد.
class ChatAction {
  const ChatAction({
    required this.id,
    required this.userId,
    required this.kind,
    required this.roomId,
    required this.reason,
    required this.until,
    required this.active,
    required this.username,
  });

  final String id;
  final String userId;

  /// mute | kick
  final String kind;
  final String roomId;
  final String reason;
  final int until;
  final bool active;
  final String username;

  bool get isMute => kind == 'mute';
  bool get isPermanent => until == 0;

  factory ChatAction.fromJson(Map<String, dynamic> j) => ChatAction(
        id: j['id']?.toString() ?? '',
        userId: j['userId']?.toString() ?? '',
        kind: j['kind']?.toString() ?? '',
        roomId: j['roomId']?.toString() ?? '',
        reason: j['reason']?.toString() ?? '',
        until: (j['until'] as num?)?.toInt() ?? 0,
        active: j['active'] == true,
        username: j['username']?.toString() ?? '',
      );
}

/// فيديو داخل دورة.
///
/// الفيديو المقفل يصل بلا مدة ولا حجم ولا رابط بث — الخادم لا يرسلها أصلاً.
/// لذلك `streamUrl` فارغ للمقفل، وإطلاق البث يستلزم فتح الدورة بمفتاح.
class CourseVideo {
  const CourseVideo({
    required this.id,
    required this.title,
    this.description = '',
    this.mode = 'locked',
    this.sort = 0,
    this.durationS = 0,
    this.sizeBytes = 0,
    this.playable = false,
    this.streamUrl = '',
    this.thumbUrl = '',
  });

  final String id;
  final String title;
  final String description;

  /// free = متاح للجميع، locked = يحتاج فتح الدورة.
  final String mode;
  final int sort;
  final int durationS;
  final int sizeBytes;

  /// هل يملك الخادم إذن البث لهذا المستخدم؟ هو مصدر الحقيقة لا الواجهة.
  final bool playable;
  final String streamUrl;

  /// مصغّرة يرفعها المالك. تُرسل للدرس المقفل أيضاً: الصورة لا تكشف المقطع،
  /// ووجودها مع قفل واضح هو ما يسمح للمستخدم بأن يقرّر ما يفتحه.
  final String thumbUrl;

  /// فيديو مجاني يُعرض بشارة «مجاني» بدل القفل.
  bool get isFree => mode == 'free';

  String get durationLabel {
    if (durationS <= 0) return '';
    final m = durationS ~/ 60;
    final s = durationS % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final mb = sizeBytes / (1024 * 1024);
    return mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB'
                      : '${mb.toStringAsFixed(0)} MB';
  }

  factory CourseVideo.fromJson(Map<String, dynamic> j) => CourseVideo(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        mode: j['mode']?.toString() ?? 'locked',
        sort: (j['sort'] as num?)?.toInt() ?? 0,
        durationS: (j['durationS'] as num?)?.toInt() ?? 0,
        sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
        playable: j['playable'] == true,
        streamUrl: j['streamUrl']?.toString() ?? '',
        thumbUrl: j['thumbUrl']?.toString() ?? '',
      );
}

/// دورة = قائمة تشغيل من الفيديوهات، مع قفل اختياري يُفتح بمفتاح المالك.
class Course {
  const Course({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.description = '',
    this.coverUrl = '',
    this.locked = false,
    this.unlocked = false,
    this.videos = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final String coverUrl;

  /// الدورة تتطلّب مفتاحاً.
  final bool locked;

  /// هذا الجهاز فتحها بالفعل (أو هي مجانية أصلاً).
  final bool unlocked;

  final List<CourseVideo> videos;

  int get videoCount => videos.length;
  int get freeCount => videos.where((v) => v.isFree).length;

  /// الفيديوهات المتاحة الآن — كلها إن كانت مفتوحة، والمجانية فقط إن كانت مقفلة.
  List<CourseVideo> get playableVideos =>
      videos.where((v) => v.playable).toList();

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        subtitle: j['subtitle']?.toString() ?? '',
        description: j['description']?.toString() ?? '',
        coverUrl: j['coverUrl']?.toString() ?? '',
        locked: j['locked'] == true,
        unlocked: j['unlocked'] == true,
        videos: ((j['videos'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => CourseVideo.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}
