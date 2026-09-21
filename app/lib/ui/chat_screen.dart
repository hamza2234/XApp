import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart' as fc;
import 'package:flutter_chat_ui/flutter_chat_ui.dart' as fchat;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/api.dart';
import '../core/app_config.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import 'chat_bridge.dart';
import 'chat_theme_x.dart';
import 'external_link.dart';
import 'media_viewer.dart';
import 'theme.dart';

/// شاشة الدردشة المجتمعية — أقسام، فقاعات، وسائط، ومشاهدون.
///
/// كل المحادثات علنية داخل الأقسام: لا رسائل خاصة. هذا اختيار أمني مقصود،
/// فما يمكن حمايته فعلاً بخادم واحد هو ما لا يحتاج إدارة مفاتيح طرفية.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.api,
    required this.store,
    required this.onExit,
    this.openRoomId = '',
    this.onRoomOpened,
    this.onRoomChanged,
  });
  final Api api;
  final Store store;

  /// قسم مطلوب فتحه من الخارج (ضغط إشعار دردشة).
  ///
  /// يصل عبر الغلاف لا مباشرةً، لأن الشاشة تُبنى مرة واحدة وتبقى حيّة في
  /// `IndexedStack`؛ تغيير هذه القيمة هو ما يستدعي التبديل.
  final String openRoomId;

  /// يُبلَّغ بعد فتح القسم المطلوب، ليُنظَّف الطلب فلا يُعاد الفتح كل بناء.
  final VoidCallback? onRoomOpened;

  /// يُبلَّغ بالقسم المعروض الآن.
  ///
  /// يحتاجه الغلاف ليمتنع عن إشعار المستخدم برسائل القسم الذي ينظر إليه
  /// بعينه — وهو ما لا يمكن استنتاجه من الغلاف وحده.
  final ValueChanged<String>? onRoomChanged;

  /// الخروج من الدردشة — يعيد الشريطين في الغلاف.
  ///
  /// الدردشة تعمل بملء الشاشة دائماً، فالرأس يحتاج مخرجاً صريحاً بعد أن
  /// اختفى شريط التنقل السفلي.
  final VoidCallback onExit;

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

  /// آخر قيود بلّغنا بها المستخدم — نمنع تكرار التنبيه نفسه كل دورة تحديث.
  String _lastRestriction = '';

  /// محرّك قائمة الرسائل.
  ///
  /// التمرير والتحميل التدريجي وزر «النزول للأسفل» كلها مسؤولية الحزمة بدل
  /// `ScrollController` يدوي: منطق «الرسائل الجديدة» وربط الموضع عند إدراج
  /// رسائل أقدم كان أكثر ما يخطئ فيه الكود المكتوب يدوياً.
  final _chatController = fc.InMemoryChatController();
  final _bridge = ChatBridge();

  /// نصّ الإدخال — نملّكه لنحفظه إن طُلب من المستخدم إكمال هويته.
  final _input = TextEditingController();
  final _focus = FocusNode();


  /// عدد من شاركوا في القسم ومن هم متصل الآن — يُحدَّثان عند فتح القسم فقط.
  int _members = 0;
  int _online = 0;

  /// عيّنات شدة الصوت أثناء التسجيل، وعميل الاستماع إليها.
  final List<double> _waveSamples = [];
  StreamSubscription<Amplitude>? _ampSub;

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
    _load();
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    // طلب فتح قسم من إشعار: الشاشة باقية في `IndexedStack` فلا `initState`
    // جديد، والتبديل لا يقع إلا برصد تغيّر القيمة هنا.
    if (widget.openRoomId.isNotEmpty && widget.openRoomId != old.openRoomId) {
      _openRoomFromOutside(widget.openRoomId);
    }
  }

  /// يفتح قسماً طلبه إشعار، بعد أن تكون الحالة قد حُمّلت.
  Future<void> _openRoomFromOutside(String roomId) async {
    // الحالة قد لا تكون وصلت بعد (الإشعار أسرع من الشبكة)؛ ننتظر انتهاء
    // التحميل الجاري بدل أن نفشل ونبتلع الطلب.
    if (_loading) {
      for (var i = 0; i < 40 && _loading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (!mounted) return;
      }
    }
    if (!mounted) return;
    final room = _rooms.where((r) => r.id == roomId).firstOrNull;
    if (room != null) await _switchRoom(room);
    widget.onRoomOpened?.call();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _recordTick?.cancel();
    _recorder.dispose();
    _ampSub?.cancel();
    _chatController.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
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
      widget.onRoomChanged?.call(room.id);
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
        // العدّاد يأتي في وضع الفتح وحده، فلا نستبدل قيمة سليمة بـnull.
        if (page.members != null) _members = page.members!;
        if (page.online != null) _online = page.online!;
      });
      _syncChatList();
      _jumpToBottom();
      _reportSeen();
    } catch (_) {
      // فشل أول تحميل لا يمسح رسائل موجودة؛ التحديث الدوري سيعيد المحاولة.
    }
  }

  /// يطلبه `ChatAnimatedList` عند بلوغ أعلى القائمة — الدفعة الأقدم.
  Future<void> _onStartReached() async {
    if (_hasMore && !_loadingOlder) await _loadOlder();
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
      setState(() {
        _messages.insertAll(0, page.messages);
        _hasMore = page.hasMore;
        _loadingOlder = false;
      });
      // الحزمة تربط موضع القائمة بنفسها عند إدراج رسائل أقدم، فلا نحفظ
      // الموضع يدوياً ونزيحه — كان ذلك مصدر قفزات في القائمة.
      _syncChatList();
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
        });
        _syncChatList();
        // القائمة المعكوسة تنزل تلقائياً للجديد إن كان المستخدم في الأسفل،
        // فلا نجبره على النزول. `_reportSeen` يبقى: ختم المشاهدة للخادم.
        _reportSeen();
      }
      // حالة الدردشة تُحدَّث في الدورة نفسها، لا عند إعادة التشغيل: غلق
      // الدردشة أو تغيير أقسامها أو كتم المستخدم كلها تُطبَّق في اللوحة،
      // وبدون ذلك يبقى المستخدم على حالة قديمة حتى يخرج من التطبيق.
      await _refreshState();
    } catch (_) {
      // فشل دورة واحدة لا يُظهر خطأ: الشبكة تتقطع لحظياً كثيراً.
    } finally {
      _polling = false;
    }
  }

  /// يجلب حالة الدردشة ويطبّق تغييراتها فوراً على الواجهة.
  ///
  /// يُستدعى من كل دورة تحديث ومن العودة إلى الشاشة، فيرى المستخدم إغلاق
  /// الدردشة أو الكتم لحظياً بدل انتظار إعادة فتح التطبيق.
  Future<void> _refreshState() async {
    final s = await widget.api.chatState();
    if (!mounted) return;
    final changed = !identical(s, _state);
    setState(() {
      _state = s;
      // قسم أُزيل من اللوحة: ننتقل لأول قسم متاح بدل البقاء على قسم ميت.
      if (_room != null && !s.rooms.any((r) => r.id == _room!.id)) {
        _room = s.rooms.isEmpty ? null : s.rooms.first;
      }
    });
    if (changed) _noticeRestriction(s);
  }

  /// يُبلّغ المستخدم بالكتم أو الطرد فور وقوعه — برسالة تشرح السبب.
  ///
  /// التنبيه يظهر مرة واحدة عند تغيّر الحالة فقط، فلا يتحوّل إلى إزعاج
  /// متكرر كل دورة تحديث.
  void _noticeRestriction(ChatState s) {
    final key = '${s.muted}|${s.kicked}|${s.restrictionReason}';
    if (key == _lastRestriction) return;
    _lastRestriction = key;
    if (!s.muted && !s.kicked) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final reason = s.restrictionReason.trim();
    final text = s.kicked
        ? (reason.isEmpty ? 'تم إخراجك من الدردشة' : 'تم إخراجك من الدردشة: $reason')
        : (reason.isEmpty ? 'تم كتمك — تواصل مع المالك' : 'تم كتمك: $reason');
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: XTheme.danger,
        duration: const Duration(seconds: 6),
      ));
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

  /// ينزل إلى آخر رسالة.
  ///
  /// نستخدم أوّل الرسائل في القائمة لا آخرها: القائمة معكوسة (`reversed`)
  /// فالفهرس 0 هو الأحدث. `scrollToIndex` في الحزمة يفهم هذا الترتيب.
  void _jumpToBottom() {
    final last = _messages.isEmpty ? null : _messages.last;
    if (last == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chatController.scrollToMessage(last.id);
    });
  }

  /// يزامن القائمة المعروضة مع `_messages`.
  ///
  /// الحزمة تحتفظ بنسخة `Message` خاصّة بها، فلا تكفي `setState` وحدها:
  /// بدّون هذا النداء تُعرض القائمة القديمة بينما مصدر الحقيقة تغيّر — وهي
  /// بالضبط علّة «رسالة أرسلتها ولا تظهر».
  void _syncChatList() {
    if (!mounted) return;
    final core = [
      for (final m in _messages)
        _bridge.toCore(m, isMine: m.mine),
    ];
    // `setMessages` ينهار إن تكرّر معرّف؛ الرسائل المحلية المؤقّتة لها معرّف
    // فريد، لكن الحماية أرخص من انهيار في الإصدار.
    final seen = <String>{};
    core.retainWhere((m) => seen.add(m.id));
    _chatController.setMessages(core);
  }

  Future<void> _switchRoom(ChatRoom room) async {
    if (_room?.id == room.id) return;
    widget.onRoomChanged?.call(room.id);
    setState(() {
      _room = room;
      _messages.clear();
      _lastAt = 0;
      _reportedSeen = 0;
      _hasMore = false;
      // القائمة تحمل رسائل القسم السابق، وتفريغها يمنع لَمحها لحظة التبديل.
      _syncChatList();
      // أرقام القسم السابق لا تصلح للجديد — تصفيرها يمنع عرض عدد مضلّل.
      _members = 0;
      _online = 0;
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

  /// `text` يأتي من مربّع الحزمة، وهي من فرّغته بعد الإرسال.
  ///
  /// المربّع لا يعرض خطأً بنفسه، فنكتبه في الحقل إن لم نستطع الإرسال
  /// (كتابة موقوفة أو بلا هوية) بدل أن يضيع ما كتبه المستخدم.
  Future<void> _sendText(String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final room = _room;
    if (room == null) return;
    if (!_state.canWrite) {
      _restoreDraft(body);
      _toast(_state.writeBlockedReason.isEmpty
          ? 'لا يمكنك الكتابة حالياً'
          : _state.writeBlockedReason);
      return;
    }
    // الهوية قبل الإرسال: الخادم يرفض الكتابة بلا كنية أو صورة، وكان الرفض
    // يظهر كخطأ بعد كتابة الرسالة فيضيع النص. نفتح اللوحة ونعيد النصّ.
    if (!await _ensureIdentity()) {
      _restoreDraft(body);
      return;
    }
    if (!mounted) return;
    await _send(room.id, text: body);
  }

  /// يعيد نصّاً لم يُرسل إلى الحقل بعد فشل شرط الإرسال.
  void _restoreDraft(String text) {
    if (!mounted) return;
    _input.text = text;
    _input.selection =
        TextSelection.collapsed(offset: _input.text.length);
  }

  /// يضمن أن للمستخدم كنية أو صورة قبل الكتابة؛ يعيد false إن بقي بلا هوية.
  ///
  /// الزائر لا يُسأل: الهوية شرط على الحسابات المسجّلة وحدها، والحساب
  /// المجهول يُخبر صراحةً أنه بحاجة إلى حساب — إلا أن يكون المالك قد
  /// سمح للزوار بالكتابة، فتكون الحاجة إلى الحساب قراراً لا افتراضاً.
  Future<bool> _ensureIdentity() async {
    if (!widget.store.hasSession || widget.store.isGuest) {
      if (AppConfig.instance.guestsCanChat) return true;
      _toast('أنشئ حساباً للمشاركة في الدردشة');
      return false;
    }
    if (_hasIdentity) return true;
    _toast('اختر كنية أو صورة قبل أول رسالة');
    await _openProfile();
    return mounted && _hasIdentity;
  }

  /// هل للمستخدم كنية أو صورة؟ الخادم يقبل أيّاً منهما.
  bool get _hasIdentity =>
      _state.myNickname.trim().isNotEmpty ||
      _state.myAvatarUrl.trim().isNotEmpty;

  /// إرسال موحّد: يعرض الرسالة فوراً كـ«قيد الإرسال» ثم يستبدلها بردّ الخادم.
  ///
  /// العرض الفوري مقصود: انتظار الشبكة قبل ظهور الرسالة يجعل الدردشة تبدو
  /// معطّلة على اتصال ضعيف، وهو أسوأ من رسالة تظهر باهتة لحظة.
  Future<void> _send(String roomId,
      {String text = '',
      String? mediaB64,
      int seconds = 0,
      List<double> waveform = const []}) async {
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
      waveform: waveform,
      pending: true,
    );
    setState(() {
      _messages.add(optimistic);
      _lastAt = optimistic.at;
    });
    _syncChatList();
    _jumpToBottom();

    try {
      final saved = await widget.api.chatSend(roomId,
          text: text,
          mediaB64: mediaB64,
          mediaSeconds: seconds,
          waveform: waveform);
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i >= 0) _messages[i] = saved;
        if (saved.at > _lastAt) _lastAt = saved.at;
      });
      _syncChatList();
      _reportSeen();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i >= 0) _messages[i] = _messages[i].copyWith(pending: false, failed: true);
      });
      _syncChatList();
      _toast(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == tempId);
        if (i >= 0) _messages[i] = _messages[i].copyWith(pending: false, failed: true);
      });
      _syncChatList();
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
    // التعليق المكتوب في الحقل يُرفق بالصورة ثم يُفرّغ، كما كان.
    await _send(_room!.id,
        text: _input.text.trim(), mediaB64: base64Encode(bytes));
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
        _waveSamples.clear();
      });
      // نلتقط شدة الصوت كل 200 مللي ثانية لرسم موجة حقيقية للرسالة.
      //
      // البديل — رسم أعمدة عشوائية — يكذب على المستخدم: الموجة تبدو متغيّرة
      // وهي نفسها لكل المقاطع. القيمة بالديسيبل (سالبة)، فنحوّلها إلى 0..1.
      _ampSub?.cancel();
      _ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen((a) {
        if (!_recording) return;
        _waveSamples.add(((a.current + 60) / 60).clamp(0.0, 1.0));
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

  /// يضغط عيّنات الموجة إلى طول ثابت يرسمه التطبيق.
  ///
  /// عدد العيّنات يتبع مدة التسجيل، وطول الموجة المعروضة ثابت. التوسيط
  /// بالمتوسط (لا بأخذ كل نبضة n) يمنع فقدان المقاطع القصيرة الصاخبة.
  List<double> _compressWave(List<double> src, {int buckets = 48}) {
    if (src.isEmpty) return const [];
    if (src.length <= buckets) return List<double>.from(src);
    final out = <double>[];
    final step = src.length / buckets;
    for (var i = 0; i < buckets; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).ceil().clamp(start + 1, src.length);
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += src[j];
      }
      out.add((sum / (end - start)).clamp(0.0, 1.0));
    }
    return out;
  }

  Future<void> _stopRecording() async {
    _recordTick?.cancel();
    await _ampSub?.cancel();
    _ampSub = null;
    final wave = _compressWave(List<double>.from(_waveSamples));
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
          mediaB64: base64Encode(bytes), seconds: secs, waveform: wave);
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
        _chatHeader(),
        _roomBar(),
        if (_state.welcome.trim().isNotEmpty) _welcomeStrip(),
        // `XChatScope` يلزم: الحزمة تقرأ ثيم Material وترجماته من نسختها
        // (`material_ui`) ولا ترى ثيم `MaterialApp` عندنا. بدونه ترجع إلى
        // ثيم فاتح افتراضي فيظهر نصّ غامق على خلفية غامقة.
        Expanded(child: XChatScope(child: _messageArea())),
      ],
    );
  }

  /// رأس الدردشة: مخرج + هوية القسم + عدّاد الحضور + الإشعارات والملف.
  ///
  /// الإشعارات والملف انتقلا هنا من الشريط السفلي (شريط الأقسام) لأن الشريط
  /// كان يحمل ثلاثة مسؤوليات في سطر واحد: التنقل بين الأقسام، وكتم الإشعارات،
  /// وفتح الملف — فيضيق على الأجهزة الصغيرة ويختلط فيه التنقل بالإعداد. الرأس
  /// مكان الإعدادات، والشريط يبقى للأقسام وحدها.
  Widget _chatHeader() {
    final room = _room;
    if (room == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: XTheme.surface,
        border: Border(
          bottom: BorderSide(color: XTheme.textDim.withOpacity(.10)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 8, 8),
        child: Row(
          children: [
              // الدردشة بملء الشاشة دائماً، فلا شريط تنقّل: هذا المخرج
              // الوحيد الظاهر، ولولاه لبدا التطبيق بلا مخرج.
              IconButton(
                tooltip: 'خروج من الدردشة',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: widget.onExit,
              ),
              _roomBadge(room),
              const SizedBox(width: 11),
              // اسم القسم في الرأس حيث يقرأه المستخدم أولاً، لا في الشريط
              // السفلي بين الأزرار.
              Expanded(child: _roomTitle(room)),
              // كتم/تفعيل إشعارات الدردشة — يعمل فعلاً عبر الخادم، ويحفظ
              // الاختيار للجهاز فلا يُنسى بعد الإغلاق.
              _iconBtn(
                _state.notify
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_off_outlined,
                _state.notify ? 'إشعارات الدردشة مفعّلة' : 'إشعارات الدردشة مكتومة',
                _toggleNotify,
                tint: _state.notify ? XTheme.accent : XTheme.textDim,
              ),
              // الملف الشخصي: الاسم واللون والصورة والأصوات.
              _iconBtn(
                Icons.person_outline,
                _state.myNickname.isEmpty ? 'ملفي' : _state.myNickname,
                _openProfile,
                tint: XTheme.cyan,
              ),
          ],
        ),
      ),
    );
  }

  /// أيقونة القسم داخل قرص متدرّج — نقطة التعرّف البصرية على القسم.
  Widget _roomBadge(ChatRoom room) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: XTheme.gradient,
          borderRadius: BorderRadius.circular(13),
          boxShadow: XTheme.glow(XTheme.accent, strength: .45),
        ),
        child: Icon(_roomIcon(room.icon), size: 19, color: Colors.white),
      );

  /// اسم القسم وسطر الوصف: «N عضواً» دائماً، والرقم الملون عن المتصلين.
  Widget _roomTitle(ChatRoom room) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            room.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              letterSpacing: -.2,
            ),
          ),
          const SizedBox(height: 2),
          // الرقمان قد يتجاوزان عرض الرأس على الأجهزة الضيقة (اسم قسم طويل
          // بجانب شارة الحضور). بلا `Flexible` يتمدّد النصّان فيتجاوزان
          // المساحة ويظهر شريط التشويه الأصفر — وهو عطل عرض لا نقص بيانات:
          // الرقم يبقى مقروءاً في القسم الأعرض.
          Row(
            children: [
              Flexible(
                child: Text(
                  '$_members عضواً',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: XTheme.textDim,
                  ),
                ),
              ),
              if (_online > 0) ...[
                const SizedBox(width: 7),
                _dot(XTheme.textDim.withOpacity(.45), 3),
                const SizedBox(width: 7),
                _dot(XTheme.ok, 6),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '$_online الآن',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: XTheme.ok,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );

  Widget _dot(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

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

  /// شريط الأقسام وحده — الإشعارات والملف انتقلا إلى الرأس.
  ///
  /// كان الشريط يحمل ثلاثة أدوار في سطر: تنقّل + كتم + ملف. حصرُه في التنقّل
  /// يعطي كل قرص عرضاً أكبر ويمنع اللمس الخاطئ بين التنقّل والإعداد.
  Widget _roomBar() {
    return Container(
      decoration: BoxDecoration(
        color: XTheme.surface,
        border: Border(
          bottom: BorderSide(color: XTheme.textDim.withOpacity(.10)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            reverse: true,
            itemCount: _rooms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (_, i) => _roomChip(_rooms[i]),
          ),
        ),
      ),
    );
  }

  /// قرص القسم — النشط متدرّج بحلقة فاتحة، والخامل زجاج شفّاف بلا حدّ.
  Widget _roomChip(ChatRoom r) {
    final active = _room?.id == r.id;
    return GestureDetector(
      onTap: () => _switchRoom(r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? XTheme.gradient : null,
          color: active ? null : XTheme.surface2,
          borderRadius: BorderRadius.circular(30),
          border: active
              ? null
              : Border.all(color: XTheme.textDim.withOpacity(.16)),
          boxShadow: active ? XTheme.glow(XTheme.accent, strength: .45) : null,
        ),
        child: Row(
          children: [
            Icon(_roomIcon(r.icon),
                size: 15, color: active ? Colors.white : XTheme.textDim),
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
    return fchat.Chat(
      currentUserId: ChatBridge.myUserId,
      chatController: _chatController,
      theme: xChatTheme(context),
      resolveUser: (id) async {
        if (id == ChatBridge.myUserId) {
          return fc.User(
            id: id,
            name: _state.myNickname,
            imageSource: _state.myAvatarUrl.isEmpty
                ? null
                : '${kApiBase}${_state.myAvatarUrl}',
          );
        }
        // الرسالة تحمل كائن المؤلّف كاملاً في `metadata`، فلا نحتاج نداء
        // شبكة لحلّ الاسم والصورة.
        for (final m in _messages) {
          if (!m.mine && m.author.id == id) return _bridge.toUser(m.author, id: id);
        }
        return null;
      },
      onMessageSend: _onMessageSend,
      // أزرار الإرفاق تبقى أزرارنا الثلاثة أسفل الشاشة: الصوت تسجيل حيّ لا
      // ملف، والفيديو يُلتقط بالكاميرا مباشرة، ولا يدخلان في قائمة مرفقات
      // الحزمة القياسية (ملف/صورة/فيديو من المعرض).
      onMessageLongPress: _onMessageLongPress,
      builders: fc.Builders(
        composerBuilder: (context) => _composer(),
        chatMessageBuilder: (context, message, index, animation, child,
            {isRemoved, required isSentByMe, groupStatus}) =>
            _messageRow(
          context,
          message,
          index,
          animation,
          child,
          isSentByMe: isSentByMe,
          groupStatus: groupStatus,
        ),
        emptyChatListBuilder: (context) => _emptyList(),
        // القائمة نفسها من الحزمة مع إضافة نداء التحميل التدريجي: الرسائل
        // تُطلب عند بلوغ الأعلى، والحزمة تتولّى ربط الموضع بعد الإدراج.
        chatAnimatedListBuilder: (context, itemBuilder) =>
            fchat.ChatAnimatedList(
          itemBuilder: itemBuilder,
          onStartReached: _onStartReached,
        ),
        // حزمة `chat_ui` لا ترسم وسائط بنفسها: تتركها لمن يحقن بانية. نمرّر
        // وسائطنا الحالية لأنها توقّع روابط Cloudflare قبل التحميل، وهذا ما
        // لا تفعله باقتا `flyer_chat_*` الرسميتان.
        textMessageBuilder: (context, message, index,
                {required isSentByMe, groupStatus}) =>
            _coreBubble(message, isSentByMe: isSentByMe),
        imageMessageBuilder: (context, message, index,
                {required isSentByMe, groupStatus}) =>
            _coreBubble(message, isSentByMe: isSentByMe),
        videoMessageBuilder: (context, message, index,
                {required isSentByMe, groupStatus}) =>
            _coreBubble(message, isSentByMe: isSentByMe),
        audioMessageBuilder: (context, message, index,
                {required isSentByMe, groupStatus}) =>
            _coreBubble(message, isSentByMe: isSentByMe),
        systemMessageBuilder: (context, message, index,
                {required isSentByMe, groupStatus}) =>
            _coreBubble(message, isSentByMe: isSentByMe),
      ),
      backgroundColor: XTheme.bg,
    );
  }

  /// صفّ الرسالة: اسم الكاتب أعلى فقاعة الطرف الآخر، والصور الشخصية على
  /// الجانبين. القائمة معكوسة فالفقاعات الجديدة في الأسفل.
  Widget _messageRow(
    BuildContext context,
    fc.Message message,
    int index,
    Animation<double> animation,
    Widget child, {
    required bool isSentByMe,
    fc.MessageGroupStatus? groupStatus,
  }) {
    // `groupStatus` يقول هل هذه أول رسالة في مجموعة متتالية؛ نُخفي الاسم
    // والصورة عند التكرار كما اعتاد المستخدم في النسخة السابقة.
    final first = groupStatus?.isFirst ?? true;
    return fchat.ChatMessage(
      message: message,
      index: index,
      animation: animation,
      child: child,
      headerWidget: !isSentByMe && first ? _senderName(message) : null,
      leadingWidget: !isSentByMe ? _authorAvatar(message) : null,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    );
  }

  Widget? _senderName(fc.Message message) {
    final m = ChatBridge.unwrap(message);
    if (m == null) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3, right: 42, left: 6),
      child: Text(m.author.label,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
              color: XTheme.textDim)),
    );
  }

  Widget? _authorAvatar(fc.Message message) {
    final m = ChatBridge.unwrap(message);
    if (m == null) return null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: _avatar(m.author, size: 34),
    );
  }

  Widget _emptyList() => _noticeView(
        icon: Icons.chat_bubble_outline,
        title: 'لا رسائل في ${_room?.name ?? 'القسم'} بعد',
        body: _state.canWrite
            ? 'كن أول من يبدأ الحديث'
            : _state.writeBlockedReason,
      );

  /// الضغط المطوّل: حذف رسالتي، أو حذف أي رسالة إن كنت المالك.
  ///
  /// الخادم هو من يفرض القاعدة فعلاً (`caller.role !== 'owner'`)، وهذه
  /// الواجهة تعرض ما يسمح به فقط — زر يرفضه الخادم أسوأ من غياب الزر.
  ///
  /// الصور والفيديو تُفتح من داخل الفقاعة نفسها (`_imageContent`)، فلا
  /// نكرّر الفتح هنا وإلا انفتح العارض مرّتين للضغطة الواحدة.
  void _onMessageLongPress(BuildContext context, fc.Message message,
      {required int index, required LongPressStartDetails details}) {
    final m = ChatBridge.unwrap(message);
    if (m == null) return;
    final mine = message.authorId == ChatBridge.myUserId;
    if (m.pending || m.id.isEmpty) return;
    if (mine) {
      _confirmDelete(m);
      return;
    }
    if (widget.store.isOwner) _confirmModerationDelete(m);
  }

  /// حذف رسالة غيري بصفة المالك.
  ///
  /// تأكيد صريح مقصود: هذا إجراء لا رجعة فيه على محتوى شخص آخر، وقد
  /// يقع بالخطأ لأن الضغط المطوّل يبدأ بلمسة عابرة.
  Future<void> _confirmModerationDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(XTheme.rLg)),
        title: const Text('حذف رسالة العضو؟',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الصاحب: ${m.author.label}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(
              m.isText
                  ? 'ستُحذف هذه الرسالة من الدردشة للجميع، ولا يمكن التراجع.'
                  : 'سيُحذف هذا المرفق من الدردشة للجميع، ولا يمكن التراجع.',
              style: TextStyle(fontSize: 13, color: XTheme.textDim, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: TextStyle(color: XTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف',
                style: TextStyle(
                    color: XTheme.danger, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.chatDelete(m.id);
      if (!mounted) return;
      setState(() => _messages.removeWhere((x) => x.id == m.id));
      _syncChatList();
      _toast('حُذفت رسالة العضو');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('تعذر الحذف — تحقق من الإنترنت');
    }
  }

  /// نصّ جديد من المربّع — نفس مسار `_sendText` لكن الحزمة هي من ناداه،
  /// فنعيد ما كُتب إن فشل الشرط بدل أن يضيع.
  void _onMessageSend(String text) {
    final message = text.trim();
    if (message.isEmpty) return;
    _sendText(message);
  }

  /// فقاعة الرسالة — الشكل يتبع السمة التي يختارها المالك.
  /// فقاعة الرسالة — الشكل يتبع السمة التي يختارها المالك.
  ///
  /// نبنيها نحن لمّا تمرّره الحزمة من بانية، لأن كل رسالة عندنا تحتاج
  /// توقيع رابط Cloudflare قبل تحميلها، وعرض المشاهدين، وشكل فقاعة من
  /// سمة التطبيق. الحزمة تتولّى الترتيب والمحاذاة والتحريك فقط.
  Widget _coreBubble(fc.Message message, {required bool isSentByMe}) {
    final m = ChatBridge.unwrap(message);
    if (m == null) return const SizedBox.shrink();
    if (m.kind == 'system') return _systemBubble(m);
    final mine = isSentByMe;
    final radius = _bubbleRadius(_state.theme);
    final bubbleColor = mine
        ? null
        : (XTheme.isLight ? Colors.white : XTheme.surface2);
    // نصّ الفقاعة: غامق على البرتقالي الفاتح، والأبيض فوقه غير مقروء.
    final onBubble = mine ? chatOnAccent : XTheme.text;

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
                color: onBubble,
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
                          ? onBubble.withOpacity(.75)
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
                      : onBubble.withOpacity(.85),
                ),
              ],
            ],
          ),
        ),
        // صور المشاهدين تحت الرسالة — كما في ماسنجر.
        if (mine && m.seenBy.isNotEmpty) _seenRow(m),
      ],
    );

    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .78),
      decoration: BoxDecoration(
        gradient: mine ? XTheme.gradient : null,
        color: bubbleColor,
        borderRadius: radius,
        boxShadow: mine
            ? XTheme.glow(XTheme.accent, strength: .30)
            : XTheme.shadow(lift: .4),
        border: mine
            ? null
            : Border.all(
                color: XTheme.isLight
                    ? Colors.black.withOpacity(.05)
                    : Colors.white.withOpacity(.07),
              ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: content,
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
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(XTheme.rSm),
          child: SizedBox(
            // مقاس ثابت قبل وصول الصورة وبعدها.
            //
            // الصورة كانت تُقاس بمحتواها، فتظهر بحجم أثناء التحميل ثم تقفز
            // إلى حجمها الحقيقي فور اكتماله — ومع كل إعادة تنزيل تتكرّر
            // القفزة ويهتز كل ما تحتها. إطار ثابت يجعل العرض ثابتاً من
            // اللحظة الأولى، والصورة تملؤه بلا تحرّك.
            width: _imageWidth,
            height: _imageHeight,
            child: Image.network(
              _mediaUrl(url),
              headers: _mediaHeaders(url),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              loadingBuilder: (context, child, p) {
                if (p == null) return child;
                // شريط تقدّم رقيق فوق الإطار بدل استبدال الصورة بمربع رمادي:
                // الصورة تظهر تدريجياً فلا تبدو الشاشة فارغة ثم ممتلئة.
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: XTheme.surface2),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: p.expectedTotalBytes != null
                            ? p.cumulativeBytesLoaded /
                                p.expectedTotalBytes!
                            : null,
                        minHeight: 3,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation(
                            XTheme.accent),
                      ),
                    ),
                  ],
                );
              },
              errorBuilder: (context, error, stack) => Container(
                color: XTheme.surface2,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: XTheme.textDim, size: 26),
                    const SizedBox(height: 6),
                    Text('تعذر تحميل الصورة',
                        style: TextStyle(
                            fontSize: 10.5, color: XTheme.textDim)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// مقاس إطار الصورة في الفقاعة.
  ///
  /// ثابت لا يتبع الصورة، وإلا عاد الاهتزاز. 220×165 يبدو جيداً على الجوال
  /// ولا يترك فراغاً كبيراً في الرسائل النصية القصيرة المجاورة.
  static const double _imageWidth = 220;
  static const double _imageHeight = 165;

  /// رابط الوسيط كاملاً — الروابط النسبية تُسبق بعنوان الـWorker.
  String _mediaUrl(String url) =>
      url.startsWith('/') ? '$kApiBase$url' : url;

  /// ترويسات الوسيط: الروابط النسبية محمية بتوقيع الطلب، والخارجية لا.
  ///
  /// التوقيع ثابت داخل نافذة صلاحيته (انظر Api.signFor) لأن توليده في كل
  /// بناء يجعل Flutter يعتبر الصورة جديدة فيعيد تنزيلها ويرتجّ العرض.
  Map<String, String>? _mediaHeaders(String url) =>
      url.startsWith('/') ? widget.api.signFor('GET', url) : null;

  Widget _audioContent(ChatMessage m, bool mine) => _VoicePlayer(
        api: widget.api,
        url: m.mediaUrl,
        mine: mine,
        waveform: m.waveform,
        seconds: m.seconds,
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

  /// تأكيد حذف رسالة، ثم حذفها من الخادم والقائمة.
  ///
  /// التأكيد ضروري: الضغط المطوّل يقع بالخطأ عند التمرير، وحذف بلا سؤال
  /// لا رجعة فيه. نطالب بالخادم أولاً ثم نمسح محلياً، فلو فشل الحذف بقيت
  /// الرسالة ظاهرة بدل أن تختفي ثم تعود في التحديث التالي.
  Future<void> _confirmDelete(ChatMessage m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(XTheme.rLg)),
        title: const Text('حذف الرسالة؟',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
        content: Text(
          m.isText
              ? 'ستُحذف هذه الرسالة من الدردشة للجميع.'
              : 'سيُحذف هذا المرفق من الدردشة للجميع.',
          style: TextStyle(fontSize: 13.5, color: XTheme.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: TextStyle(color: XTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف',
                style: TextStyle(
                    color: XTheme.danger, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.api.chatDelete(m.id);
      if (!mounted) return;
      setState(() => _messages.removeWhere((x) => x.id == m.id));
      _syncChatList();
      _toast('حُذفت الرسالة');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('تعذر الحذف — تحقق من الإنترنت');
    }
  }

  // ───────────────────────── شريط الكتابة ─────────────────────────

  Widget _composer() {
    if (_recording) {
      final secs =
          ((DateTime.now().millisecondsSinceEpoch - _recordStart) ~/ 1000)
              .clamp(0, _state.mediaSeconds);
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            color: XTheme.surface,
            border:
                Border(top: BorderSide(color: XTheme.danger.withOpacity(.24))),
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
        ),
      );
    }

    if (!_state.canWrite) {
      // `Positioned` لا `Container` عارياً: بانية الكومبوزر تُركَّب داخل `Stack`
      // في الحزمة، وعنصر بلا موضع يُرسم في أعلى المكدّس فوق الرسائل.
      return Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
          decoration: BoxDecoration(
            color: XTheme.surface,
            border: Border(
                top: BorderSide(color: XTheme.textDim.withOpacity(.12))),
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
        ),
      );
    }

    // `fchat.Composer` يعيد `Positioned` **دائماً**، فهو لا يصلح إلا طفلاً
    // مباشراً في `Stack` الداخلي للحزمة. لفّه في `Row`/`Expanded` يهدم
    // ParentData فيتعطّل الكومبوزر بأكمله ويظهر الفراغ الأبيض الذي رآه
    // المستخدم. لذلك نمرّر أزرارنا عبر `topWidget` — وهي الوسيلة المدعومة.
    return fchat.Composer(
      textEditingController: _input,
      focusNode: _focus,
      hintText: 'اكتب رسالة…',
      maxLines: 4,
      maxLength: _state.maxLength,
      textColor: XTheme.text,
      hintColor: XTheme.textDim,
      backgroundColor: XTheme.surface,
      inputFillColor: XTheme.surface2,
      sendIconColor: chatOnAccent,
      emptyFieldSendIconColor: XTheme.textDim,
      sendButtonVisibilityMode: fchat.SendButtonVisibilityMode.hidden,
      padding: const EdgeInsets.fromLTRB(8, 9, 8, 8),
      topWidget: _attachBar(),
    );
  }

  /// شريط الإرفاق فوق حقل الكتابة.
  ///
  /// كان إلى جانب الحقل قبل أن نكتشف أن الكومبوزر عنصر مكدّس لا صفّي. وضعه
  /// في `topWidget` يحفظ الأزرار الثلاثة (صورة، فيديو، صوت) كما كان المستخدم
  /// يعرفها بلا مصادمة تخطيط.
  Widget _attachBar() => Row(
        children: [
          _composerIcon(
              Icons.add_photo_alternate_outlined, 'صورة', _pickImage),
          if (_state.mediaScope != 'none')
            _composerIcon(Icons.videocam_outlined, 'فيديو', _pickVideo),
          _composerIcon(
            _recording ? Icons.stop_circle_outlined : Icons.mic_none,
            'رسالة صوتية',
            _toggleRecording,
            tint: _recording ? XTheme.danger : null,
          ),
        ],
      );

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
  Future<void> _reloadStateOnly() => _refreshState();

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
  const _VoicePlayer({
    required this.api,
    required this.url,
    required this.mine,
    this.waveform = const [],
    this.seconds = 0,
  });
  final Api api;
  final String url;
  final bool mine;

  /// مخطط الموجة الفعلي للرسالة، ومدتها بالثواني كما أرسلها صاحبها.
  final List<double> waveform;
  final int seconds;

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
        ? (widget.seconds > 0 ? widget.seconds * 1000 : 1)
        : _total.inMilliseconds;
    final progress =
        total <= 0 ? 0.0 : (_pos.inMilliseconds / total).clamp(0.0, 1.0);
    final elapsed = _playing || _pos > Duration.zero
        ? _pos.inSeconds
        : (total ~/ 1000);
    final wave = widget.waveform.isEmpty
        ? _fallbackWave
        : widget.waveform;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: widget.mine
                    ? Colors.white.withOpacity(.22)
                    : XTheme.accent.withOpacity(.14),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 21,
                color: widget.mine ? Colors.white : XTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 9),
          // الأعمدة تُرسم بمقياس ثابت (ارتفاع كامل) واللون يميّز ما سُمع
          // عمّا بقي. هذا سلوك تطبيقات المراسلة المعروفة: المستخدم يرى
          // موضعه في المقطع بنظرة بدل قراءة رقم.
          SizedBox(
            width: 132,
            height: 30,
            child: CustomPaint(
              painter: _WavePainter(
                values: wave,
                progress: progress,
                dim: fg.withOpacity(.32),
                active: widget.mine ? Colors.white : XTheme.accent,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt(Duration(seconds: elapsed)),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: fg.withOpacity(.85)),
          ),
        ],
      ),
    );
  }

  /// موجة رمزية حين لا يصل مخطط من الخادم (مقطع قديم أُرسل قبل الميزة).
  ///
  /// ثابتة لا عشوائية: العشوائية تُعاد مع كل بناء فيتغيّر شكل الموجة أمام
  /// المستخدم أثناء التشغيل، فيبدو الرسم معطوباً.
  static const _fallbackWave = <double>[
    .2, .35, .5, .4, .65, .8, .55, .4, .6, .45, .3, .5,
    .7, .6, .45, .35, .55, .75, .6, .4, .3, .5, .65, .45,
    .35, .55, .4, .6, .5, .35, .45, .6, .7, .5, .35, .25,
  ];
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

/// يرسم مخطط الموجة: أعمدة، المُستمَع منها بلون بارز وما بقي باهتاً.
class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.values,
    required this.progress,
    required this.dim,
    required this.active,
  });

  final List<double> values;
  final double progress;
  final Color dim;
  final Color active;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final n = values.length;
    // فجوة ثابتة بين الأعمدة؛ العرض المتبقي يوزّع على الأعمدة، فتملأ الموجة
    // الإطار مهما كان عدد النقاط (48 من التسجيل أو 36 في الموجة الرمزية).
    const gap = 2.0;
    final barW = ((size.width - gap * (n - 1)) / n).clamp(1.0, 6.0);
    final paint = Paint()..strokeCap = StrokeCap.round;
    final cut = progress * n;
    for (var i = 0; i < n; i++) {
      // أدنى ارتفاع 3 بكسل: الصمت المطلق لا يرسم خطاً غير مرئي يوهم بعطل.
      final h = (values[i].clamp(0.0, 1.0) * size.height).clamp(3.0, size.height);
      final x = i * (barW + gap) + barW / 2;
      paint.color = i < cut ? active : dim;
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint..strokeWidth = barW,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.values != values ||
      old.progress != progress ||
      old.dim != dim ||
      old.active != active;
}
