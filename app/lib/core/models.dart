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
    this.appLocked = false,
    this.lockMessage = '',
    this.updateMessage = '',
    this.updateUrl = '',
    this.updateImageUrl = '',
    List<XPackage>? packages,
  }) : packages = packages ?? [];
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
  bool appLocked;
  String lockMessage;
  String updateMessage;
  String updateUrl;
  String updateImageUrl;
  List<XPackage> packages;

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
      );

  Map<String, dynamic> toJson() => {
        'dailyFreeQuota': dailyFreeQuota,
        'minVersion': minVersion,
        'blockedVersions': blockedVersions,
        'telegramLink': telegramLink,
        'schematicsLocked': schematicsLocked,
        'compatLocked': compatLocked,
        'compatSearchCost': compatSearchCost,
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
