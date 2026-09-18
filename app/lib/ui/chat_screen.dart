import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'external_link.dart';
import 'media_viewer.dart';
import 'theme.dart';

/// شاشة الدردشة المجتمعية — أقسام، فقاعات، وسائط، ومشاهدون.
///
/// كل المحادثات علنية داخل الأقسام: لا رسائل خاصة. هذا اختيار أمني مقصود،
/// فما يمكن حمايته فعلاً بخادم واحد هو ما لا يحتاج إدارة مفاتيح طرفية.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.api, required this.store});
  final Api api;
  final Store store;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with AutomaticKeepAliveClientMixin {
  ChatState _state = const ChatState();
  List<ChatRoom> get _rooms => _state.rooms;

  ChatRoom? _room;
  final List<ChatMessage> _messages = [];

  bool _loading = true;
  bool _loadingOlder = false;
  bool _hasMore = false;
  String? _error;

  /// أحدث ختم زمني وصلنا — أساس طلب «الجديد فقط» في التحديث الدوري.
  int _lastAt = 0;

  /// ختم آخر مشاهدة أُبلغ به الخادم — نمنع تكرار الطلب نفسه.
  int _reportedSeen = 0;

  Timer? _poll;
  bool _polling = false;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _atBottom = true;

  /// مؤقّت إخفاء شريط «رسائل جديدة».
  bool _unseenBelow = false;

  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  bool _recording = false;
  int _recordStart = 0;
  Timer? _recordTick;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _recordTick?.cancel();
    _recorder.dispose();
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // RTL: النهاية هي أحدث رسالة، فـpixels قريبة من maxScrollExtent هناك.
    final atBottom = pos.pixels >= pos.maxScrollExtent - 60;
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
        if (atBottom) _unseenBelow = false;
      });
      if (atBottom) _reportSeen();
    }
    // التمرير للأعلى يطلب دفعة أقدم — لا تُحمَّل المحادثة كاملة أبداً.
    if (pos.pixels <= 120 && _hasMore && !_loadingOlder) _loadOlder();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await widget.api.chatState();
      if (!mounted) return;
      final room = _room ??
          (state.rooms.isEmpty ? null : state.rooms.first);
      setState(() {
        _state = state;
        _room = room;
        _loading = false;
      });
      if (room == null) return;
      await _loadLatest(room.id);
      _startPolling();
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
          _error = 'تعذر تحميل الدردشة — تحقق من الإنترنت';
        });
      }
    }
  }

  /// أحدث صفحة عند فتح قسم أو تبديله.
  Future<void> _loadLatest(String room) async {
    try {
      final page = await widget.api.chatMessages(room, limit: 40);
      if (!mounted || _room?.id != room) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _hasMore = page.hasMore;
        _lastAt = _messages.isEmpty ? 0 : _messages.last.at;
        _reportedSeen = 0;
      });
      _jumpToBottom();
      _reportSeen();
    } catch (_) {
      // فشل أول تحميل لا يمسح رسائل موجودة؛ التحديث الدوري سيعيد المحاولة.
    }
  }

  /// دفعة أقدم عند التمرير للأعلى.
  Future<void> _loadOlder() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    final oldest = _messages.first.at;
    try {
      final page = await widget.api
          .chatMessages(_room!.id, before: oldest, limit: 40);
      if (!mounted) return;
      // نحفظ موضع التمرير: إدراج عناصر في الأعلى يزيح ما يقرأه المستخدم.
      final before = _scroll.hasClients ? _scroll.position.maxScrollExtent : 0.0;
      setState(() {
        _messages.insertAll(0, page.messages);
        _hasMore = page.hasMore;
        _loadingOlder = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final after = _scroll.position.maxScrollExtent;
        _scroll.jumpTo(_scroll.position.pixels + (after - before));
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// التحديث الدوري: يحمل الجديد وحده بعد آخر ختم، وليس المحادثة كلها.
  void _startPolling() {
    _poll?.cancel();
    final ms = _state.pollMs.clamp(2000, 30000);
    _poll = Timer.periodic(Duration(milliseconds: ms), (_) => _pollNew());
  }

  Future<void> _pollNew() async {
    final room = _room;
    if (room == null || _polling || !mounted) return;
    if (!_state.enabled) return;
    // لا نستطلع والشاشة غير مرئية: يوفّر بطارية وشبكة بلا فائدة.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _polling = true;
    try {
      final page = await widget.api
          .chatMessages(room.id, since: _lastAt, limit: 60);
      if (!mounted || _room?.id != room.id) return;
      if (page.messages.isNotEmpty) {
        setState(() {
          for (final m in page.messages) {
            // منع التكرار: رسالتي التي أرسلتها للتوّ قد تعود من الاستطلاع.
            final i = _messages.indexWhere((x) => x.id == m.id);
            if (i >= 0) {
              _messages[i] = m;
            } else {
              _messages.add(m);
            }
          }
          _lastAt = _messages.last.at;
          if (!_atBottom) _unseenBelow = true;
        });
        if (_atBottom) _reportSeen();
        // عند وجود جديد والتمرير في الأسفل نتابع النزول تلقائياً.
        if (_atBottom) _jumpToBottom();
      }
      // تحديث صور المشاهدين للرسائل القديمة قد يحتاج إعادة جلب أخيرة،
      // لكن ذلك يكفي عند الطلب اليدوي (سحب للتحديث) لا كل دورة.
    } catch (_) {
      // فشل دورة واحدة لا يُظهر خطأ: الشبكة تتقطع لحظياً كثيراً.
    } finally {
      _polling = false;
    }
  }

  /// يُخبر الخادم أن المستخدم بلغ آخر رسالة — أساس «من رأى الرسالة».
  void _reportSeen() {
    final room = _room;
    if (room == null || _messages.isEmpty) return;
    if (!widget.store.hasSession || widget.store.isGuest) return;
    final at = _messages.last.at;
    if (at <= _reportedSeen) return;
    _reportedSeen = at;
    widget.api.chatSeen(room.id, at).catchError((_) {});
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _switchRoom(ChatRoom room) async {
    if (_room?.id == room.id) return;
    setState(() {
      _room = room;
      _messages.clear();
      _lastAt = 0;
      _reportedSeen = 0;
      _hasMore = false;
      _unseenBelow = false;
    });
    await _loadLatest(room.id);
  }

  // ───────────────────────── الإرسال ─────────────────────────

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: XTheme.surface2,
      ));
  }

  Future<void> _sendText() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final room = _room;
    if (room == null) return;
    if (!_state.canWrite) {
      _toast(_state.writeBlockedReason.isEmpty
          ? 'لا يمكنك الكتابة حالياً'
          : _state.writeBlockedReason);
      return;
    }
    _input.clear();
    await _send(room.id, text: text);
  }

  /// إرسال موحّد: يعرض الرسالة فوراً كـ«قيد الإرسال» ثم يستبدلها بردّ الخادم.
  ///
  /// العرض الفوري مقصود: انتظار الشبكة قبل ظهور الرسالة يجعل الدردشة تبدو
  /// معطّلة على اتصال ضعيف، وهو أسوأ من رسالة تظهر باهتة لحظة.
  Future<void> _send(String roomId, {String text = '', String? mediaB64, int seconds = 0}) async {
    final tempId = 'local_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: tempId,
      roomId: roomId,
      kind: mediaB64 == null ? 'text' : _pendingKind,
      body: text,
      mediaUrl: '',
      mediaMime: '',
      mediaSize: 0,
      at: DateTime.now().millisecondsSinceEpoch,
      mine: true,
      author: ChatAuthor(
        id: '',
        nickname: _state.myNickname,
        avatarUrl: _state.myAvatarUrl,
      ),
      pending: true,
    );
    setState(() {
      _messages.add(optimistic);
      _lastAt = optimistic.at;
    });
    _jumpToBottom();

    try {
      final saved = await widget.api.chatSend(roomId,
          text: text, mediaB64: mediaB64, mediaSeconds: seconds);
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i >= 0) _messages[i] = saved;
        if (saved.at > _lastAt) _lastAt = saved.at;
      });
      _reportSeen();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i >= 0) _messages[i] = _messages[i].copyWith(pending: false, failed: true);
      });
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i >= 0) _messages[i] = _messages[i].copyWith(pending: false, failed: true);
      });
      _toast('تعذر الإرسال — تحقق من الإنترنت');
    }
  }

  /// نوع الوسيط قيد الإرسال — يضبطه المنتقي قبل نداء `_send`.
  String _pendingKind = 'image';

  Future<void> _pickImage() async {
    if (!_state.imagesEnabled) {
      _toast('رفع الصور موقوف حالياً');
      return;
    }
    if (!_state.canWrite) {
      _toast(_state.writeBlockedReason.isEmpty
          ? 'لا يمكنك الكتابة حالياً'
          : _state.writeBlockedReason);
      return;
    }
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      // ضغط الصورة قبل الرفع: صورة جوال خام تتجاوز حدّ 3MB بسهولة.
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 3 * 1024 * 1024) {
      _toast('الصورة كبيرة — اختر صورة أصغر');
      return;
    }
    _pendingKind = 'image';
    await _send(_room!.id, text: _input.text.trim(), mediaB64: base64Encode(bytes));
    _input.clear();
  }

  Future<void> _pickVideo() async {
    if (!_state.canSendMedia) {
      _toast(_state.mediaBlockedReason.isEmpty
          ? 'إرسال الفيديو للمشتركين فقط'
          : _state.mediaBlockedReason);
      return;
    }
    final x = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: Duration(seconds: _state.mediaSeconds),
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > _state.maxMediaMb * 1024 * 1024) {
      _toast('المقطع كبير (أقصى ${_state.maxMediaMb}MB)');
      return;
    }
    _pendingKind = 'video';
    await _send(_room!.id, mediaB64: base64Encode(bytes));
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    if (!_state.canSendMedia) {
      _toast(_state.mediaBlockedReason.isEmpty
          ? 'إرسال الصوت للمشتركين فقط'
          : _state.mediaBlockedReason);
      return;
    }
    if (!await _recorder.hasPermission()) {
      _toast('لم يُمنح إذن الميكروفون');
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/x_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      setState(() {
        _recording = true;
        _recordStart = DateTime.now().millisecondsSinceEpoch;
      });
      // إيقاف تلقائي عند بلوغ الحدّ الأقصى للمدة.
      _recordTick?.cancel();
      _recordTick = Timer(const Duration(seconds: 1), () {
        if (!_recording) return;
        final secs =
            (DateTime.now().millisecondsSinceEpoch - _recordStart) ~/ 1000;
        if (secs >= _state.mediaSeconds) _stopRecording();
        if (mounted) setState(() {});
      });
    } catch (_) {
      _toast('تعذر بدء التسجيل');
    }
  }

  Future<void> _stopRecording() async {
    _recordTick?.cancel();
    try {
      final path = await _recorder.stop();
      final secs =
          ((DateTime.now().millisecondsSinceEpoch - _recordStart) ~/ 1000)
              .clamp(1, _state.mediaSeconds);
      if (!mounted) return;
      setState(() => _recording = false);
      if (path == null) return;
      final f = File(path);
      if (!await f.exists()) return;
      final bytes = await f.readAsBytes();
      await f.delete().catchError((_) => f);
      if (bytes.length > _state.maxMediaMb * 1024 * 1024) {
        _toast('التسجيل كبير (أقصى ${_state.maxMediaMb}MB)');
        return;
      }
      _pendingKind = 'audio';
      await _send(_room!.id,
          mediaB64: base64Encode(bytes), seconds: secs);
    } catch (_) {
      if (mounted) setState(() => _recording = false);
      _toast('تعذر إيقاف التسجيل');
    }
  }

  // ───────────────────────── الواجهة ─────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: XTheme.accent));
    }
    if (_error != null) {
      return _errorView(_error!);
    }
    if (!_state.enabled) {
      return _noticeView(
        icon: Icons.forum_outlined,
        title: 'الدردشة موقوفة مؤقتاً',
        body: 'أوقف المالك الدردشة. عاود المحاولة لاحقاً.',
      );
    }
    return Column(
      children: [
        _roomBar(),
        if (_state.welcome.trim().isNotEmpty) _welcomeStrip(),
        Expanded(child: _messageArea()),
        if (_unseenBelow) _newMessagesBar(),
        _composer(),
      ],
    );
  }

  Widget _errorView(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 54, color: XTheme.danger),
              const SizedBox(height: 14),
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(
                  backgroundColor: XTheme.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(XTheme.rMd)),
                ),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );

  Widget _noticeView(
          {required IconData icon,
          required String title,
          required String body}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 54, color: XTheme.textDim),
              const SizedBox(height: 14),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: XTheme.textDim)),
            ],
          ),
        ),
      );

  /// شريط الأقسام + أزرار الملف الشخصي والإشعارات.
  Widget _roomBar() {
    final me = _state.myNickname.isEmpty ? 'ملفي' : _state.myNickname;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: XTheme.surface,
        border: Border(
          bottom: BorderSide(color: XTheme.textDim.withOpacity(.10)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: _rooms.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final r = _rooms[i];
                  final active = _room?.id == r.id;
                  return GestureDetector(
                    onTap: () => _switchRoom(r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: active ? XTheme.gradient : null,
                        color: active ? null : XTheme.surface2,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow:
                            active ? XTheme.glow(XTheme.accent, strength: .6) : null,
                      ),
                      child: Row(
                        children: [
                          Icon(_roomIcon(r.icon),
                              size: 15,
                              color: active ? Colors.white : XTheme.textDim),
                          const SizedBox(width: 6),
                          Text(r.name,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: active ? Colors.white : XTheme.text,
                              )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          _iconBtn(
            _state.notify ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            _state.notify ? 'إشعارات مفعّلة' : 'إشعارات مكتومة',
            _toggleNotify,
            tint: _state.notify ? XTheme.accent : XTheme.textDim,
          ),
          _iconBtn(Icons.person_outline, me, _openProfile,
              tint: XTheme.cyan),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap,
      {Color? tint}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: XTheme.surface2,
            shape: BoxShape.circle,
            border: Border.all(
                color: (tint ?? XTheme.accent).withOpacity(.28)),
          ),
          child: Icon(icon, size: 17, color: tint ?? XTheme.accent),
        ),
      ),
    );
  }

  Widget _welcomeStrip() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: XTheme.cyan.withOpacity(.08),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 15, color: XTheme.cyan),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_state.welcome,
                  style: const TextStyle(fontSize: 11.5, color: XTheme.cyan)),
            ),
          ],
        ),
      );

  Widget _messageArea() {
    if (_messages.isEmpty) {
      return _noticeView(
        icon: Icons.chat_bubble_outline,
        title: 'لا رسائل في ${_room?.name ?? 'القسم'} بعد',
        body: _state.canWrite
            ? 'كن أول من يبدأ الحديث'
            : _state.writeBlockedReason,
      );
    }
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () => _loadLatest(_room!.id),
          color: XTheme.accent,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            itemCount: _messages.length + (_loadingOlder ? 1 : 0),
            itemBuilder: (_, i) {
              if (_loadingOlder && i == 0) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: XTheme.accent),
                    ),
                  ),
                );
              }
              final m = _messages[i - (_loadingOlder ? 1 : 0)];
              final prev = i - (_loadingOlder ? 1 : 0) - 1 >= 0
                  ? _messages[i - (_loadingOlder ? 1 : 0) - 1]
                  : null;
              // تجميع رسائل الكاتب نفسه المتقاربة زمنياً: يقلّل تكرار الاسم
              // والصورة ويجعل القراءة أسرع، كما في ماسنجر.
              final grouped = prev != null &&
                  prev.author.id == m.author.id &&
                  !m.mine &&
                  m.at - prev.at < 5 * 60 * 1000;
              return _bubble(m, grouped: grouped);
            },
          ),
        ),
        if (_hasMore && !_loadingOlder)
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _loadOlder,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: XTheme.surface2,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: XTheme.textDim.withOpacity(.20)),
                  ),
                  child: Text('تحميل رسائل أقدم',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: XTheme.textDim)),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _newMessagesBar() => GestureDetector(
        onTap: () {
          setState(() => _unseenBelow = false);
          _jumpToBottom();
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 7),
          color: XTheme.accent.withOpacity(.14),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_downward, size: 14, color: XTheme.accent),
              SizedBox(width: 6),
              Text('رسائل جديدة',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: XTheme.accent)),
            ],
          ),
        ),
      );

  /// فقاعة الرسالة — الشكل يتبع السمة التي يختارها المالك.
  Widget _bubble(ChatMessage m, {required bool grouped}) {
    if (m.kind == 'system') return _systemBubble(m);
    final mine = m.mine;
    final radius = _bubbleRadius(_state.theme);
    final bubbleColor = mine
        ? null
        : (XTheme.isLight ? Colors.white : XTheme.surface2);

    final content = Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (m.body.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(
                12, m.isText ? 9 : 8, 12, m.isText ? 9 : 8),
            child: Text(
              m.body,
              style: TextStyle(
                fontSize: 14.2,
                height: 1.45,
                color: mine ? Colors.white : XTheme.text,
              ),
            ),
          ),
        if (m.isImage) _imageContent(m, mine),
        if (m.isAudio) _audioContent(m, mine),
        if (m.isVideo) _videoContent(m, mine),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_clock(m.time),
                  style: TextStyle(
                      fontSize: 10,
                      color: mine
                          ? Colors.white.withOpacity(.75)
                          : XTheme.textDim)),
              if (mine) ...[
                const SizedBox(width: 4),
                Icon(
                  m.failed
                      ? Icons.error_outline
                      : (m.pending ? Icons.schedule : Icons.done_all),
                  size: 12,
                  color: m.failed
                      ? XTheme.danger
                      : Colors.white.withOpacity(.85),
                ),
              ],
            ],
          ),
        ),
        // صور المشاهدين تحت الرسالة — كما في ماسنجر.
        if (mine && m.seenBy.isNotEmpty) _seenRow(m),
      ],
    );

    final bubble = Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .78),
      decoration: BoxDecoration(
        gradient: mine ? XTheme.gradient : null,
        color: bubbleColor,
        borderRadius: radius,
        boxShadow: mine
            ? XTheme.glow(XTheme.accent, strength: .35)
            : XTheme.shadow(lift: .5),
        border: mine
            ? null
            : Border.all(color: XTheme.textDim.withOpacity(.10)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: content,
      ),
    );

    final avatar = _avatar(m.author, size: grouped ? 26 : 34,
        showInitials: !grouped);

    return Padding(
      padding: EdgeInsets.only(top: grouped ? 2 : 10),
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (mine) ...[
            Flexible(child: bubble),
            const SizedBox(width: 8),
            Opacity(
              opacity: m.pending ? .5 : 1,
              child: _avatar(
                ChatAuthor(
                    nickname: _state.myNickname,
                    avatarUrl: _state.myAvatarUrl),
                size: 34,
              ),
            ),
          ] else ...[
            Opacity(
              opacity: m.pending ? .5 : 1,
              child: SizedBox(
                width: 34,
                child: grouped
                    ? const SizedBox.shrink()
                    : avatar,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!grouped)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3, right: 4),
                      child: Text(m.author.label,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w900,
                              color: XTheme.textDim)),
                    ),
                  bubble,
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  BorderRadius _bubbleRadius(String theme) {
    const r = Radius.circular(18);
    const small = Radius.circular(6);
    switch (theme) {
      case 'classic':
        return const BorderRadius.all(Radius.circular(8));
      case 'neon':
        return const BorderRadius.all(Radius.circular(22));
      case 'dark':
      case 'bubble':
      default:
        return const BorderRadius.only(
          topRight: r, topLeft: r, bottomRight: r, bottomLeft: small);
    }
  }

  Widget _imageContent(ChatMessage m, bool mine) {
    final url = m.mediaUrl;
    if (url.isEmpty) {
      return _mediaPlaceholder(
          Icons.image_outlined, mine ? 'جاري رفع الصورة…' : 'صورة');
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaViewer(
          api: widget.api,
          url: url,
          title: m.author.label,
        ),
      )),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(XTheme.rSm),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: Image.network(
              url.startsWith('/') ? '$kApiBase$url' : url,
              headers: url.startsWith('/')
                  ? widget.api.signFor('GET', url)
                  : null,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, p) => p == null
                  ? child
                  : Container(
                      height: 180,
                      width: 220,
                      alignment: Alignment.center,
                      color: XTheme.surface2,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: XTheme.accent),
                    ),
              errorBuilder: (context, error, stack) => Container(
                height: 140, width: 200,
                alignment: Alignment.center,
                color: XTheme.surface2,
                child: Icon(Icons.broken_image_outlined,
                    color: XTheme.textDim),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _audioContent(ChatMessage m, bool mine) => _VoicePlayer(
        api: widget.api,
        url: m.mediaUrl,
        mine: mine,
      );

  Widget _videoContent(ChatMessage m, bool mine) {
    if (m.mediaUrl.isEmpty) {
      return _mediaPlaceholder(
          Icons.videocam_outlined, mine ? 'جاري رفع المقطع…' : 'مقطع');
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MediaViewer(
          api: widget.api,
          url: m.mediaUrl,
          title: m.author.label,
          isVideo: true,
        ),
      )),
      child: Container(
        width: 230, height: 150,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(XTheme.rSm),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill, size: 46, color: Colors.white),
        ),
      ),
    );
  }

  Widget _mediaPlaceholder(IconData icon, String label) => Container(
        width: 200, height: 120,
        margin: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: XTheme.surface2,
          borderRadius: BorderRadius.circular(XTheme.rSm),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: XTheme.textDim),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(fontSize: 11, color: XTheme.textDim)),
          ],
        ),
      );

  Widget _seenRow(ChatMessage m) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 16,
              width: (m.seenBy.length * 12 + 6).clamp(18, 90).toDouble(),
              child: Stack(
                children: [
                  for (var i = 0; i < m.seenBy.length && i < 8; i++)
                    Positioned(
                      left: i * 12.0,
                      child: _avatar(m.seenBy[i], size: 16),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Text('${m.seenBy.length}',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withOpacity(.85))),
          ],
        ),
      );

  Widget _systemBubble(ChatMessage m) => Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: XTheme.surface2,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(m.body,
              style: TextStyle(fontSize: 11.5, color: XTheme.textDim)),
        ),
      );

  Widget _avatar(ChatAuthor a,
      {double size = 34, bool showInitials = true}) {
    final url = a.avatarUrl;
    final initial = a.label.characters.first;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: url.isEmpty ? XTheme.gradient : null,
        color: url.isEmpty ? null : XTheme.surface2,
        border: Border.all(color: XTheme.bg, width: size > 20 ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.isEmpty
          ? Center(
              child: showInitials
                  ? Text(initial,
                      style: TextStyle(
                          fontSize: size * .42,
                          fontWeight: FontWeight.w900,
                          color: Colors.white))
                  : Icon(Icons.person, size: size * .6, color: Colors.white),
            )
          : Image.network(
              url.startsWith('/') ? '$kApiBase$url' : url,
              headers: url.startsWith('/')
                  ? widget.api.signFor('GET', url)
                  : null,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.person,
                    size: size * .6, color: XTheme.textDim),
              ),
            ),
    );
  }

  // ───────────────────────── شريط الكتابة ─────────────────────────

  Widget _composer() {
    if (_recording) {
      final secs =
          ((DateTime.now().millisecondsSinceEpoch - _recordStart) ~/ 1000)
              .clamp(0, _state.mediaSeconds);
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: XTheme.surface,
          border: Border(top: BorderSide(color: XTheme.danger.withOpacity(.24))),
        ),
        child: Row(
          children: [
            const _PulsingDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Text('جاري التسجيل… ${_fmtSecs(secs)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: XTheme.danger)),
            ),
            IconButton(
              onPressed: () => _stopRecording(),
              icon: const Icon(Icons.send_rounded, color: XTheme.accent),
            ),
            IconButton(
              onPressed: () async {
                _recordTick?.cancel();
                await _recorder.stop();
                setState(() => _recording = false);
              },
              icon: Icon(Icons.delete_outline, color: XTheme.textDim),
            ),
          ],
        ),
      );
    }

    if (!_state.canWrite) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: XTheme.surface,
          border: Border(top: BorderSide(color: XTheme.textDim.withOpacity(.12))),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: XTheme.textDim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _state.writeBlockedReason.isEmpty
                    ? 'لا يمكنك الكتابة في الدردشة حالياً'
                    : _state.writeBlockedReason,
                style: TextStyle(fontSize: 12.5, color: XTheme.textDim),
              ),
            ),
            TextButton(
              onPressed: () => openExternal(context, 'https://t.me/',
                  label: 'تواصل'),
              child: const Text('تواصل',
                  style: TextStyle(color: XTheme.accent)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      decoration: BoxDecoration(
        color: XTheme.surface,
        border: Border(top: BorderSide(color: XTheme.textDim.withOpacity(.12))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _composerIcon(Icons.add_photo_alternate_outlined, 'صورة', _pickImage),
          if (_state.mediaScope != 'none')
            _composerIcon(Icons.videocam_outlined, 'فيديو', _pickVideo),
          _composerIcon(
            _recording ? Icons.stop_circle_outlined : Icons.mic_none,
            'رسالة صوتية',
            _toggleRecording,
            tint: _recording ? XTheme.danger : null,
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: XTheme.surface2,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                    color: _focus.hasFocus
                        ? XTheme.accent.withOpacity(.45)
                        : XTheme.textDim.withOpacity(.14)),
              ),
              child: TextField(
                controller: _input,
                focusNode: _focus,
                maxLines: 4,
                minLines: 1,
                maxLength: _state.maxLength,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(fontSize: 14.5),
                decoration: const InputDecoration(
                  hintText: 'اكتب رسالة…',
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          GestureDetector(
            onTap: _input.text.trim().isEmpty ? null : _sendText,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: _input.text.trim().isEmpty
                    ? null
                    : XTheme.gradient,
                color: _input.text.trim().isEmpty
                    ? XTheme.surface2
                    : null,
                shape: BoxShape.circle,
                boxShadow: _input.text.trim().isEmpty
                    ? null
                    : XTheme.glow(XTheme.accent, strength: .6),
              ),
              child: Icon(Icons.send_rounded,
                  size: 20,
                  color: _input.text.trim().isEmpty
                      ? XTheme.textDim
                      : Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composerIcon(IconData icon, String tip, VoidCallback onTap,
      {Color? tint}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 21, color: tint ?? XTheme.textDim),
        ),
      ),
    );
  }

  // ───────────────────────── الملف الشخصي ─────────────────────────

  Future<void> _toggleNotify() async {
    if (!widget.store.hasSession || widget.store.isGuest) {
      _toast('أنشئ حساباً لتخصيص الإشعارات');
      return;
    }
    try {
      final res = await widget.api.chatProfile(notify: !_state.notify);
      if (!mounted) return;
      // نعيد قراءة الحالة من الخادم بدل تعديلها محلياً: مصدر واحد للحقيقة،
      // فلا تختلف الواجهة عن الواقع إن تغيّر شيء في الإعدادات بالتوازي.
      await _reloadStateOnly();
      _toast(res['notify'] == true ? 'الإشعارات مفعّلة' : 'الإشعارات مكتومة');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('تعذر تغيير حالة الإشعارات');
    }
  }

  Future<void> _openProfile() async {
    if (!widget.store.hasSession || widget.store.isGuest) {
      _toast('أنشئ حساباً لتظهر باسمك وصورتك في الدردشة');
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatProfileSheet(
        api: widget.api,
        nickname: _state.myNickname,
        avatarUrl: _state.myAvatarUrl,
      ),
    );
    if (changed == true) await _reloadStateOnly();
  }

  /// يعيد حالة الدردشة وحدها بلا إعادة تحميل الرسائل.
  Future<void> _reloadStateOnly() async {
    try {
      final s = await widget.api.chatState();
      if (!mounted) return;
      setState(() => _state = s);
    } catch (_) {}
  }

  static IconData _roomIcon(String name) {
    switch (name) {
      case 'build':
        return Icons.build_outlined;
      case 'memory':
        return Icons.memory_outlined;
      case 'store':
        return Icons.storefront_outlined;
      case 'help':
        return Icons.help_outline;
      case 'sell':
        return Icons.sell_outlined;
      default:
        return Icons.forum_outlined;
    }
  }

  static String _clock(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static String _fmtSecs(int s) =>
      '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}

/// نقطة نابضة لشريط التسجيل.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: .35, end: 1.0).animate(_c),
        child: Container(
          width: 12, height: 12,
          decoration: const BoxDecoration(
              color: XTheme.danger, shape: BoxShape.circle),
        ),
      );
}

/// مشغّل الرسالة الصوتية — تحميل بكسل عند أول تشغيل ثم تشغيل/إيقاف.
class _VoicePlayer extends StatefulWidget {
  const _VoicePlayer({required this.api, required this.url, required this.mine});
  final Api api;
  final String url;
  final bool mine;

  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> {
  final _player = AudioPlayer();
  bool _playing = false;
  Duration _pos = Duration.zero;
  Duration _total = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
      // انتهاء المقطع يعيد الشريط إلى البداية بلا إغلاق الفقاعة.
      if (s == PlayerState.completed) {
        _player.seek(Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (widget.url.isEmpty) return;
    try {
      if (_playing) {
        await _player.pause();
        return;
      }
      if (_player.state == PlayerState.paused) {
        await _player.resume();
        return;
      }
      // الملفات محمية بتوقيع الطلب، فنحمّلها إلى ملف مؤقت ثم نشغّلها:
      // مشغّل النظام لا يعرف ترويسات التوقيع.
      final bytes = await widget.api
          .getBytes(widget.url)
          .then((r) => r.bytes)
          .timeout(const Duration(minutes: 2));
      final dir = await getTemporaryDirectory();
      final f = File(
          '${dir.path}/x_audio_${widget.url.hashCode.abs()}.m4a');
      await f.writeAsBytes(bytes);
      await _player.play(DeviceFileSource(f.path));
    } catch (_) {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fg = widget.mine ? Colors.white : XTheme.text;
    final total = _total.inMilliseconds <= 0
        ? 1
        : _total.inMilliseconds;
    final progress = (_pos.inMilliseconds / total).clamp(0.0, 1.0);
    return Container(
      width: 210,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      margin: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: widget.mine
                    ? Colors.white.withOpacity(.22)
                    : XTheme.accent.withOpacity(.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause : Icons.play_arrow_rounded,
                size: 20,
                color: widget.mine ? Colors.white : XTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor: fg.withOpacity(.22),
                    valueColor: AlwaysStoppedAnimation(
                        widget.mine ? Colors.white : XTheme.accent),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _fmt(_playing || _pos > Duration.zero ? _pos : _total),
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: fg.withOpacity(.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// لوحة الملف الشخصي للدردشة: كنية وصورة تظهران لكل الأعضاء.
class ChatProfileSheet extends StatefulWidget {
  const ChatProfileSheet({
    super.key,
    required this.api,
    required this.nickname,
    required this.avatarUrl,
  });

  final Api api;
  final String nickname;
  final String avatarUrl;

  @override
  State<ChatProfileSheet> createState() => _ChatProfileSheetState();
}

class _ChatProfileSheetState extends State<ChatProfileSheet> {
  late final TextEditingController _nick =
      TextEditingController(text: widget.nickname);
  String _avatarUrl = '';
  Uint8List? _picked;
  bool _busy = false;
  bool _clearAvatar = false;

  @override
  void initState() {
    super.initState();
    _avatarUrl = widget.avatarUrl;
  }

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 1500 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الصورة كبيرة — اختر صورة أصغر'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() {
      _picked = bytes;
      _clearAvatar = false;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.api.chatProfile(
        nickname: _nick.text.trim(),
        imageB64: _picked == null ? null : base64Encode(_picked!),
        clearAvatar: _clearAvatar,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: XTheme.surface2,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تعذر الحفظ — تحقق من الإنترنت'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _picked != null
        ? Image.memory(_picked!, fit: BoxFit.cover)
        : (_clearAvatar || _avatarUrl.isEmpty
            ? Center(
                child: Icon(Icons.person,
                    size: 34, color: XTheme.textDim),
              )
            : Image.network(
                _avatarUrl.startsWith('/')
                    ? '$kApiBase$_avatarUrl'
                    : _avatarUrl,
                headers: _avatarUrl.startsWith('/')
                    ? widget.api.signFor('GET', _avatarUrl)
                    : null,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => Center(
                  child: Icon(Icons.person,
                      size: 34, color: XTheme.textDim),
                ),
              ));

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: XTheme.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(XTheme.rXl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42, height: 4,
              decoration: BoxDecoration(
                color: XTheme.textDim.withOpacity(.30),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            const SectionTitle('ملفي في الدردشة', icon: Icons.badge_outlined),
            const SizedBox(height: 6),
            Row(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      Container(
                        width: 76, height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: XTheme.surface2,
                          border: Border.all(
                              color: XTheme.accent.withOpacity(.35),
                              width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: preview,
                      ),
                      Positioned(
                        bottom: 0, left: 0,
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            gradient: XTheme.gradient,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              size: 13, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الكنية',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: XTheme.textDim)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nick,
                        maxLength: 24,
                        decoration: InputDecoration(
                          hintText: 'اسم يظهر للأعضاء',
                          counterText: '',
                          isDense: true,
                          filled: true,
                          fillColor: XTheme.surface2,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(XTheme.rMd),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_avatarUrl.isNotEmpty || _picked != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _picked = null;
                      _clearAvatar = true;
                    }),
                    icon: Icon(Icons.delete_outline,
                        size: 16, color: XTheme.danger),
                    label: const Text('إزالة الصورة',
                        style: TextStyle(color: XTheme.danger)),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: XTheme.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(XTheme.rMd)),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('حفظ',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'كنيتك وصورتك تظهران لكل الأعضاء في الدردشة.',
              style: TextStyle(fontSize: 11, color: XTheme.textDim),
            ),
          ],
        ),
      ),
    );
  }
}
