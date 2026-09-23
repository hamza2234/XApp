/// شاشة الدورات — قوائم تشغيل على طراز يوتيوب، بقفل يفتحه مفتاح المالك.
///
/// القاعدة الأمنية في هذه الشاشة: الخادم هو من يقرّر. كل فيديو يصل ومعه
/// `playable`، والمقفل يصل بلا رابط بث أصلاً. لذلك الواجهة هنا لا تحرس شيئاً
/// ولا «تُخفي» شيئاً — هي تعرض ما وصلها فقط. هذا يمنع أي منطق أمني في العميل
/// يمكن تجاوزه بتعديل التطبيق.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/api.dart';
import '../core/app_config.dart';
import '../core/config.dart';
import '../core/media_proxy.dart';
import '../core/models.dart';
import 'cached_image.dart';
import 'external_link.dart';
import 'secure_screen.dart';
import 'theme.dart';

class CoursesScreen extends StatefulWidget {
  const CoursesScreen({super.key, required this.api});

  final Api api;

  @override
  State<CoursesScreen> createState() => _CoursesScreenState();
}

class _CoursesScreenState extends State<CoursesScreen>
    with AutomaticKeepAliveClientMixin {
  List<Course> _courses = const [];
  String _telegram = '';
  bool _loading = true;
  String? _error;

  /// الدورة المختارة — فارغ يعني عرض الشبكة (الشاشة الرئيسية).
  Course? _open;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.api.courses();
      if (!mounted) return;
      setState(() {
        _courses = r.courses;
        _telegram = r.telegramUrl;
        _loading = false;
        // الدورة المفتوحة تُحدَّث ببياناتها الجديدة بدل البقاء على نسخة قديمة
        // — هذا ما يجعل الفتح بالمفتاح ينعكس فوراً بلا إعادة تنقّل.
        final id = _open?.id;
        if (id != null) {
          _open = _courses.where((c) => c.id == id).firstOrNull;
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر تحميل الدورات — تحقق من الإنترنت';
        });
      }
    }
  }

  /// يعرض حوار المفتاح ويتفعّله. الاستحقاق يأتي من الخادم لا من العميل.
  Future<void> _askForKey(Course course) async {
    final controller = TextEditingController();
    final busy = ValueNotifier(false);
    final error = ValueNotifier('');
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(XTheme.rLg)),
        title: Row(children: [
          const Icon(Icons.key, color: XTheme.accent, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('فتح الدورة',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(course.title,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'أدخل المفتاح الذي حصلت عليه من المالك. المفتاح يفتح هذه الدورة '
              'على هذا الجهاز، وكل فيديو يُنزَّل لاحقاً في هذه الدورة يفتح تلقائياً.',
              style: TextStyle(fontSize: 12.5, color: XTheme.textDim, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX',
                errorText: null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(XTheme.rSm)),
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: error,
              builder: (_, e, __) => e.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(e,
                          style: const TextStyle(
                              color: XTheme.danger, fontSize: 12.5)),
                    ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('إلغاء', style: TextStyle(color: XTheme.textDim)),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (_, b, __) => FilledButton(
              onPressed: b ? null : () async {
                final c = controller.text.trim();
                if (c.isEmpty) return;
                busy.value = true;
                error.value = '';
                try {
                  final r = await widget.api.redeemCourseKey(c);
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, r['message']?.toString() ?? 'تم الفتح');
                } on ApiException catch (e) {
                  busy.value = false;
                  error.value = e.message;
                } catch (_) {
                  busy.value = false;
                  error.value = 'تعذر الاتصال — تحقق من الإنترنت';
                }
              },
              child: b
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('فتح'),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    busy.dispose();
    error.dispose();
    if (code == null || !mounted) return;
    _toast(code);
    // إعادة الجلب من الخادم: هي مصدر الحقيقة، ولا نفتح شيئاً محلياً.
    await _load();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: XTheme.surface2,
      ));
  }

  Future<void> _contactOwner() async {
    final link = _telegram.trim();
    if (link.isEmpty) {
      _toast('رابط التواصل غير متاح حالياً');
      return;
    }
    await openExternal(context, link, label: 'المالك');
  }

  /// يفتح فيديو. المقفل يستقبل طلب المفتاح فوراً، والمتاح وحده يذهب للمشغّل.
  ///
  /// لا ننتقل إلى المشغّل أبداً إن كان الدرس مقفلاً: الانتقال ثم الفشل هو ما
  /// كان يُظهر شاشة سوداء تنتهي برسالة قفل. أما فيديو مُباح لكن تعذّر بناؤه
  /// (مشكلة شبكة أو مزوّد) فيُفتح المشغّل، فهناك رسالة خطأ وزرّ إعادة محاولة
  /// — ولا معنى لطلب مفتاح لا يحلّ مشكلة ليست قفلاً.
  Future<void> _openVideo(Course course, CourseVideo video) async {
    final fresh = _resolve(course.id, video.id) ?? video;
    if (_isLocked(course, fresh)) {
      await _askForKey(course);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CoursePlayerScreen(
        api: widget.api,
        video: fresh,
        title: fresh.title,
        courseTitle: course.title,
        onNeedUnlock: () => _askForKey(course),
      ),
    ));
    if (!mounted) return;
    // قد يكون المفتاح فُتح من داخل المشغّل: نحدّث القائمة عند العودة.
    await _load();
  }

  /// هل السبب قفلٌ يحتاج مفتاحاً؟ الشرط من الخادم: دورة تحتاج مفتاحاً لم
  /// يُفتح بعد، ودرسٌ ليس مجانياً. ما دون ذلك عُطل لا يُصلحه مفتاح.
  bool _isLocked(Course course, CourseVideo video) =>
      !video.playable && !video.isFree && course.locked && !course.unlocked;

  /// أحدث نسخة من الفيديو من آخر ردّ للخادم — يحرس من قرار مبني على نسخة قديمة
  /// بعد أن فُتحت الدورة أو تغيّر وضعها في اللوحة.
  CourseVideo? _resolve(String courseId, String videoId) {
    for (final c in _courses) {
      if (c.id != courseId) continue;
      for (final v in c.videos) {
        if (v.id == videoId) return v;
      }
    }
    return null;
  }

  /// هل يملك المستخدم حق التشغيل؟ إذن الخادم وحده، ولا شيء غيره.
  ///
  /// الشرط هو `playable` **و** وجود رابط بثّ: الخادم لا يرسل الرابط إلا لمن
  /// استحقّ، فغياب أيّهما يعني «مقفل» قطعاً. والتحقق من `course.locked` قبل
  /// ذلك كان يجعل الحكم مزدوجاً: قد تقول الدورة «مقفلة» بينما الخادم أباح
  /// الفيديو المجاني داخلها، فيُمنع من أباحه الخادم. مصدر واحد للحقيقة لا
  /// مصدران يتناقضان — وهو أصل ظهور الفيديو المقفل «متاحاً» في الواجهة.
  bool _canPlay(Course course, CourseVideo video) =>
      video.playable && video.streamUrl.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final open = _open;
    return PopScope(
      // زر الرجوع يعود للشبكة أولاً قبل الخروج من التبويب.
      canPop: open == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && open != null) setState(() => _open = null);
      },
      child: Container(
        color: XTheme.bg,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: XTheme.accent))
            : _error != null
                ? _errorView()
                : open == null
                    ? _grid()
                    : _detail(open),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 46, color: XTheme.textDim),
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: XTheme.textDim, fontSize: 13.5)),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );

  Widget _grid() {
    if (_courses.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.school_outlined, size: 50, color: XTheme.textDim),
              const SizedBox(height: 14),
              const Text('لا دورات منشورة بعد',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('ستظهر الدورات هنا حين ينشرها المالك.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.8, color: XTheme.textDim)),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _contactOwner,
                icon: const Icon(Icons.support_agent, size: 18),
                label: const Text('تواصل مع المالك'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: XTheme.accent,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
        children: [
          _header(),
          const SizedBox(height: 14),
          for (final c in _courses) ...[
            _courseCard(c),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _header() => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: XTheme.gradient,
              borderRadius: BorderRadius.circular(XTheme.rSm),
            ),
            child: const Icon(Icons.play_lesson_outlined,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الدورات',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text('دروس مرتّبة كقوائم تشغيل — المجاني مفتوح للجميع',
                    style: TextStyle(fontSize: 11.8, color: XTheme.textDim)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      );

  Widget _courseCard(Course c) {
    return InkWell(
      borderRadius: BorderRadius.circular(XTheme.rLg),
      onTap: () => setState(() => _open = c),
      child: Container(
        decoration: BoxDecoration(
          color: XTheme.surface,
          borderRadius: BorderRadius.circular(XTheme.rLg),
          border: Border.all(
              color: XTheme.textDim.withOpacity(.12), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(XTheme.rLg)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _cover(c),
                ),
              ),
              // شارة القفل: أوضح ما يراه المستخدم قبل الدخول.
              if (c.locked && !c.unlocked) ...[
                // تعتيم الغلاف كاملاً: اللون الباهت وحده لا يُقرأ «مقفل» على
                // شاشة صغيرة. القفل يجب أن يُرى قبل النقر لا بعده.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(XTheme.rLg)),
                      color: Colors.black.withOpacity(.45),
                    ),
                  ),
                ),
                const Positioned(
                  top: 10,
                  right: 10,
                  child: _LockBadge(text: 'مقفلة — تحتاج مفتاحاً'),
                ),
                const Center(
                  child: Icon(Icons.lock, color: Colors.white, size: 40),
                ),
              ],
              if (c.locked && c.unlocked)
                const Positioned(
                  top: 10,
                  right: 10,
                  child: _LockBadge(text: 'مفتوحة', open: true),
                ),
              Positioned(
                bottom: 10,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.72),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.playlist_play,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 5),
                    Text('${c.videoCount} فيديو',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.8, fontWeight: FontWeight.w900)),
                  if (c.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(c.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.2, color: XTheme.textDim, height: 1.4)),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    if (c.freeCount > 0)
                      _pill('${c.freeCount} مجاني', XTheme.ok),
                    if (c.freeCount > 0) const SizedBox(width: 6),
                    if (c.locked && !c.unlocked)
                      _pill('تحتاج مفتاحاً', XTheme.gold),
                    const Spacer(),
                    Icon(Icons.chevron_left,
                        size: 20, color: XTheme.textDim),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cover(Course c) {
    final url = c.coverUrl;
    // كان الغلاف يُطلب بلا ترويسة توقيع، والخادم يرفض كل `/v1/*` بلا توقيع،
    // فيرجع 403 دائماً ويُعرض التدرّج البديل — أي أن غلاف المالك لم يظهر
    // ولا مرة. التوقيع يُخزَّن مؤقتاً داخل `signFor` فلا يُعاد توليده كل إطار.
    if (url.isEmpty) return _coverFallback(c);
    return _SignedImage(
      api: widget.api,
      url: url,
      fit: BoxFit.cover,
      fallback: _coverFallback(c),
    );
  }

  /// غلاف بديل حين لا صورة للمالك — أيقونته تتبع حال الدورة لا التزيين:
  /// دورة مقفلة تعرض قفلاً لا زرّ تشغيل. زرّ التشغيل على دورة لا تُفتح كان
  /// يَعِد بما لا يقع، والقفل هو الحقيقة الوحيدة المعروفة هنا.
  Widget _coverFallback(Course c) => Container(
        decoration: const BoxDecoration(gradient: XTheme.gradient),
        alignment: Alignment.center,
        child: Icon(
            c.locked && !c.unlocked
                ? Icons.lock_outline
                : Icons.play_circle_outline,
            color: Colors.white70,
            size: 40),
      );

  Widget _pill(String t, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(.13),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(t,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
      );

  Widget _detail(Course c) {
    return Column(children: [
      // شريط رجوع — يمنع الحيرة ويُنزل المستخدم للشبكة بضغطة واحدة.
      Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
        color: XTheme.surface,
        child: Row(children: [
          IconButton(
            onPressed: () => setState(() => _open = null),
            icon: const Icon(Icons.arrow_forward, size: 20),
            tooltip: 'رجوع',
          ),
          Expanded(
            child: Text(c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w900)),
          ),
          if (c.locked && !c.unlocked)
            TextButton.icon(
              onPressed: () => _askForKey(c),
              icon: const Icon(Icons.key, size: 16),
              label: const Text('فتح'),
            ),
        ]),
      ),
      Expanded(
        child: c.videos.isEmpty
            ? Center(
                child: Text('لا فيديوهات في هذه الدورة بعد',
                    style: TextStyle(color: XTheme.textDim, fontSize: 13.5)),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  if (c.locked && !c.unlocked) _unlockBanner(c),
                  for (var i = 0; i < c.videos.length; i++)
                    _videoTile(c, c.videos[i], i + 1),
                ],
              ),
      ),
    ]);
  }

  /// نداء الفتح — يظهر أعلى القائمة فقط حين تكون الدورة مقفلة.
  Widget _unlockBanner(Course c) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: XTheme.gold.withOpacity(.10),
          borderRadius: BorderRadius.circular(XTheme.rLg),
          border: Border.all(color: XTheme.gold.withOpacity(.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.lock_outline, color: XTheme.gold, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('الدورة كاملة مقفلة',
                    style:
                        TextStyle(fontSize: 13.8, fontWeight: FontWeight.w900)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'المفتاح يُفعَّل مرة واحدة على هذا الجهاز ويفتح كل الفيديوهات، '
              'وكل ما يُضيفه المالك لاحقاً في هذه الدورة.',
              style: TextStyle(fontSize: 12.2, color: XTheme.textDim, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _askForKey(c),
                  icon: const Icon(Icons.key, size: 17),
                  label: const Text('لدي مفتاح'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _contactOwner,
                  icon: const Icon(Icons.support_agent, size: 17),
                  label: const Text('المالك'),
                ),
              ),
            ]),
          ],
        ),
      );

  Widget _videoTile(Course c, CourseVideo v, int index) {
    // القفل يتبع القدرة الفعلية على التشغيل لا راية الدورة وحدها: هذا ما
    // يجعل فيديو مجانياً داخل دورة مقفلة يظهر بلا قفل — وهو ما يسمح به
    // الخادم فعلاً، فلا تتناقض الواجهة مع الاستحقاق.
    final locked = !_canPlay(c, v);
    return InkWell(
      borderRadius: BorderRadius.circular(XTheme.rMd),
      onTap: () => _openVideo(c, v),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // المصغّرة الحقيقية التي يرفعها المالك، وعليها علامة القفل إن كان
          // الدرس مقفلاً — فيعرف المستخدم حاله من الصورة قبل أي نقر.
          Stack(children: [
            SizedBox(
              width: 118,
              height: 66,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(XTheme.rSm),
                child: _VideoThumb(
                  api: widget.api,
                  video: v,
                  locked: locked,
                ),
              ),
            ),
            // القفل فوق الصورة نفسها، لا بدل الصورة.
            if (locked)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(XTheme.rSm),
                    color: Colors.black.withOpacity(.42),
                  ),
                  child: const Center(
                    child: Icon(Icons.lock, color: Colors.white, size: 26),
                  ),
                ),
              ),
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(.7),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  v.durationLabel.isEmpty ? '$index' : v.durationLabel,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ]),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.6, fontWeight: FontWeight.w800)),
                if (v.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(v.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.6, color: XTheme.textDim, height: 1.4)),
                ],
                const SizedBox(height: 5),
                Row(children: [
                  if (v.isFree)
                    _pill('مجاني', XTheme.ok)
                  else if (locked)
                    _pill('مقفل', XTheme.gold)
                  else
                    _pill('متاح', XTheme.cyan),
                  if (v.sizeLabel.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(v.sizeLabel,
                        style: TextStyle(
                            fontSize: 10.5, color: XTheme.textDim)),
                  ],
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// شارة حالة على الغلاف.
class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.text, this.open = false});
  final String text;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final color = open ? XTheme.ok : XTheme.gold;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(open ? Icons.lock_open : Icons.lock, color: color, size: 13),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                color: color, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// مشغّل فيديو الدورة — ينزّل مرة، يكاش، ثم يشغّل من الملف المحلي.
///
/// الفيديو مشفّر عند النقل ولا يمكن لـ`video_player` فكّه في الطيران، فالتنزيل
/// ثم التشغيل المحلي هو الطريق الوحيد. ونتيجته أفضل أيضاً: تقديم وترجيع سلسان
/// بلا إعادة تحميل، والمشاهدة الثانية بلا شبكة.
class CoursePlayerScreen extends StatefulWidget {
  const CoursePlayerScreen({
    super.key,
    required this.api,
    required this.video,
    required this.title,
    this.courseTitle = '',
    this.onNeedUnlock,
  });

  final Api api;
  final CourseVideo video;
  final String title;
  final String courseTitle;
  final VoidCallback? onNeedUnlock;

  @override
  State<CoursePlayerScreen> createState() => _CoursePlayerScreenState();
}

class _CoursePlayerScreenState extends State<CoursePlayerScreen> {
  VideoPlayerController? _player;

  /// العنوان المحلي الذي يخدمه الوكيل — يُطلق عند الخروج.
  String? _proxyUrl;
  bool _preparing = true;
  String? _error;
  bool _killed = false;

  /// مؤقّت إظهار مؤشر التحميل. راجع `_preparingView` لسبب وجوده.
  Timer? _spinnerTimer;
  bool _showSpinner = false;

  /// كم مرة انتهت التهيئة بلا إطار؟ يمنع تشغيل فيديو لن يعرض شيئاً.
  int _blankFrames = 0;

  @override
  void initState() {
    super.initState();
    // حجب التقاط الشاشة طوال مشاهدة الدرس: الفيديو محتوى مدفوع، والتسجيل
    // منه بالتقاط الشاشة يسرّبه كاملاً بلا استحقاق.
    SecureScreen.on();
    _watchKillSwitch();
    _prepare();
  }

  @override
  void dispose() {
    SecureScreen.off();
    _spinnerTimer?.cancel();
    AppConfig.instance.removeListener(_onCfg);
    final u = _proxyUrl;
    if (u != null) MediaProxy.instance.release(u);
    // الإنهاء قد يفشل إن كان المشغّل نصف مهيّأ — لا نُسقط الشاشة بسببه.
    try {
      _player?.dispose();
    } catch (_) {}
    super.dispose();
  }

  /// يبدأ التشغيل مباشرة من الخادم.
  ///
  /// لا تنزيل كامل ولا ملف وسيط: الخادم يفكّ التشفير ويخدم القطع بمدى Range،
  /// والوكيل المحلي يوقّع كل طلب طازجاً. المشغّل يجلب أول أجزاء الملف فقط كي
  /// يعرض، ثم يواصل ما يحتاجه فعلاً — فالبداية فورية والتنزيل لا يكتمل أبداً.
  Future<void> _prepare() async {
    setState(() {
      _preparing = true;
      _error = null;
      _showSpinner = false;
    });
    // حرس أخير: الخادم لا يرسل رابطاً لغير المستحق. الوصول إلى هنا برابط
    // فارغ كان يحاول تشغيل مسار باطل فيُظهر سواداً ثم «فشل». الرسالة الصريحة
    // والزرّ أدناه يقودان إلى طلب الكود مباشرة.
    if (widget.video.streamUrl.isEmpty) {
      setState(() {
        _preparing = false;
        _error = 'هذا الدرس يحتاج كود فتح من المالك';
      });
      return;
    }
    _armSpinner();
    try {
      final url = await MediaProxy.instance
          .urlFor(widget.api, widget.video.streamUrl);
      _proxyUrl = url;
      if (!mounted) return;

      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        // مهلة صريحة: بلا سقف، تعليق الاتصال يُبقي التهيئة معلّقة للأبد على
        // صورة سوداء بلا رسالة — وهو ما ظهر شاشة سوداء لا تنتهي.
        await c.initialize().timeout(const Duration(seconds: 25));
      } on TimeoutException {
        await c.dispose();
        // مهلة التهيئة ليست فشلاً نهائياً: أول طلب يعبر الوكيل يوقظ الجلسة
        // ويفتح الاتصال، والمحاولة الثانية تمرّ في العادة. نحاول قبل إظهار
        // خطأ يدفع المستخدم لإعادة المحاولة يدوياً بلا داعٍ.
        if (_blankFrames++ == 0 && mounted) {
          await _prepare();
          return;
        }
        rethrow;
      } catch (_) {
        await c.dispose();
        rethrow;
      }
      // تهيئة «ناجحة» بنسبة صفر معناها أن المشغّل لم يقرأ إطاراً بعد، وتشغيلها
      // يعرض مساحة سوداء صامتة. نعيد المحاولة مرة، ثم نُعلن الفشل بدل أن
      // يبقى المستخدم أمام سواد لا ينتهي.
      if (c.value.aspectRatio <= 0) {
        await c.dispose();
        if (_blankFrames++ == 0 && mounted) {
          await _prepare();
          return;
        }
        throw StateError('blank frame');
      }
      await c.setLooping(false);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _spinnerTimer?.cancel();
      setState(() {
        _player = c;
        _preparing = false;
        _showSpinner = false;
      });
      await c.play();
    } catch (e) {
      _spinnerTimer?.cancel();
      if (mounted) {
        setState(() {
          _preparing = false;
          _showSpinner = false;
          _error = 'تعذر تشغيل الفيديو — حاول مرة أخرى';
        });
      }
    }
  }

  /// يبدأ مؤقّت إظهار مؤشر التحميل بعد 600 مللي ثانية.
  ///
  /// السبب: الطفرة الشبكية السريعة لا تحتاج مؤشراً — إظهاره ثم إخفاؤه في
  /// أقل من نصف ثانية وميض مزعج. لكن الانتظار الطويل بلا أي إشارة هو بالضبط
  /// «الشاشة السوداء» التي شكا منها المستخدمون. فالأسود لا يُعرض أصلاً،
  /// ويظهر المؤشر فقط إن طال الانتظار فعلاً.
  void _armSpinner() {
    _spinnerTimer?.cancel();
    _spinnerTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted && _preparing) setState(() => _showSpinner = true);
    });
  }

  /// يسجّل الشاشة كمراقبة لمفتاح المالك: إن أوقف الفيديوهات أثناء المشاهدة
  /// يتوقف العرض فوراً — وإلا صار المفتاح بلا معنى على الأجهزة التي فتحت
  /// الفيديو قبل تفعيله.
  void _watchKillSwitch() {
    AppConfig.instance.addListener(_onCfg);
    _onCfg();
  }

  void _onCfg() {
    if (!mounted) return;
    final cfg = AppConfig.instance;
    if (cfg.videosHidden && _player != null && !_killed) {
      _killed = true;
      _player?.pause();
      setState(() => _error = cfg.videosHiddenMessage.isEmpty
          ? 'الفيديوهات متوقفة مؤقتاً'
          : cfg.videosHiddenMessage);
    }
  }

  /// يعيد المحاولة من الصفر: يُنهي المشغّل ويعيد التهيئة.
  ///
  /// لا شيء يُمسح من القرص لأن شيئاً لم يُكتب عليه أصلاً — التشغيل بثٌّ مباشر.
  Future<void> _hardReload() async {
    // إغلاق المشغّل والوكيل معاً: إعادة تسجيل المسار مطلوبة لأن التوقيع
    // المرتبط بالمسار قد يكون انتهى، ولا معنى لتشغيل ملف لم يعد له عنوان.
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    final u = _proxyUrl;
    if (u != null) MediaProxy.instance.release(u);
    _proxyUrl = null;
    await _prepare();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(.5),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w800)),
            if (widget.courseTitle.isNotEmpty)
              Text(widget.courseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
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
    if (_preparing) {
      // لا صورة سوداء في المنتصف: كان يظهر مسطّح أسود (أو مصغّرة لا تُحمَّل)
      // فيبدو المشغّل «عاطلاً» ثم يشتغل فجأة. الآن لا يظهر إلا مؤشر حقيقي،
      // ولا يظهر أصلاً إن كان الاتصال سريعاً.
      return Center(
        child: AnimatedOpacity(
          opacity: _showSpinner ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: XTheme.accent),
            const SizedBox(height: 14),
            const Text('جاري تجهيز الفيديو…',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: XTheme.danger, size: 44),
            const SizedBox(height: 14),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
            const SizedBox(height: 18),
            Row(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton.icon(
                onPressed: _hardReload,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('إعادة المحاولة'),
              ),
              if (widget.onNeedUnlock != null) ...[
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: widget.onNeedUnlock,
                  icon: const Icon(Icons.key, size: 17),
                  label: const Text('فتح الدورة'),
                ),
              ],
            ]),
          ],
        ),
      );
    }
    final p = _player!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          // `aspectRatio` يبقى صفراً حتى يصل أول إطار، والنسبة 16/9 هنا
          // تُبقي المساحة محجوزة فلا تقفز الصفحة عند بدء العرض.
          aspectRatio: p.value.aspectRatio <= 0 ? 16 / 9 : p.value.aspectRatio,
          child: VideoPlayer(p),
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: p,
          builder: (_, v, __) => Column(children: [
            VideoProgressIndicator(
              p,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: XTheme.accent,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white10,
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                iconSize: 40,
                color: Colors.white,
                icon: Icon(v.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled),
                onPressed: () => v.isPlaying ? p.pause() : p.play(),
              ),
              const SizedBox(width: 18),
              Text(
                '${_fmt(v.position)} / ${_fmt(v.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
            ]),
            // خطأ المشغّل بعد بدء التشغيل (ترميز غير مدعوم، ملف تالف) كان
            // يُترك على سطح أسود صامت. نعرضه مع طريق إعادة المحاولة.
            if (v.hasError) ...[
              const SizedBox(height: 8),
              Text(
                v.errorDescription ?? 'تعذر تشغيل الفيديو',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _hardReload,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ]),
        ),
      ],
    );
  }


  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

/// `firstOrNull` على قائمة بدون `package:collection`.
extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
/// صورة موقّعة تُجلب من الخادم.
///
/// هذا الغلاف يبقي واجهة القسم كما هي (بديل + مقاس) ويفوّض البناء الفعلي
/// إلى `SignedImage` المشترك، الذي يحلّ الترويسة مرة واحدة بعد البناء —
/// فالتوقيع صار Ed25519 غير متزامن، ولا يمكن حسابه داخل `build`.
class _SignedImage extends StatelessWidget {
  const _SignedImage({
    required this.api,
    required this.url,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final Api api;
  final String url;
  final Widget fallback;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => SignedImage(
        api: api,
        path: url,
        fit: fit,
        errorBuilder: () => fallback,
      );
}

/// مصغّرة الدرس: صورة المالك إن وُجدت، وإلا بديل مشتقّ من حالة الدرس.
///
/// البديل ليس صورة عشوائية: إطار داكن مع أيقونة تشغيل أو قفل، فيبقى الصف
/// مفهوماً حتى قبل أن يرفع المالك أي صورة.
class _VideoThumb extends StatelessWidget {
  const _VideoThumb({
    required this.api,
    required this.video,
    required this.locked,
  });

  final Api api;
  final CourseVideo video;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E2430), Color(0xFF2B3444)],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        locked ? Icons.lock_outline : Icons.play_circle_outline,
        color: locked ? Colors.white38 : XTheme.accent,
        size: 28,
      ),
    );
    final url = video.thumbUrl;
    if (url.isEmpty) return placeholder;
    return _SignedImage(api: api, url: url, fallback: placeholder);
  }
}

