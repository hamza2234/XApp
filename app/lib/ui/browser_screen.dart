import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/models.dart';
import 'theme.dart';
import 'viewer_screen.dart';

/// متصفح المخططات: موديلات الشركة ← مجلدات ← ملفات
/// يحافظ على ترتيب كلاودفلير كما هو.
class BrowserScreen extends StatefulWidget {
  const BrowserScreen(
      {super.key,
      required this.api,
      required this.brand,
      required this.onFileOpened});
  final Api api;
  final SchemBrand brand;
  final VoidCallback onFileOpened;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  List<SchemModel>? _models;
  String? _error;
  final _q = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<void> _load(String q) async {
    try {
      final list = await widget.api.schemModels(widget.brand.id, q: q);
      if (!mounted) return;
      setState(() {
        _models = list.map((e) => SchemModel.fromJson(e)).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.brand.name)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: TextField(
            controller: _q,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(
                  const Duration(milliseconds: 400), () => _load(v.trim()));
            },
            decoration: const InputDecoration(
              hintText: 'ابحث عن موديل…',
              prefixIcon: Icon(Icons.search, color: XTheme.textDim),
            ),
          ),
        ),
        Expanded(child: _body()),
      ]),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
          child: Text(_error!, style: const TextStyle(color: XTheme.danger)));
    }
    if (_models == null) {
      return const Center(
          child: CircularProgressIndicator(color: XTheme.accent));
    }
    if (_models!.isEmpty) {
      return const Center(
          child: Text('لا توجد موديلات',
              style: TextStyle(color: XTheme.textDim)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      itemCount: _models!.length,
      itemBuilder: (context, i) {
        final m = _models![i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.phone_android,
                      size: 20, color: XTheme.accent),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(m.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15))),
                ]),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: m.folders.map((f) {
                    return ActionChip(
                      avatar: const Icon(Icons.folder_outlined,
                          size: 16, color: XTheme.cyan),
                      label: Text(f.category,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      backgroundColor: XTheme.cyan.withOpacity(.08),
                      side: BorderSide(
                          color: XTheme.cyan.withOpacity(.25)),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => FolderScreen(
                                  api: widget.api,
                                  title: '${m.name} — ${f.category}',
                                  folderId: f.id,
                                  onFileOpened: widget.onFileOpened))),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// شاشة محتويات مجلد — مجلدات فرعية وملفات (PDF/PNG)
class FolderScreen extends StatefulWidget {
  const FolderScreen(
      {super.key,
      required this.api,
      required this.title,
      required this.folderId,
      required this.onFileOpened});
  final Api api;
  final String title;
  final String folderId;
  final VoidCallback onFileOpened;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  List<SchemEntry>? _entries;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.schemFiles(widget.folderId);
      if (!mounted) return;
      setState(() {
        _entries = list.map((e) => SchemEntry.fromJson(e)).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _open(SchemEntry e) {
    if (e.isFolder) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => FolderScreen(
              api: widget.api,
              title: e.cleanName,
              folderId: e.id,
              onFileOpened: widget.onFileOpened)));
    } else {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ViewerScreen(
              api: widget.api,
              entry: e,
              onOpened: widget.onFileOpened)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.title,
              style: const TextStyle(fontSize: 16)),
      ),
      body: _entries == null
          ? (_error != null
              ? Center(
                  child: Text(_error!,
                      style: const TextStyle(color: XTheme.danger)))
              : const Center(
                  child:
                      CircularProgressIndicator(color: XTheme.accent)))
          : _entries!.isEmpty
              ? const Center(
                  child: Text('المجلد فارغ',
                      style: TextStyle(color: XTheme.textDim)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  itemCount: _entries!.length,
                  itemBuilder: (context, i) {
                    final e = _entries![i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassCard(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        onTap: () => _open(e),
                        child: Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: _color(e).withOpacity(.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(_icon(e),
                                color: _color(e), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(e.cleanName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5)),
                                if (e.sizeText != null)
                                  Text(e.sizeText!,
                                      style: const TextStyle(
                                          color: XTheme.textDim,
                                          fontSize: 11)),
                              ],
                            ),
                          ),
                          Icon(
                              e.isFolder
                                  ? Icons.chevron_left
                                  : Icons.open_in_new,
                              size: 18,
                              color: XTheme.textDim),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  IconData _icon(SchemEntry e) {
    if (e.isFolder) return Icons.folder;
    if (e.isPdf) return Icons.picture_as_pdf;
    if (e.isImage) return Icons.image;
    return Icons.insert_drive_file;
  }

  Color _color(SchemEntry e) {
    if (e.isFolder) return XTheme.gold;
    if (e.isPdf) return XTheme.danger;
    if (e.isImage) return XTheme.ok;
    return XTheme.textDim;
  }
}
