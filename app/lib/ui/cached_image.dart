import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/avatar_cache.dart';
import 'theme.dart';

/// عرض الصور عبر [AvatarCache] — بلا وميض وبلا إعادة تنزيل.
///
/// المفتاح هو الرابط وحده، بينما `Image.network` يضمّ الترويسات إلى مفتاحه؛
/// وتوقيع الطلب يتجدّد فتُعتبر الصورة جديدة فتُنزَّل من جديد يومض العرض.

/// صورة عضو من الكاش: بلا وميض عند إعادة البناء.
///
/// الترتيب مقصود: نرسم ما في الذاكرة فوراً بلا `FutureBuilder` يمرّ بلحظة
/// فراغ، فإن لم تكن محفوظة نطلبها مرة واحدة ونرسم النتيجة. الحالة تُحفظ في
/// `State` فلا يُعاد الطلب عند كل `build`.
class CachedAvatar extends StatefulWidget {
  const CachedAvatar({
    required this.url,
    required this.size,
    this.headers,
    this.showInitials = true,
    this.initials = '؟',
  });

  final String url;
  final double size;
  final Map<String, String>? headers;
  final bool showInitials;
  final String initials;

  @override
  State<CachedAvatar> createState() => _CachedAvatarState();
}

class _CachedAvatarState extends State<CachedAvatar> {
  Uint8List? _bytes;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _bytes = AvatarCache.avatars.peek(widget.url);
    if (_bytes == null) _request();
  }

  @override
  void didUpdateWidget(covariant CachedAvatar old) {
    super.didUpdateWidget(old);
    // صورة العضو قد تتغيّر: نُبطل البايتات القديمة ونطلب الجديدة.
    if (old.url != widget.url) {
      _bytes = AvatarCache.avatars.peek(widget.url);
      _asked = false;
      if (_bytes == null) _request();
    }
  }

  Future<void> _request() async {
    if (_asked) return;
    _asked = true;
    final bytes =
        await AvatarCache.avatars.load(widget.url, headers: widget.headers);
    if (!mounted) return;
    if (bytes != null) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(bytes,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true);
    }
    // بديل ثابت الحجم يمنع القفزة أثناء الجلب، والشبكة يمرّ عليها الكاش وحده.
    return Center(
      child: widget.showInitials
          ? Text(widget.initials,
              style: TextStyle(
                  fontSize: widget.size * .42,
                  fontWeight: FontWeight.w900,
                  color: Colors.white))
          : Icon(Icons.person, size: widget.size * .6, color: XTheme.textDim),
    );
  }
}


/// صورة شبكية من الكاش: تُرسم فوراً إن كانت محفوظة، وتُطلب مرة واحدة.
///
/// لماذا لا `Image.network`؟ لأن مفتاح تخزينه يشمل الترويسات، وتوقيع الطلب
/// يتجدد فتتغيّر الترويسة وتُعتبر الصورة جديدة عند كل تجديد — فتُنزَّل مرة
/// أخرى ويومض العرض في القائمة. هنا المفتاح هو الرابط وحده، والبايتات تبقى
/// في الذاكرة والقرص فتظهر فوراً وفي وضع الطيران أيضاً.
class CachedImage extends StatefulWidget {
  const CachedImage({
    super.key,
    required this.url,
    required this.cache,
    this.headers,
    this.fit = BoxFit.cover,
    this.onTap,
  });

  final String url;
  final AvatarCache cache;
  final Map<String, String>? headers;
  final BoxFit fit;
  final VoidCallback? onTap;

  @override
  State<CachedImage> createState() => _CachedImageState();
}

class _CachedImageState extends State<CachedImage> {
  Uint8List? _bytes;
  bool _failed = false;
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _bytes = widget.cache.peek(widget.url);
    if (_bytes == null) _request();
  }

  @override
  void didUpdateWidget(covariant CachedImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = widget.cache.peek(widget.url);
      _failed = false;
      _asked = false;
      if (_bytes == null) _request();
    }
  }

  Future<void> _request() async {
    if (_asked) return;
    _asked = true;
    final bytes = await widget.cache.load(widget.url, headers: widget.headers);
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _failed = bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final image = bytes != null
        ? Image.memory(bytes,
            fit: widget.fit, gaplessPlayback: true, width: double.infinity)
        : (_failed
            ? Container(
                color: XTheme.surface2,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: XTheme.textDim, size: 26),
                    const SizedBox(height: 6),
                    Text('تعذر تحميل الصورة',
                        style:
                            TextStyle(fontSize: 10.5, color: XTheme.textDim)),
                  ],
                ),
              )
            : Container(
                color: XTheme.surface2,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: XTheme.accent),
                ),
              ));
    if (widget.onTap == null) return image;
    return GestureDetector(onTap: widget.onTap, child: image);
  }
}
