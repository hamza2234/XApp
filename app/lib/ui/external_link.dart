import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';

/// يحوّل رابط تيليجرام `https://t.me/<اسم>` إلى مخطط `tg://` الذي يملكه
/// تطبيق تيليجرام وحده.
///
/// السبب: أندرويد يربط مخطط `https` بالمتصفح افتراضياً، فلا يفتح رابط
/// `https://t.me/...` تطبيق تيليجرام إلا إن اختار المستخدم «افتح دائماً»
/// فيه. لذلك كان الضغط على «تواصل مع المالك» يفتح المتصفح لا تيليجرام.
/// مخطط `tg://` يحوّل مباشرة إلى التطبيق إن كان مثبتاً.
///
/// يرجع `null` إن لم يكن رابط تيليجرام — فلا تُمس بقية الروابط.
String? telegramAppUri(String url) {
  final raw = url.trim();
  if (raw.isEmpty) return null;
  if (raw.toLowerCase().startsWith('tg://')) return raw;

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  // نطاق تيليجرام وحده — لا تُقبل نطاقات ملتبسة مثل t.me.evil.com.
  if (host != 't.me' && host != 'telegram.me' && host != 'www.t.me') {
    return null;
  }

  final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final first = segs.first;

  // رابط دعوة بمفتاح +: يُفتح عبر join لا resolve.
  final invite = first.startsWith('+') ? first.substring(1) : null;
  final params = <String, String>{
    if (invite == null) 'domain': first else 'invite': invite,
    // تُحفظ بقية المعاملات (text/start) كي تصل الرسالة الجاهزة كما هي.
    ...{
      for (final e in uri.queryParameters.entries)
        if (e.key != 'domain' && e.key != 'invite') e.key: e.value
    },
  };
  return Uri(
    scheme: 'tg',
    host: invite == null ? 'resolve' : 'join',
    queryParameters: params,
  ).toString();
}

/// وجهات الإطلاق لرابط: مخطط التطبيق أولاً ثم الرابط الأصلي كبديل.
List<Uri> launchCandidates(String url) => [
      if (telegramAppUri(url) case final app?) Uri.parse(app),
      if (Uri.tryParse(url.trim()) case final web? when web.hasScheme) web,
    ];

/// فتح رابط خارجي في تطبيقه الأصلي، مع بديل إن لم يوجد تطبيق يفتحه.
///
/// تيليجرام يُفتح عبر مخطط `tg://` ليصل لتطبيق تيليجرام مباشرة بدل
/// المتصفح، ثم يُجرَّب الرابط الأصلي إن لم يكن التطبيق مثبتاً.
/// `canLaunchUrl` لا يُعتمد عليه وحده: قد يعيد false على أندرويد 11+
/// للتطبيقات غير المعلَنة في `<queries>`. لذلك نحاول الإطلاق دائماً.
Future<void> openExternal(BuildContext context, String url,
    {String label = 'الرابط'}) async {
  if (url.trim().isEmpty) {
    _notify(context, 'لم يضبط المالك رابط $label بعد');
    return;
  }
  final candidates = launchCandidates(url);
  if (candidates.isEmpty) {
    _notify(context, 'رابط غير صالح: $url');
    return;
  }

  for (final uri in candidates) {
    for (final mode in [
      LaunchMode.externalApplication,
      LaunchMode.platformDefault
    ]) {
      try {
        if (await launchUrl(uri, mode: mode)) return;
      } catch (_) {
        // نجرّب الوضع ثم الوجهة التالية
      }
    }
  }

  if (context.mounted) {
    _manualCopyDialog(context, url, label);
  }
}

void _notify(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// يعرض الرابط لفتحه أو نسخه يدوياً إن تعذّر الإطلاق التلقائي.
void _manualCopyDialog(BuildContext context, String url, String label) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: XTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('تعذّر الفتح تلقائياً',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('افتح $label يدوياً من الرابط التالي:',
            style: TextStyle(color: XTheme.textDim, fontSize: 12.5)),
        const SizedBox(height: 10),
        SelectableText(url,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5)),
      ]),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
      ],
    ),
  );
}