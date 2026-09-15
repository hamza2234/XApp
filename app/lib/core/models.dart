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
    this.guestFileQuota = 5,
    this.minVersion = 1,
    this.blockedVersions = const [],
    this.telegramLink = '',
    this.schematicsLocked = false,
    this.compatLocked = false,
    this.appLocked = false,
    this.lockMessage = '',
    this.updateMessage = '',
    this.updateUrl = '',
    this.updateImageUrl = '',
  });
  int guestFileQuota;
  int minVersion;
  List<int> blockedVersions;
  String telegramLink;
  bool schematicsLocked;
  bool compatLocked;
  bool appLocked;
  String lockMessage;
  String updateMessage;
  String updateUrl;
  String updateImageUrl;

  factory XSettings.fromJson(Map<String, dynamic> j) => XSettings(
        guestFileQuota: (j['guestFileQuota'] as num?)?.toInt() ?? 5,
        minVersion: (j['minVersion'] as num?)?.toInt() ?? 1,
        blockedVersions:
            ((j['blockedVersions'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
        telegramLink: j['telegramLink']?.toString() ?? '',
        schematicsLocked: j['schematicsLocked'] == true,
        compatLocked: j['compatLocked'] == true,
        appLocked: j['appLocked'] == true,
        lockMessage: j['lockMessage']?.toString() ?? '',
        updateMessage: j['updateMessage']?.toString() ?? '',
        updateUrl: j['updateUrl']?.toString() ?? '',
        updateImageUrl: j['updateImageUrl']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'guestFileQuota': guestFileQuota,
        'minVersion': minVersion,
        'blockedVersions': blockedVersions,
        'telegramLink': telegramLink,
        'schematicsLocked': schematicsLocked,
        'compatLocked': compatLocked,
        'appLocked': appLocked,
        'lockMessage': lockMessage,
        'updateMessage': updateMessage,
        'updateUrl': updateUrl,
        'updateImageUrl': updateImageUrl,
      };
}
