import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../core/api.dart';
import '../core/config.dart';
import 'theme.dart';

/// عارض وسائط الدردشة — صورة بملء الشاشة أو مقطع فيديو بمشغّل مدمج.
///
/// الوسائط محمية بتوقيع الطلب، ومشغّل الفيديو لا يعرف الترويسات، فنحمّل
/// الملف موقّعاً إلى مخزن مؤقت ثم نشغّله من الملف المحلي.
class MediaViewer extends StatefulWidget {
  const MediaViewer({
    super.key,
    required this.api,
    required this.url,
    this.title = '',
    this.isVideo = false,
  });

  final Api api;
  final String url;
  final String title;
  final bool isVideo;

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  VideoPlayerController? _video;
  bool _preparing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) _prepareVideo();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _prepareVideo() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final bytes = await widget.api
          .getBytes(widget.url)
          .then((r) => r.bytes)
          .timeout(const Duration(minutes: 3));
      final dir = await getTemporaryDirectory();
      final ext = widget.url.split('.').last;
      final f = File('${dir.path}/x_video_${widget.url.hashCode.abs()}.$ext');
      await f.writeAsBytes(bytes);
      final c = VideoPlayerController.file(f);
      await c.initialize();
      await c.setLooping(false);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _preparing = false;
      });
      await c.play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _preparing = false;
          _error = 'تعذر تشغيل المقطع';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(.6),
        foregroundColor: Colors.white,
        title: Text(widget.title.isEmpty ? 'وسائط' : widget.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'إغلاق',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Center(child: _body()),
    );
  }

  Widget _body() {
    if (widget.isVideo) {
      if (_preparing) {
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: XTheme.accent),
            SizedBox(height: 14),
            Text('جاري تحضير المقطع…',
                style: TextStyle(color: Colors.white70)),
          ],
        );
      }
      if (_error != null) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: XTheme.danger, size: 46),
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                _video?.dispose();
                _video = null;
                _prepareVideo();
              },
              style: FilledButton.styleFrom(backgroundColor: XTheme.accent),
              child: const Text('إعادة المحاولة'),
            ),
          ],
        );
      }
      final v = _video;
      if (v == null) return const SizedBox.shrink();
      return AspectRatio(
        aspectRatio: v.value.aspectRatio == 0 ? 16 / 9 : v.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(v),
            VideoProgressIndicator(v, allowScrubbing: true,
                colors: const VideoProgressColors(
                    playedColor: XTheme.accent,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white10)),
            Center(
              child: IconButton(
                iconSize: 58,
                color: Colors.white.withOpacity(.85),
                icon: Icon(v.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill),
                onPressed: () =>
                    v.value.isPlaying ? v.pause() : v.play(),
              ),
            ),
          ],
        ),
      );
    }

    return InteractiveViewer(
      maxScale: 5,
      child: Image.network(
        widget.url.startsWith('/') ? '$kApiBase${widget.url}' : widget.url,
        headers: widget.url.startsWith('/')
            ? widget.api.signFor('GET', widget.url)
            : null,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, p) => p == null
            ? child
            : const CircularProgressIndicator(color: XTheme.accent),
        errorBuilder: (context, error, stack) => const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Colors.white54, size: 46),
            SizedBox(height: 12),
            Text('تعذر عرض الصورة',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
