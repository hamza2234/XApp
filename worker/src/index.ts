/**
 * x-app-api — الواجهة الخلفية الآمنة لتطبيق X
 *
 * مبادئ العزل:
 *  - MIRROR (phonex-mirror) و SCHEMATICS (phonex-schematics): قراءة فقط.
 *    لا يوجد أي استدعاء put/delete على هذه الموارد في هذا الملف.
 *  - XDB (x-app-db) و QUOTA (x-app-quota): ملك تطبيق X وحده.
 *
 * طبقات الأمان:
 *  1) حظر أدوات السكريبت (User-Agent)
 *  2) تصعيد حظر IP عند تكرار الطلبات الفاشلة
 *  3) توقيع HMAC لكل طلب (X-App-Ts + X-App-Sig) — بدونه يُرفض الطلب
 *  4) JWT للجلسات + ربط الحساب بجهاز واحد
 *  5) كشف مزارع الأجهزة (IP واحد بأجهزة كثيرة)
 *  6) سجل أحداث أمنية (جهاز + IP + مسار + سبب) يطلع عليه المالك
 *  7) حصة يومية للزائر على فتح ملفات المخططات — يتحكم بها المالك
 *  8) بوابة إصدارات: إيقاف الإصدارات القديمة من لوحة المالك
 */

// ============================== Crypto ==============================

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message)
  }
}

/**
 * مفتاح تشفير ردود لوحة المالك، مشتق من جلسة المالك نفسها.
 *
 * الغرض: لو تسرّبت استجابة لوحة المالك (سجل وسيط، نسخة احتياطية، كاش)
 * يبقى محتواها غير مقروء. لماذا من الجلسة وليس من سرّ ثابت؟ لأن أي سرّ
 * ثابت يجب أن يُضمَّن في التطبيق ليتمكن من الفك، فيصبح مكشوفاً لأي من
 * يفكّ الـAPK. الجلسة وحدها يملكها المالك، وتنتهي بانتهائها.
 *
 * هذا يحمي المحتوى أثناء النقل والتخزين، ولا يغني عن TLS: من يقرأ
 * الترويسات يقرأ الجلسة، لكنه لا يقرأ الأجسام من السجلات أو النسخ.
 */
async function ownerCipherKey(token: string): Promise<CryptoKey> {
  const material = await crypto.subtle.digest(
    'SHA-256', new TextEncoder().encode(`xapp-owner-panel-v1|${token}`)
  )
  return crypto.subtle.importKey('raw', material, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt'])
}

/** يشفّر رد لوحة المالك: AES-GCM مع nonce عشوائي لكل استجابة. */
async function ownerSeal(token: string, payload: unknown): Promise<string> {
  const nonce = new Uint8Array(12)
  crypto.getRandomValues(nonce)
  const key = await ownerCipherKey(token)
  const plain = new TextEncoder().encode(JSON.stringify(payload))
  const cipher = await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce }, key, plain)
  return `${b64e(nonce)}.${b64e(cipher)}`
}

/** يفكّ ما شفّره ownerSeal — يُستخدم في الاختبارات والتحقق. */
async function ownerOpen(token: string, sealed: string): Promise<unknown> {
  const [n, c] = sealed.split('.')
  const key = await ownerCipherKey(token)
  const plain = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: b64d(n) }, key, b64d(c)
  )
  return JSON.parse(new TextDecoder().decode(plain))
}

function b64e(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data)
  let binary = ''
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function b64d(str: string): Uint8Array {
  const padded = str.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (str.length % 4)) % 4)
  const binary = atob(padded)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    'raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']
  )
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const key = await hmacKey(secret)
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message))
  return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, '0')).join('')
}

async function signJwt(payload: Record<string, unknown>, secret: string, ttlSeconds: number): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const data = `${b64e(new TextEncoder().encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })))}.${b64e(new TextEncoder().encode(JSON.stringify({ ...payload, iat: now, exp: now + ttlSeconds })))}`
  const sig = await crypto.subtle.sign('HMAC', await hmacKey(secret), new TextEncoder().encode(data))
  return `${data}.${b64e(sig)}`
}

async function verifyJwt(token: string, secret: string): Promise<Record<string, any>> {
  const parts = token.split('.')
  if (parts.length !== 3) throw new HttpError(401, 'invalid token')
  const data = `${parts[0]}.${parts[1]}`
  const valid = await crypto.subtle.verify('HMAC', await hmacKey(secret), b64d(parts[2]), new TextEncoder().encode(data))
  if (!valid) throw new HttpError(401, 'invalid token')
  const payload = JSON.parse(new TextDecoder().decode(b64d(parts[1])))
  if (typeof payload.exp === 'number' && payload.exp < Math.floor(Date.now() / 1000)) {
    throw new HttpError(401, 'token expired')
  }
  return payload
}

async function pbkdf2(password: string, salt: Uint8Array): Promise<string> {
  const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits'])
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' }, base, 256)
  return b64e(bits)
}

async function hashPassword(password: string): Promise<string> {
  const salt = new Uint8Array(16)
  crypto.getRandomValues(salt)
  return `pbkdf2$100000$${b64e(salt)}$${await pbkdf2(password, salt)}`
}

async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const parts = stored.split('$')
  if (parts.length !== 4 || parts[0] !== 'pbkdf2') return false
  return (await pbkdf2(password, b64d(parts[2]))) === parts[3]
}

// ============================== Helpers ==============================

interface Env {
  MIRROR: D1Database
  XDB: D1Database
  QUOTA: KVNamespace
  SCHEMATICS: R2Bucket
  XMEDIA: R2Bucket
  X_JWT_SECRET: string
  X_SIG_SECRET: string
  X_OWNER_KEY: string
  X_OWNER_JWT_SECRET?: string
  X_FILE_KEY: string
  /** حساب خدمة Firebase (JSON كامل) — إن غاب، الدفع معطّل بهدوء. */
  FCM_SERVICE_ACCOUNT?: string
  /** معرّف مشروع Firebase — يُقرأ من الحساب إن لم يُضبط هنا. */
  FCM_PROJECT_ID?: string
}

interface Caller { uid: string; role: string }

const DAY = 86400
const FOLDER_MIME = 'application/vnd.google-apps.folder'
const LOCAL_PREFIX = 'local:'
const LOCAL_R2 = 'local/'
const ROOT_CATALOG = 'catalog/v1/brands.json'

const BLOCKED_UA = /(curl|wget|python-requests|python-urllib|scrapy|go-http-client|libwww|node-fetch|axios\/|postmanruntime|httpie)|^\s*$|bot|spider|crawler/i

function json(body: unknown, status = 200, extra?: Record<string, string>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', ...extra }
  })
}

function ip(request: Request): string {
  return request.headers.get('cf-connecting-ip')?.trim() || 'unknown'
}

function deviceOf(request: Request): string {
  return request.headers.get('x-device-id')?.trim() ?? ''
}

function versionOf(request: Request): number {
  return Number(request.headers.get('x-app-version')?.trim() || '0') || 0
}

function today(): string {
  return new Date().toISOString().slice(0, 10)
}

function uid(): string {
  return `${Date.now().toString(36)}_${crypto.randomUUID().replace(/-/g, '').slice(0, 16)}`
}

// ============================== X DB helpers ==============================

interface XUser {
  id: string; username: string; display_name: string; role: string
  quota_balance: number; quota_expires_at: number
  active: number; device_id: string | null; expires_at: number
}

async function xUser(XDB: D1Database, id: string): Promise<XUser | null> {
  return XDB.prepare('SELECT * FROM x_users WHERE id = ?1').bind(id).first<XUser>()
}

async function xUserByName(XDB: D1Database, username: string): Promise<XUser | null> {
  return XDB.prepare('SELECT * FROM x_users WHERE username = ?1 COLLATE NOCASE').bind(username).first<XUser>()
}

interface XSettings {
  dailyFreeQuota: number          // المنحة اليومية الواحدة لكل مستخدم (زائر أو مسجل أو مشترك)
  guestFileQuota: number          // مهجور: يُعاد كتابته من dailyFreeQuota للتوافق مع النسخ القديمة
  minVersion: number              // أدنى إصدار مسموح
  blockedVersions: number[]       // إصدارات موقوفة تحديداً
  telegramLink: string
  schematicsLocked: boolean       // قفل المخططات كلياً عن الزوار
  compatLocked: boolean           // قفل التوافقات عن الزوار
  compatSearchCost: number        // ثمن دخول الشركة في التوافقات بالعملات (0 = مجاني)
  guestCompatQuota: number        // مهجور: كان حصة مستقلة للتوافقات، صار نسخة من dailyFreeQuota
  appLocked: boolean              // قفل التطبيق كلياً (صيانة)
  lockMessage: string
  updateMessage: string           // رسالة شاشة التحديث الإجباري
  updateUrl: string               // رابط زر التحديث
  updateImageUrl: string          // صورة شاشة التحديث
  packages: { cards: number; price: string; days: number; desc: string }[]  // باقات العملات
  privacyPolicy: string           // سياسة الخصوصية — يكتبها المالك وتظهر للمستخدم
  // ── الدردشة المجتمعية ──
  chatEnabled: boolean            // تشغيل/إيقاف الدردشة كلياً
  chatReadOnly: boolean           // وضع القراءة فقط: تُقرأ الرسائل ولا تُكتب
  chatRooms: { id: string; name: string; icon: string }[]  // أقسام الدردشة
  chatTheme: string               // سمة الدردشة: classic | bubble | dark | neon
  chatWelcome: string             // رسالة نظام تُعرض عند دخول أي قسم
  chatMaxLength: number           // أقصى طول للرسالة النصية
  chatImagesEnabled: boolean      // السماح برفع الصور في الدردشة
  chatWriteScope: string          // من يكتب: all | registered | subscribers
  chatMediaScope: string          // من يرسل صوت/فيديو: subscribers | none
  chatMaxMediaMb: number          // أقصى حجم للمقطع الصوتي/المرئي بالميغابايت
  chatMediaSeconds: number        // أقصى مدة للمقطع بالثواني
  chatPollMs: number              // دور تحديث الدردشة في التطبيق (مللي ثانية)
}

const DEFAULT_SETTINGS: XSettings = {
  dailyFreeQuota: 5,
  guestFileQuota: 5,
  minVersion: 1,
  blockedVersions: [],
  telegramLink: 'https://t.me/phonex6',
  schematicsLocked: false,
  compatLocked: false,
  compatSearchCost: 1,
  guestCompatQuota: 5,
  appLocked: false,
  lockMessage: '',
  updateMessage: 'يتوفر إصدار جديد — حدّث التطبيق للمتابعة',
  updateUrl: '',
  updateImageUrl: '',
  packages: [
    { cards: 150, price: '3$', days: 60, desc: 'صالحة لغاية شهرين' },
    { cards: 300, price: '5$', days: 150, desc: 'صالحة لغاية 5 أشهر' },
    { cards: 500, price: '7$', days: 365, desc: 'صالحة لغاية سنة كاملة' },
  ],
  // نص افتراضي مفهوم بلغة واضحة. المالك يستبدله من لوحته، ووجوده هنا يضمن
  // ألا يظهر للمستخدم صندوق فارغ إن لم يكتب المالك نصاً بعد.
  privacyPolicy: `نحن في MAPX نحترم خصوصيتك ونوضح لك بلغة بسيطة ما نجمعه ولماذا.
ما نجمعه:
• معرّف الجهاز: رقم مشتق من جهازك، نستخدمه لربط حسابك بجهازك ومنحك حصتك اليومية. لا يمكن من خلاله معرفة هويتك.
• عنوان الإنترنت (IP): نستخدمه لحماية التطبيق من الهجمات والاستخدام الآلي المسيء.
• اسم المستخدم وكلمة المرور: كلمة المرور تُخزَّن مشفّرة، ولا يمكن لأحد — بمن فيهم نحن — قراءتها.

ما لا نجمعه:
• لا نصل إلى جهات الاتصال أو الصور أو الرسائل أو الموقع الجغرافي.
• لا نبيع بياناتك ولا نشاركها مع أي طرف ثالث لأغراض تجارية.

كيف تُستخدم بياناتك:
• لتشغيل حسابك وحفظ رصيدك وحصتك اليومية.
• لحماية التطبيق من العبث والهجمات.

الاحتفاظ والحذف:
• تبقى بياناتك ما دام حسابك قائماً. يمكنك طلب حذف حسابك وبياناتك في أي وقت عبر التواصل مع المالك.

المسؤولية:
• أنت مسؤول عن سرّية كلمة مرورك. لا تشارك حسابك مع الآخرين.

بالمتابعة أنت توافق على هذه السياسة.`,

  // ── الدردشة: مفعّلة بأقسام جاهزة، والمالك يعدّلها من لوحته ──
  chatEnabled: true,
  chatReadOnly: false,
  chatRooms: [
    { id: 'general', name: 'العامة', icon: 'chat' },
    { id: 'help', name: 'مساعدة وإصلاح', icon: 'build' },
    { id: 'parts', name: 'قطع وموديلات', icon: 'memory' },
    { id: 'offers', name: 'عروض وتجار', icon: 'store' },
  ],
  chatTheme: 'bubble',
  chatWelcome: 'أهلاً بك — التزم بالأدب ولا تشارك بياناتك الخاصة مع أحد.',
  chatMaxLength: 1000,
  chatImagesEnabled: true,
  // الكتابة للمسجّلين، والصوت/الفيديو للمشتركين السارين فقط. الافتراضي
  // الأكثر تقييداً حتى يقرر المالك خلافه.
  chatWriteScope: 'registered',
  chatMediaScope: 'subscribers',
  chatMaxMediaMb: 12,
  chatMediaSeconds: 120,
  chatPollMs: 4000,
}

async function xSettings(XDB: D1Database): Promise<XSettings> {
  const row = await XDB.prepare("SELECT data FROM x_settings WHERE id = 'main'").first<{ data: string }>()
  if (!row) return { ...DEFAULT_SETTINGS }
  try {
    const raw = JSON.parse(row.data) as Partial<XSettings>
    return normalizeSettings({ ...DEFAULT_SETTINGS, ...raw }, raw)
  } catch { return { ...DEFAULT_SETTINGS } }
}

/**
 * المنحة اليومية صارت واحدة لكل المستخدمين، وكانت منفصلة: حصة للملفات
 * وحصة للتوافقات. صفّ قديم بلا الحقل الجديد يحمل الرقمين، وأخذ أحدهما فقط
 * يغيّر ما اعتاده المالك — نأخذ الأكبر. أما 0 فيبقى 0: إلغاء المنحة قرار
 * صريح من المالك لا يُستبدل بالافتراضي.
 */
function normalizeSettings(s: XSettings, raw: Partial<XSettings>): XSettings {
  if (raw.dailyFreeQuota === undefined) {
    const legacy = Math.max(Number(raw.guestFileQuota) || 0, Number(raw.guestCompatQuota) || 0)
    if (legacy > 0) s.dailyFreeQuota = Math.min(1000, legacy)
  }
  s.dailyFreeQuota = Math.max(0, Math.min(1000, Math.floor(Number(s.dailyFreeQuota) || 0)))
  // الحقلان المهجوران يبقيان معروضين في bootstrap بنفس القيمة كي لا تظن
  // نسخة قديمة من التطبيق أن المالك ألغى المنحة.
  s.guestFileQuota = s.dailyFreeQuota
  s.guestCompatQuota = s.dailyFreeQuota

  // أقسام الدردشة: نُبقي معرّفات صالحة فقط، ونمنع التكرار — معرّف مكرر كان
  // سيجمع رسائل قسمين في قسم واحد بلا أن يظهر خطأ للمالك.
  const seen = new Set<string>()
  const rooms = (Array.isArray(s.chatRooms) ? s.chatRooms : [])
    .map(r => ({
      id: String(r?.id ?? '').trim().toLowerCase().replace(/[^\w-]/g, '').slice(0, 24),
      name: String(r?.name ?? '').trim().slice(0, 40),
      icon: String(r?.icon ?? 'chat').trim().replace(/[^\w]/g, '').slice(0, 16) || 'chat',
    }))
    .filter(r => r.id && r.name && !seen.has(r.id) && (seen.add(r.id), true))
  // قسم واحد على الأقل: دردشة بلا قسم لا يمكن استخدامها.
  s.chatRooms = rooms.length ? rooms.slice(0, 20)
    : [{ id: 'general', name: 'العامة', icon: 'chat' }]
  if (!['classic', 'bubble', 'dark', 'neon'].includes(s.chatTheme)) s.chatTheme = 'bubble'
  s.chatMaxLength = Math.max(80, Math.min(4000, Math.floor(Number(s.chatMaxLength) || 1000)))
  s.chatWelcome = String(s.chatWelcome ?? '').slice(0, 300)
  if (!['all', 'registered', 'subscribers'].includes(s.chatWriteScope)) s.chatWriteScope = 'registered'
  if (!['subscribers', 'none'].includes(s.chatMediaScope)) s.chatMediaScope = 'subscribers'
  s.chatMaxMediaMb = Math.max(1, Math.min(25, Math.floor(Number(s.chatMaxMediaMb) || 12)))
  s.chatMediaSeconds = Math.max(5, Math.min(300, Math.floor(Number(s.chatMediaSeconds) || 120)))
  // دور التحديث: أقل من ثانيتين يرهق الخادم، وأكثر من 30 يعني دردشة بطيئة.
  s.chatPollMs = Math.max(2000, Math.min(30000, Math.floor(Number(s.chatPollMs) || 4000)))
  return s
}

async function logSecurity(env: Env, request: Request, reason: string, detail = ''): Promise<void> {
  try {
    await env.XDB.prepare(
      'INSERT INTO x_security (device_id, ip, path, reason, detail, at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)'
    ).bind(
      deviceOf(request) || null, ip(request), new URL(request.url).pathname,
      reason, detail.slice(0, 300), new Date().toISOString()
    ).run()
  } catch { /* السجل لا يُسقط الطلب */ }
}

// ============================== Security layer ==============================

/**
 * عدّ الإساءة. `severity` يفصل الخطأ البشري عن محاولات التجاوز:
 * كلمة مرور خاطئة متكررة تعني مستخدماً نسِي كلمته، لا مهاجماً — وكانت
 * 15 محاولة كافية لحظر جهازه نهائياً. الخطر الحقيقي (توقيع مزوّر) وحده
 * يستحق الحظر التلقائي.
 */
async function noteAbuse(env: Env, request: Request, reason: string, severity: 'low' | 'high' = 'high'): Promise<void> {
  const addr = ip(request)
  if (severity === 'low') return
  try {
    // عدّاد إساءة للجهاز أيضاً — تغيير IP/البروكسي لا يحمي المتلاعب
    const dev = deviceOf(request)
    if (dev) {
      const dk = `abusedev:${dev}`
      const dc = Number(await env.QUOTA.get(dk)) || 0
      await env.QUOTA.put(dk, String(dc + 1), { expirationTtl: 3600 })
      if (dc + 1 >= 15) {
        await banDevice(env, dev, `auto:${reason}`, request)
      }
    }
    if (addr !== 'unknown') {
      const key = `abuse:${addr}`
      const count = Number(await env.QUOTA.get(key)) || 0
      await env.QUOTA.put(key, String(count + 1), { expirationTtl: 600 })
      // الحظر بعد 20 إساءة كان يضرب عناوين CGNAT المشتركة: جهاز واحد مسيء
      // يحجب جيرانه كلهم. صار التسجيل أولاً، والحظر عند 60 إساءة في نفس
      // النافذة القصيرة — رقم لا يبلغه مستخدم شرعي.
      if (count + 1 >= 60) {
        await env.QUOTA.put(`hardban:${addr}`, 'repeat', { expirationTtl: 3600 })
        await logSecurity(env, request, 'ip_hardban', `reason=${reason} strikes=${count + 1}`)
      }
    }
  } catch { /* ignore */ }
}

/** حظر جهاز نهائي — لا يفيده تغيير IP أو بروكسي أو حساب جديد */
/**
 * حظر IP دائم — يُستخدم مع حظر الجهاز: الأول يوقف المهاجم فوراً،
 * والثاني يمنعه حتى لو غيّر عنوانه.
 */
async function banIp(env: Env, addr: string, reason: string, request?: Request): Promise<void> {
  await env.QUOTA.put(`hardban:${addr}`, 'perm') // بلا انتهاء
  await env.XDB.prepare(
    `INSERT INTO x_bans (id, kind, reason, permanent, at) VALUES (?1, 'ip', ?2, 1, ?3)
     ON CONFLICT(id) DO UPDATE SET reason = ?2, at = ?3`
  ).bind(addr, reason.slice(0, 200), new Date().toISOString()).run()
  if (request) await logSecurity(env, request, 'ip_banned', reason)
}

async function banDevice(env: Env, deviceId: string, reason: string, request?: Request): Promise<void> {
  await env.QUOTA.put(`devban:${deviceId}`, 'perm') // بلا انتهاء
  await env.XDB.prepare(
    `INSERT INTO x_bans (id, kind, reason, permanent, at) VALUES (?1, 'device', ?2, 1, ?3)
     ON CONFLICT(id) DO NOTHING`
  ).bind(deviceId, reason, new Date().toISOString()).run()
  if (request) await logSecurity(env, request, 'device_banned', reason)
}

/**
 * قراءة من KV لا تُسقط الطلب عند تعطّل KV.
 *
 * كانت أي مشكلة مؤقتة في KV تُفشل كل طلب قبل وصوله للخادم، فيرى المستخدم
 * «تعذر الاتصال» وهو متصل. فقدان فحص الحظر لدقائق أهون من تعطيل التطبيق كله.
 */
async function kvGet(env: Env, key: string): Promise<string | null> {
  try {
    return await env.QUOTA.get(key)
  } catch {
    return null
  }
}

async function assertDeviceAllowed(env: Env, request: Request): Promise<void> {
  const dev = deviceOf(request)
  if (!dev) return
  if (await kvGet(env, `devban:${dev}`)) {
    if (await hasOwnerSession(env, request)) return
    await logSecurity(env, request, 'banned_device_hit')
    throw new HttpError(403, 'تم حظر هذا الجهاز نهائياً — تواصل مع الدعم')
  }
}

async function assertIpClean(env: Env, request: Request): Promise<void> {
  const addr = ip(request)
  if (await kvGet(env, `hardban:${addr}`)) {
    if (await hasOwnerSession(env, request)) return
    await logSecurity(env, request, 'banned_ip_hit')
    throw new HttpError(403, 'تم حظر هذا العنوان — تواصل مع الدعم')
  }
  if (Number(await kvGet(env, `abuse:${addr}`)) >= 20) {
    if (await hasOwnerSession(env, request)) return
    throw new HttpError(403, 'تم حظر هذا الطلب مؤقتاً')
  }
}

/**
 * هل يحمل الطلب جلسة مالك صالحة؟
 *
 * بدون هذا الاستثناء يبقى المالك خارج التطبيق نهائياً إذا حُظر جهازه أو
 * عنوانه (بنقرة خاطئة على زر الحظر، أو حظر تلقائي بسبب أخطاء اختبار):
 * لا يستطيع الوصول إلى صفحة إلغاء الحظر لأن فحص الحظر يسبق المصادقة.
 * الجلسة تُوقَّع بـ X_JWT_SECRET فلا يمكن تزويرها.
 */
async function hasOwnerSession(env: Env, request: Request): Promise<boolean> {
  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '').trim()
  if (!token) return false
  try {
    const payload = await verifyJwt(token, env.X_JWT_SECRET)
    return payload.role === 'owner'
  } catch {
    return false
  }
}

/**
 * حدّ المعدل مفتاحه الجهاز لا العنوان.
 *
 * مشغّلو الجوال يستخدمون CGNAT: آلاف المستخدمين بلا علاقة بينهم يظهرون
 * بالعنوان نفسه. حدّ لكل عنوان كان يعني أن آخر من يفتح التطبيق من ذلك
 * العنوان يُرفض بـ 429 في أول تشغيل، ويُعرض له «تعذر الاتصال». الحدّ لكل
 * جهاز يمنع الجهاز المسيء دون معاقبة جيرانه.
 *
 * العناوين بلا معرّف جهاز (أدوات آلية غالباً) تبقى على الحدّ بالعنوان.
 */
async function rateLimit(env: Env, request: Request, bucket: string, limit: number, window: number): Promise<void> {
  const dev = deviceOf(request)
  const key = dev ? `rl:${bucket}:d:${dev}` : `rl:${bucket}:${ip(request)}`
  const used = Number(await kvGet(env, key)) || 0
  if (used + 1 > limit) {
    // لا يُحتسب تجاوز الحدّ في رصيد الإساءة: مستخدم شرعي على عنوان مشترك
    // قد يبلغه بسهولة، واحتسابه كان يحوّله إلى حظر كامل بعد 20 مرة.
    await logSecurity(env, request, 'rate_limited', `bucket=${bucket} limit=${limit}/${window}s`)
    throw new HttpError(429, 'طلبات كثيرة جداً — تم الحظر مؤقتاً')
  }
  try {
    await env.QUOTA.put(key, String(used + 1), { expirationTtl: window })
  } catch {
    // تعذّر العدّ لا يمنع الطلب — الحدّ الحقيقي يُفرض عند الخصم من الرصيد.
  }
}

/** توقيع التطبيق: X-App-Sig = HMAC(X_SIG_SECRET, deviceId|ts|method|path) */
async function verifySignature(env: Env, request: Request): Promise<void> {
  if (!env.X_SIG_SECRET) return
  const sig = request.headers.get('x-app-sig')?.trim() ?? ''
  const ts = Number(request.headers.get('x-app-ts')?.trim() || '0')
  if (!sig || !ts) {
    await noteAbuse(env, request, 'missing_signature')
    await logSecurity(env, request, 'missing_signature')
    throw new HttpError(403, 'طلب غير موقّع')
  }
  if (Math.abs(Date.now() - ts) > 10 * 60 * 1000) {
    await noteAbuse(env, request, 'stale_signature')
    throw new HttpError(403, 'انتهت صلاحية التوقيع')
  }
  const url = new URL(request.url)
  // البصمة جزء من التوقيع حين تُرسل: بغير ذلك يكفي تبديل ترويسة البصمة
  // لأخذ منحة يومية جديدة بلا حد. وعند غيابها نقبل صيغة التوقيع القديمة،
  // فمعرّف الجهاز نفسه صار البصمة الدائمة في النسخ الجديدة.
  const fp = request.headers.get('x-device-fp')?.trim() ?? ''
  const legacy = `${deviceOf(request)}|${ts}|${request.method}|${url.pathname}${url.search}`
  const expected = await hmacHex(
    env.X_SIG_SECRET,
    fp ? `${deviceOf(request)}|${fp}|${ts}|${request.method}|${url.pathname}${url.search}` : legacy
  )
  if (sig !== expected) {
    await noteAbuse(env, request, 'bad_signature')
    await logSecurity(env, request, 'bad_signature', `ts=${ts}`)
    throw new HttpError(403, 'توقيع غير صالح')
  }
}

/**
 * كشف مزرعة الأجهزة: عدة أجهزة تتشارك عنواناً واحداً.
 *
 * العتبة كانت 30 جهازاً في اليوم، وهي منخفضة جداً لأن مشغّلي الجوال
 * يستخدمون CGNAT: عشرات المستخدمين الحقيقيين يظهرون بالعنوان نفسه خلال
 * ساعات، فيُحظر العنوان كله ويمنع من لم يذنب. صار الكشف يسجّل للمالك أولاً،
 * ولا يحظر إلا بعد تكرار التجاوز في نوافذ متعددة — أي سلوك ثابت لا صدفة
 * ازدحام عابرة.
 */
async function trackDeviceFarm(env: Env, request: Request): Promise<void> {
  const dev = deviceOf(request)
  const addr = ip(request)
  if (!dev || addr === 'unknown') return
  const key = `devs:${addr}`
  const list = ((await env.QUOTA.get(key, 'json')) as string[] | null) ?? []
  if (list.includes(dev)) return
  list.push(dev)
  if (list.length > 400) {
    const strikes = Number(await env.QUOTA.get(`farmstrikes:${addr}`)) || 0
    await env.QUOTA.put(`farmstrikes:${addr}`, String(strikes + 1), { expirationTtl: 7 * DAY })
    await logSecurity(env, request, 'device_farm', `devices=${list.length} strikes=${strikes + 1}`)
    if (strikes + 1 >= 3) {
      await env.QUOTA.put(`hardban:${addr}`, 'device-farm', { expirationTtl: DAY })
      throw new HttpError(403, 'تم حظر هذا العنوان — تواصل مع الدعم')
    }
  }
  await env.QUOTA.put(key, JSON.stringify(list.slice(-500)), { expirationTtl: DAY })
}

/** ربط الحساب بجهاز واحد — أي جهاز آخر يُرفض ويُسجَّل */
async function assertDeviceBound(env: Env, request: Request, user: XUser): Promise<void> {
  const dev = deviceOf(request)
  if (!dev) return
  if (user.role === 'owner') return
  if (!user.device_id) {
    await env.XDB.prepare('UPDATE x_users SET device_id = ?1 WHERE id = ?2').bind(dev, user.id).run()
    return
  }
  if (user.device_id !== dev) {
    await logSecurity(env, request, 'device_mismatch', `bound=${user.device_id} got=${dev} user=${user.username}`)
    throw new HttpError(403, 'هذا الحساب مرتبط بجهاز آخر — تواصل مع المالك')
  }
}

async function authenticate(env: Env, request: Request): Promise<{ caller: Caller; user: XUser | null }> {
  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '').trim()
  if (!token) throw new HttpError(401, 'missing token')

  // جلسة المالك تُجرَّب أولاً بسرّها المستقل. رمز بتوقيع صحيح لكن بلا
  // typ=owner لا يُقبل هنا، فلا يمكن تحويل جلسة عادية إلى جلسة مالك.
  const asOwner = await tryOwnerToken(env, token)
  if (asOwner) {
    const owner = await xUser(env.XDB, String(asOwner.sub))
    if (!owner || owner.role !== 'owner' || !owner.active) {
      throw new HttpError(401, 'invalid token')
    }
    return { caller: { uid: owner.id, role: 'owner' }, user: owner }
  }

  const payload = await verifyJwt(token, env.X_JWT_SECRET)
  const sub = typeof payload.sub === 'string' ? payload.sub : ''
  if (!sub) throw new HttpError(401, 'invalid token')
  const role = typeof payload.role === 'string' ? payload.role : 'guest'

  if (role === 'guest') {
    // الزائر: جلسة مرتبطة بالجهاز فقط — بلا صف في x_users
    if (deviceOf(request) && payload.dev !== deviceOf(request)) {
      await logSecurity(env, request, 'guest_token_device_mismatch')
      throw new HttpError(401, 'invalid token')
    }
    return { caller: { uid: sub, role }, user: null }
  }

  const user = await xUser(env.XDB, sub)
  if (!user) throw new HttpError(401, 'invalid token')
  if (!user.active) throw new HttpError(403, 'الحساب بانتظار تفعيل المالك')
  if (user.expires_at > 0 && Date.now() >= user.expires_at) {
    throw new HttpError(403, 'انتهى اشتراكك — تواصل مع المالك')
  }
  await assertDeviceBound(env, request, user)
  return { caller: { uid: user.id, role: user.role }, user }
}

/** بوابة الإصدارات — تُعيد استجابة 426 غنية (رسالة+صورة+زر) أو null إن مسموح */
function versionGate(request: Request, settings: XSettings): Response | null {
  const v = versionOf(request)
  if (v <= 0) return null
  if (v < settings.minVersion || settings.blockedVersions.includes(v)) {
    return json({
      ok: false,
      error: 'إصدار التطبيق غير مدعوم — حدّث التطبيق',
      status: 426,
      update: {
        required: true,
        message: settings.updateMessage,
        url: settings.updateUrl,
        imageUrl: settings.updateImageUrl
      }
    }, 426)
  }
  return null
}

/**
 * بصمة الجهاز الدائمة — أساس المنحة اليومية.
 *
 * معرّف الجهاز كان يُولَّد داخل التطبيق ويُخزَّن مع بياناته، فمسح البيانات
 * يمحوه ويعود المستخدم بمنحة جديدة. البصمة تأتي من النظام (ANDROID_ID)
 * وتُخزَّن في التخزين الأصلي، فتبقى بعد مسح البيانات وبعد تبديل الحساب.
 *
 * ولا تُقبل من العميل بلا تحقق: التوقيع يشملها (انظر verifySignature)، فتبديلها
 * في الطلب يكسر التوقيع. وهي داخل خادم واحد لكل الأدوار، فيتشارك الزائر
 * والمشترك والمسجّل المنحة نفسها على الجهاز نفسه.
 */
function fingerprint(request: Request): string {
  const fp = request.headers.get('x-device-fp')?.trim() ?? ''
  if (/^[0-9a-f]{16,64}$/i.test(fp)) return `fp:${fp.toLowerCase()}`
  // نسخ قديمة لا ترسل بصمة: معرّف الجهاز أفضل من لا شيء، ثم العنوان كحل أخير.
  const dev = deviceOf(request)
  return dev ? `dev:${dev}` : `ip:${ip(request)}`
}

/**
 * مفتاح محفظة الزائر: بصمة الجهاز مع ترحيل المحفظة القديمة.
 *
 * كانت المحافظ مفتاحها معرّف الجهاز المخزَّن في بيانات التطبيق، فمسحها يفقد
 * الرصيد. البصمة أدوم، فننقل الرصيد عند أول ظهور لها بدل إضاعته.
 */
async function walletKey(env: Env, fp: string, dev: string): Promise<string> {
  if (!fp.startsWith('fp:') || !dev) return fp
  const mine = await env.XDB.prepare(
    'SELECT 1 AS x FROM x_guest_wallets WHERE device_id = ?1'
  ).bind(fp).first()
  if (mine) return fp
  await env.XDB.prepare(
    `INSERT OR IGNORE INTO x_guest_wallets (device_id, balance, expires_at, created_at, updated_at)
     SELECT ?1, balance, expires_at, created_at, updated_at FROM x_guest_wallets WHERE device_id = ?2`
  ).bind(fp, dev).run()
  return fp
}

/** مفتاح الهوية لهذا الطلب — يُحسب مرة ويُمرَّر لكل عمليات الخصم والعرض. */
async function walletOf(env: Env, request: Request): Promise<string> {
  return walletKey(env, fingerprint(request), deviceOf(request))
}

/**
 * خصم من عملات الهوية: حساب المسجّل من x_users، ومحفظة الزائر من جدولها.
 * يُعيد الرصيد بعد الخصم، أو null إذا لم يكفِ الرصيد.
 */
async function spendCoins(
  env: Env, caller: Caller, fp: string, cost: number
): Promise<number | null> {
  const now = Date.now()
  if (caller.role === 'user') {
    const row = await env.XDB.prepare(
      `UPDATE x_users SET quota_balance = quota_balance - ?3
       WHERE id = ?1 AND quota_balance >= ?3
         AND (quota_expires_at = 0 OR quota_expires_at > ?2)
       RETURNING quota_balance`
    ).bind(caller.uid, now, cost).first<{ quota_balance: number }>()
    return row ? row.quota_balance : null
  }
  const w = await env.XDB.prepare(
    `UPDATE x_guest_wallets SET balance = balance - ?3
     WHERE device_id = ?1 AND balance >= ?3
       AND (expires_at = 0 OR expires_at > ?2)
     RETURNING balance`
  ).bind(fp, now, cost).first<{ balance: number }>()
  return w ? w.balance : null
}

/** سبب نفاد الرصيد: رسالة دقيقة تفرّق بين انتهاء الصلاحية ونفاده. */
async function emptyReason(env: Env, caller: Caller, fp: string): Promise<HttpError> {
  const now = Date.now()
  if (caller.role === 'user') {
    const u = await xUser(env.XDB, caller.uid)
    if (u && u.quota_expires_at > 0 && u.quota_expires_at <= now) {
      return new HttpError(402, 'انتهت صلاحية عملاتك — جدّد باقتك عبر التواصل مع المالك')
    }
    return new HttpError(402, 'انتهت حصتك المجانية ولا توجد عملات — اشترِ باقة من المالك')
  }
  const wallet = await env.XDB.prepare(
    'SELECT balance, expires_at FROM x_guest_wallets WHERE device_id = ?1'
  ).bind(fp).first<{ balance: number; expires_at: number }>()
  if (wallet && wallet.expires_at > 0 && wallet.expires_at <= now) {
    return new HttpError(402, 'انتهت صلاحية عملاتك — تواصل مع المالك للتجديد')
  }
  return new HttpError(402,
    'انتهت حصتك المجانية ولا توجد عملات — تواصل مع المالك لإنشاء حساب أو شحن رصيد')
}

/**
 * خصم موحّد: المنحة اليومية أولاً ثم العملات.
 *
 * الترتيب واحد لفتح المخططات ودخول شركة في التوافقات: العدّاد واحد والعملات
 * واحدة، فلا يفاجأ المستخدم بأن رصيده في الشريط لا يطابق ما يُخصم فعلاً.
 */
async function chargeOne(
  env: Env, caller: Caller, fp: string, settings: XSettings
): Promise<{ freeLeft: number; balance: number; source: string }> {
  if (caller.role === 'owner') return { freeLeft: -1, balance: -1, source: 'owner' }

  const freeLeft = await takeDailyFree(env.XDB, fp, settings.dailyFreeQuota)
  if (freeLeft >= 0) return { freeLeft, balance: -1, source: 'free' }

  const cost = Math.max(1, Math.floor(Number(settings.compatSearchCost) || 1))
  const balance = await spendCoins(env, caller, fp, cost)
  if (balance === null) throw await emptyReason(env, caller, fp)
  return { freeLeft: 0, balance, source: 'coins' }
}

/**
 * فتح ملف مخطط مع إعفاء إعادة الفتح.
 *
 * يُخصم مرة واحدة لكل (جهاز + ملف + يوم). إعادة فتح نفس المخطط — وهو سلوك
 * طبيعي جداً في الاستعمال — كانت تُخصم في كل مرة وتستنزف المنحة على ملف
 * واحد. المفاتيح في KV بصلاحية يومين كي لا تتراكم.
 */
async function consumeFileOnce(
  env: Env, ctx: ExecutionContext, caller: Caller, settings: XSettings,
  fp: string, fileKey: string
): Promise<number> {
  const digest = await hmacHex(settings.telegramLink || 'x-file', `${fp}|${fileKey}|${today()}`)
  const seenKey = `fo:${fp}:${digest.slice(0, 32)}`
  const cached = await kvGet(env, seenKey)
  if (cached) return Number(cached)

  const r = await chargeOne(env, caller, fp, settings)
  const left = r.source === 'free' ? r.freeLeft : r.balance
  ctx.waitUntil(env.QUOTA.put(seenKey, String(left), { expirationTtl: 2 * DAY })
    .catch(() => {}))
  return left
}

// ============================== Mirror reads (READ-ONLY) ==============================

interface MirrorDoc { id: string; fields: Record<string, any> }

function mrows(result: D1Result<{ id: string; data: string }>): MirrorDoc[] {
  return (result.results ?? []).map(r => ({ id: r.id, fields: JSON.parse(r.data) }))
}

async function mirrorCollection(db: D1Database, collection: string): Promise<MirrorDoc[]> {
  return mrows(await db.prepare(
    'SELECT id, data FROM docs WHERE collection = ?1 ORDER BY sort_order IS NULL, sort_order, id'
  ).bind(collection).all<{ id: string; data: string }>())
}

async function mirrorSearchCompat(
  db: D1Database, opts: { query: string; brandFile?: string; type?: string; keyword?: string; limit: number }
): Promise<MirrorDoc[]> {
  const clauses = ["collection = 'compatibility'"]
  const binds: (string | number)[] = []
  if (opts.brandFile) { binds.push(opts.brandFile); clauses.push(`brand_file = ?${binds.length}`) }
  if (opts.type) { binds.push(opts.type); clauses.push(`component_type = ?${binds.length}`) }
  if (opts.keyword) { binds.push(`%${opts.keyword.toLowerCase()}%`); clauses.push(`LOWER(data) LIKE ?${binds.length}`) }
  // كل كلمة شرط مستقل (AND): بحث «iphone 11» كان يرجع صفراً لأن المطابقة
  // كانت على النص كاملاً. سقف 4 كلمات يحدّ كلفة الاستعلام.
  const tokens = opts.query.toLowerCase().split(/\s+/).filter(Boolean).slice(0, 4)
  for (const t of tokens) {
    binds.push(`%${t}%`)
    clauses.push(`LOWER(data) LIKE ?${binds.length}`)
  }
  // نجلب أكثر من الحدّ ثم نرتّب بالأهمية: الاستعلام بلا ORDER BY كان يُرجع
  // الصفوف بترتيب تخزين اعتباطي، فيظهر السجل المطابق تماماً بعد صفّين.
  const fetchLimit = Math.min(opts.limit * 3, 360)
  binds.push(fetchLimit)
  const rows = mrows(await db.prepare(
    `SELECT id, data FROM docs WHERE ${clauses.join(' AND ')}
     ORDER BY sort_order IS NULL, sort_order, id LIMIT ?${binds.length}`
  ).bind(...binds).all<{ id: string; data: string }>())

  // الترتيب النهائي في JS: أسماء الحقول في `data` JSON غير موثّقة في القاعدة،
  // فالاعتماد على json_extract لأسماء مخمّنة هشّ. هنا نقرأ الحقول المحلّلة.
  const q = opts.query.toLowerCase().trim()
  const scored = rows.map(d => ({ d, s: relevanceScore(d.fields, tokens, q) }))
  scored.sort((a, b) => b.s - a.s || a.d.id.localeCompare(b.d.id))
  return scored.slice(0, opts.limit).map(x => x.d)
}

/**
 * درجة ملاءمة سجل لعبارة البحث — الأعلى أولاً.
 *
 * بنية سجل التوافقات: `compatibleModels` قائمة موديلات، و`subCategory` كائن
 * فيه `name`، و`componentType` نوع القطعة. المطابقة في موديل بعينه أقوى دليل
 * من مطابقة عابرة في نص الحقل كله. بلا هذا الترتيب يظهر سجل هامشي قبل السجل
 * الذي يبحث عنه المستخدم حرفياً.
 */
function relevanceScore(fields: Record<string, unknown>, tokens: string[], q: string): number {
  const models = Array.isArray(fields.compatibleModels)
    ? (fields.compatibleModels as unknown[]).map(m => String(m).toLowerCase())
    : [];
  const sub = (fields.subCategory && typeof fields.subCategory === 'object')
    ? String((fields.subCategory as Record<string, unknown>).name ?? '').toLowerCase()
    : String(fields.subCategory ?? '').toLowerCase();
  const hay = JSON.stringify(fields).toLowerCase()

  // الترتيب يُبنى على أفضل موديل في السجل لا على مجموع كل الموديلات:
  // سجل فيه عشرة موديلات كلها مطابقة جزئية كان يسبق سجلاً فيه الموديل
  // المطلوب حرفياً. المهم أن يوجد موديل واحد مطابق تماماً.
  let best = 0
  for (const m of models) {
    const cm = m.replace(/[\s-]+/g, '')
    const cq = q.replace(/[\s-]+/g, '')
    let s = 0
    if (cq && cm === cq) s = 100
    else if (cq && cm.startsWith(cq)) s = 80
    // اسم الموديل يُكتب في البيانات مسبوقاً بالشركة («xiaomi redmi note 11»)،
    // فمطابقة الذيل تطابق الاسم الذي كتبه المستخدم.
    else if (cq && cm.endsWith(cq)) s = 70
    else if (cq && cq.length >= 3 && cm.includes(cq)) s = 60
    else s = tokens.reduce((acc, t) =>
      acc + (m === t ? 50 : m.startsWith(t) ? 30 : m.includes(t) ? 18 : 0), 0)
    if (s > best) best = s
  }

  // كسر التعادل: مطابقة النوع الفرعي، ثم أي مطابقة في السجل كله.
  let tie = tokens.reduce((acc, t) => acc + (sub.includes(t) ? 4 : 0), 0)
  for (const t of tokens) if (hay.includes(t)) tie += 1
  return best * 1000 + tie
}

/** الأنواع المتوفرة لشركة — استعلام تجميعي واحد، مخزّن مؤقتاً. */
async function compatTypesOf(db: D1Database, brandFile: string): Promise<string[]> {
  const rows = await db.prepare(
    `SELECT component_type t, COUNT(*) c FROM docs
     WHERE collection = 'compatibility' AND brand_file = ?1
     GROUP BY component_type ORDER BY c DESC`
  ).bind(brandFile).all<{ t: string; c: number }>()
  return (rows.results ?? []).map(r => r.t).filter(Boolean)
}

/** كل ملفات الشركات المتوفرة في المرآة — لتصفية سجل التثبيتات حسب النشاط. */
async function compatBrandFiles(db: D1Database): Promise<string[]> {
  const rows = await db.prepare(
    "SELECT DISTINCT brand_file f FROM docs WHERE collection = 'compatibility'"
  ).all<{ f: string }>()
  return (rows.results ?? []).map(r => r.f).filter(Boolean)
}

// ---------- تحصيل التوافقات ----------

// الثمن والمنحة صارا في chargeOne: عدّاد واحد وعملة واحدة للمخططات والتوافقات.

/**
 * حصة مجانية ذرّية في D1.
 *
 * عدّاد KV لا يصلح للحصص: القراءة ثم الكتابة عمليتان منفصلتان، فطلبان
 * متقاربان يقرآن نفس القيمة فيُمنحان بحثاً زائداً. هنا الزيادة والشرط داخل
 * UPDATE واحد، فلا سباق ولا تجاوز حتى مع الطلبات المتزامنة.
 *
 * يُعيد ما تبقّى، أو -1 إذا نفدت الحصة (أو كانت صفراً).
 */
async function takeDailyFree(
  db: D1Database, fp: string, limit: number
): Promise<number> {
  if (!(limit > 0)) return -1
  const row = await db.prepare(
    `INSERT INTO x_quota_daily (uid, day, kind, used) VALUES (?1, ?2, 'all', 1)
     ON CONFLICT(uid, day, kind) DO UPDATE SET used = used + 1 WHERE used < ?3
     RETURNING used`
  ).bind(fp, today(), limit).first<{ used: number }>()
  // لا صف يعني أن الشرط لم يتحقق: الحصة مستنفدة فعلاً.
  return row ? Math.max(0, limit - row.used) : -1
}

/** ما استُهلك اليوم من المنحة — للعرض في /v1/me. */
async function dailyFreeUsed(db: D1Database, fp: string): Promise<number> {
  const row = await db.prepare(
    "SELECT used FROM x_quota_daily WHERE uid = ?1 AND day = ?2 AND kind = 'all'"
  ).bind(fp, today()).first<{ used: number }>()
  return row?.used ?? 0
}

/**
 * فتح شركة في التوافقات — نقطة الخصم الوحيدة.
 *
 * الخصم مرتبط بـ(الجهاز + الشركة + اليوم)، لا بنص البحث: المستخدم كان
 * يُحاسَب مع كل حرف يكتبه ويُحاسَب مرة أخرى عند كل تصفية، فيُستنزف قبل أن
 * يرى نتيجة. الآن يدفع مرة واحدة عند دخول الشركة، ويتنقّل بين الأنواع
 * والنصوص والنتائج بلا خصم. الخروج من الشركة والعودة لا يُعيد الخصم في
 * اليوم نفسه، فيبقى الاستعمال الطبيعي بلا مفاجآت.
 *
 * وهو أيضاً ما يمنع سحب التوافقات آلياً: كل شركة تُكلّف مرة، فسحب الكتالوغ
 * كاملاً يتطلب دفع ثمن كل شركة — بخلاف الخصم على النص الذي كان يمكن
 * تجاوزه باستعلام واحد واسع.
 */
async function ensureCompatOpen(
  env: Env, ctx: ExecutionContext, caller: Caller, settings: XSettings,
  fp: string, brandRef: string
): Promise<{ freeLeft: number; balance: number; charged: boolean; source: string }> {
  if (caller.role === 'owner') {
    return { freeLeft: -1, balance: -1, charged: false, source: 'owner' }
  }

  const digest = await hmacHex(settings.telegramLink || 'x-compat', `${fp}|${brandRef}|${today()}`)
  const seenKey = `co:${fp}:${digest.slice(0, 32)}`
  const cached = await kvGet(env, seenKey)
  if (cached) {
    const c = JSON.parse(cached) as { freeLeft: number; balance: number; source: string }
    return { freeLeft: c.freeLeft, balance: c.balance, charged: false, source: c.source }
  }

  const r = await chargeOne(env, caller, fp, settings)
  const snap = { freeLeft: r.freeLeft, balance: r.balance, source: r.source }
  ctx.waitUntil(env.QUOTA.put(seenKey, JSON.stringify(snap), { expirationTtl: 2 * DAY })
    .catch(() => {}))
  return { ...snap, charged: true }
}

/**
 * أحداث تستحق انتباه المالك: محاولات تجاوز الحماية والاستنزاف.
 * تُستثنى الأحداث الروتينية (تسجيل دخول خاطئ، جهاز مختلف) لأنها لا تعني هجوماً
 * وتُغرق السجل فيصعب رؤية المهم.
 */
const ATTACK_REASONS = [
  'missing_signature', 'bad_signature', 'stale_signature', 'ip_hardban',
  'device_farm', 'device_mismatch', 'banned_device_hit', 'banned_ip_hit',
  'device_banned', 'ip_banned', 'non_owner_admin_attempt',
  'guest_token_device_mismatch', 'rate_limited',
  'bad_owner_key', 'scraping_suspected'
]

/**
 * الأحداث المشبوهة وحدها — ما يستحق نظر المالك.
 *
 * تبويب الأمان كان يعرض كل سطر في السجل: كلمة مرور منسيّة، تجاوز حدّ سرعة،
 * جهاز بدّل مستخدمه. الغرق في الضجيج يخفي الهجوم الحقيقي. هذه القائمة
 * تستبعد الخطأ البشري وتُبقي محاولات التجاوز والتزوير والعبث:
 *  - توقيع مفقود/مزوّر/قديم: طلب لا يأتي من التطبيق أصلاً.
 *  - device_farm: عنوان واحد بيفتح أجهزة كثيرة (تلاعب بالمنحة).
 *  - banned_*: محظور يعاود المحاولة بعد الحظر.
 *  - non_owner_admin_attempt: محاولة فتح لوحة المالك بلا صلاحية.
 *  - scraping_suspected: سحب بيانات آلي.
 */
const SUSPICIOUS_REASONS = [
  'missing_signature', 'bad_signature', 'stale_signature',
  'device_farm', 'banned_device_hit', 'banned_ip_hit',
  'device_banned', 'ip_banned', 'non_owner_admin_attempt',
  'guest_token_device_mismatch', 'bad_owner_key', 'scraping_suspected'
]


const COMPAT_TYPES = ['SCREEN', 'BATTERY', 'GLASS', 'INCASSABLE']

/** شركات فرعية افتراضية — تُشتق قراءةً فقط من ملفات الشركات الأم، بلا أي كتابة على المصدر */
const VIRTUAL_SUB_BRANDS: { name: string; file: string; key: string }[] = [
  { name: 'redmi', file: '01xiaomi.json', key: 'redmi' },
  { name: 'poco', file: '01xiaomi.json', key: 'poco' },
  { name: 'oppo', file: '02realme.json', key: 'oppo' },
  { name: 'honor', file: '03huawei.json', key: 'honor' },
  { name: 'iqoo', file: '14vivo.json', key: 'iqoo' },
]

// ============================== Schematics catalog (READ-ONLY) ==============================

interface CatalogBrand { id: string; name: string }
interface CatalogModel { name: string; folders: { category: string; id: string }[] }
interface CatalogEntry { id: string; name: string; mimeType: string; size?: string | number }

async function cached<T>(env: Env, key: string, ttl: number, build: () => Promise<T>): Promise<T> {
  const hit = await env.QUOTA.get(key, 'json')
  if (hit) return hit as T
  const value = await build()
  await env.QUOTA.put(key, JSON.stringify(value), { expirationTtl: ttl })
  return value
}

async function readCatalogBrands(env: Env): Promise<CatalogBrand[]> {
  const obj = await env.SCHEMATICS.get(ROOT_CATALOG)
  if (!obj) return []
  const raw = await obj.json() as { id: string; name: string }[]
  return (Array.isArray(raw) ? raw : []).filter(b => typeof b?.id === 'string' && typeof b?.name === 'string')
}

async function readBrandCatalog(env: Env, brandId: string): Promise<{ models: CatalogModel[]; folders: Record<string, CatalogEntry[]> } | null> {
  const name = brandId.startsWith('r2:') ? brandId.slice(3) : brandId
  const obj = await env.SCHEMATICS.get(`catalog/v1/brands/${encodeURIComponent(name)}.json`)
  if (!obj) return null
  const data = await obj.json() as any
  return { models: data?.models ?? [], folders: data?.folders ?? {} }
}

/** شركات local/ (مثل Xiaomi/REDMI) — نفس منطق العامل الأصلي */
async function listLocalBrands(env: Env): Promise<CatalogBrand[]> {
  return cached(env, 'x_local_brands', 3600, async () => {
    const brands = new Map<string, CatalogBrand>()
    let cursor: string | undefined
    do {
      const page = await env.SCHEMATICS.list({ prefix: LOCAL_R2, limit: 1000, cursor, delimiter: '/' })
      for (const p of page.delimitedPrefixes ?? []) {
        let sub: string | undefined
        do {
          const sp = await env.SCHEMATICS.list({ prefix: p, limit: 1000, cursor: sub, delimiter: '/' })
          for (const s of sp.delimitedPrefixes ?? []) {
            const name = s.slice(p.length).replace(/\/$/, '')
            if (name && !brands.has(name)) {
              brands.set(name, { name, id: LOCAL_PREFIX + s.slice(LOCAL_R2.length).replace(/\/$/, '') })
            }
          }
          sub = sp.truncated ? sp.cursor : undefined
        } while (sub)
      }
      cursor = page.truncated ? page.cursor : undefined
    } while (cursor)
    return [...brands.values()].sort((a, b) => a.name.localeCompare(b.name))
  })
}

async function listLocalModels(env: Env, brandId: string): Promise<CatalogModel[]> {
  const prefix = LOCAL_R2 + brandId.slice(LOCAL_PREFIX.length) + '/'
  return cached(env, `x_lm:${brandId}`, 3600, async () => {
    const models = new Map<string, CatalogModel>()
    let cursor: string | undefined
    do {
      const page = await env.SCHEMATICS.list({ prefix, limit: 1000, cursor, delimiter: '/' })
      for (const p of page.delimitedPrefixes ?? []) {
        const name = p.slice(prefix.length).replace(/\/$/, '')
        if (name) models.set(name, { name, folders: [{ category: 'Hardware', id: LOCAL_PREFIX + p.slice(LOCAL_R2.length).replace(/\/$/, '') }] })
      }
      cursor = page.truncated ? page.cursor : undefined
    } while (cursor)
    return [...models.values()].sort((a, b) => a.name.localeCompare(b.name))
  })
}

// ============================== تشفير الملفات ==============================
// كل ملف يُقدَّم مشفراً بـ AES-CTR — البايتات المسروقة عديمة الفائدة
// بدون مفتاح التطبيق. nonce ثابت مشتق من etag حتى تبقى نسخة الكاش صالحة.

let _fileKey: Promise<CryptoKey> | null = null

function fileCryptoKey(env: Env): Promise<CryptoKey> {
  _fileKey ??= (async () => {
    const raw = new Uint8Array(32)
    for (let i = 0; i < 32; i++) raw[i] = parseInt(env.X_FILE_KEY.slice(i * 2, i * 2 + 2), 16)
    return crypto.subtle.importKey('raw', raw, { name: 'AES-CTR' }, false, ['encrypt'])
  })()
  return _fileKey
}

async function fileNonce(env: Env, r2Key: string, etag: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest(
    'SHA-256', new TextEncoder().encode(`${r2Key}|${etag}|${env.X_FILE_KEY}`))
  const nonce = new Uint8Array(digest).slice(0, 16)
  // آخر 8 بايتات صفر — العداد يبدأ من هنا حتى يتطابق مع تنفيذ Dart (عداد 128-بت)
  nonce.fill(0, 8)
  return nonce
}

const EXT_MIME: Record<string, string> = {
  pdf: 'application/pdf', svg: 'image/svg+xml', png: 'image/png',
  jpg: 'image/jpeg', jpeg: 'image/jpeg', gif: 'image/gif', webp: 'image/webp'
}

async function listLocalFiles(env: Env, folderId: string): Promise<CatalogEntry[]> {
  const prefix = LOCAL_R2 + folderId.slice(LOCAL_PREFIX.length) + '/'
  return cached(env, `x_lf:${folderId}`, 3600, async () => {
    const entries: CatalogEntry[] = []
    let cursor: string | undefined
    do {
      const page = await env.SCHEMATICS.list({ prefix, limit: 1000, cursor, delimiter: '/' })
      for (const p of page.delimitedPrefixes ?? []) {
        const name = p.slice(prefix.length).replace(/\/$/, '')
        if (name) entries.push({ name: `${name} /`, id: LOCAL_PREFIX + p.slice(LOCAL_R2.length).replace(/\/$/, ''), mimeType: FOLDER_MIME })
      }
      for (const o of page.objects ?? []) {
        const name = o.key.slice(prefix.length).replace(/%2F/gi, '/')
        if (name) entries.push({ name, id: LOCAL_PREFIX + o.key.slice(LOCAL_R2.length), mimeType: EXT_MIME[name.split('.').pop()?.toLowerCase() ?? ''] ?? 'application/octet-stream', size: String(o.size) })
      }
      cursor = page.truncated ? page.cursor : undefined
    } while (cursor)
    return entries
  })
}

// ============================== Announcements ==============================

async function announcements(env: Env): Promise<unknown[]> {
  // إعلانات تطبيق X وحدها — لا تُدمج إعلانات أي تطبيق آخر.
  // الدمج السابق مع مرآة phonex كان يعرض إعلانات تطبيق آخر داخل X، ويجعل
  // تغيير إعلاناته يظهر هنا بلا علم المالك. الآن كل تطبيق مستقل بإعلاناته.
  const rows = await env.XDB
    .prepare('SELECT id, data FROM x_announcements ORDER BY id DESC LIMIT 100')
    .all<{ id: string; data: string }>()
  return (rows.results ?? [])
    .map(r => ({ id: r.id, ...JSON.parse(r.data) }))
    .filter((a: any) => a.active === true)
    .sort((a: any, b: any) => (b.order ?? 0) - (a.order ?? 0))
}

/**
 * حدّ محاولات دخول المالك — مفتاحه الحساب لا الجهاز.
 *
 * حدّ الجهاز وحده لا يكفي: مهاجم يبدّل الأجهزة والعناوين يجرّب بلا حد.
 * العدّاد على `owner` عالمي، فسقفه يحمي الحساب من أي مصدر كان.
 */
const OWNER_LOCK_BUCKET = 'ownerlogin'

async function ownerLoginGuard(env: Env): Promise<void> {
  const used = Number(await kvGet(env, `rl:${OWNER_LOCK_BUCKET}`)) || 0
  if (used >= 8) {
    throw new HttpError(429, 'تم إيقاف محاولات الدخول مؤقتاً — حاول بعد 15 دقيقة')
  }
}

async function noteOwnerLoginFail(env: Env, request: Request): Promise<void> {
  const key = `rl:${OWNER_LOCK_BUCKET}`
  const used = Number(await kvGet(env, key)) || 0
  await env.QUOTA.put(key, String(used + 1), { expirationTtl: 900 })
  await logSecurity(env, request, 'bad_owner_login', `attempt=${used + 1}`)
}

async function clearOwnerLoginFails(env: Env): Promise<void> {
  try { await env.QUOTA.delete(`rl:${OWNER_LOCK_BUCKET}`) } catch { /* لا يمنع الدخول */ }
}

/**
 * جلسة المالك — منفصلة عن جلسات المستخدمين بسرّ مستقل و`typ` مميز.
 *
 * الفصل يمنع أخطر سيناريو: تزوير جلسة عادية بحقل `role=owner`. جلسات
 * المستخدمين تُوقّع بـ X_JWT_SECRET، وجلسات المالك بـ X_OWNER_JWT_SECRET
 * (يسقط للسرّ العام إن لم يُضبط، فتبقى النسخة تعمل). أي رمز لا يحمل
 * `typ=owner` مرفوض حتى لو صحّ توقيعه.
 */
function ownerSecret(env: Env): string {
  return env.X_OWNER_JWT_SECRET || env.X_JWT_SECRET
}

async function signOwnerJwt(env: Env, payload: Record<string, unknown>, ttl: number): Promise<string> {
  return signJwt({ ...payload, typ: 'owner' }, ownerSecret(env), ttl)
}

async function verifyOwnerJwt(env: Env, token: string): Promise<Record<string, any>> {
  const payload = await verifyJwt(token, ownerSecret(env))
  if (payload.typ !== 'owner' || payload.role !== 'owner') {
    throw new HttpError(401, 'invalid token')
  }
  return payload
}

/** يُرجع الحمولة إن كان الرمز جلسة مالك صالحة، وإلا null بلا رمي خطأ. */
async function tryOwnerToken(env: Env, token: string): Promise<Record<string, any> | null> {
  try {
    return await verifyOwnerJwt(env, token)
  } catch {
    return null
  }
}

// ============================== Chat ==============================

/**
 * الدردشة: مجموعة مجتمعية واحدة بأقسام — لا رسائل خاصة بين الأفراد.
 *
 * لماذا لا خاص؟ الخاص يحتاج تشفيراً طرفياً وإدارة مفاتيح، ووعداً أمنياً لا
 * يستطيع خادم واحد تحقيقه. الاختيار الصريح: كل رسالة علنية داخل قسم، وهذا
 * ما يمكن حمايته فعلاً (تصفية، كتم، طرد، سجل).
 */
const CHAT_KINDS = ['text', 'image', 'audio', 'video', 'system'] as const
type ChatKind = typeof CHAT_KINDS[number]

/** أنواع الوسائط التي يُقبل رفعها، والتحقق من بايتها السحرية لا من ادّعاء العميل. */
/** نوع وسيط مكتشَف. `test` غائب في نتائج التفريع الداخلي (عائلة MP4). */
interface MediaSig {
  kind: 'image' | 'audio' | 'video'
  ext: string
  mime: string
  test?: (b: Uint8Array) => boolean
}

const MEDIA_SIGNATURES: MediaSig[] = [
  { kind: 'image', ext: 'png', mime: 'image/png', test: b => b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 },
  { kind: 'image', ext: 'jpg', mime: 'image/jpeg', test: b => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  { kind: 'image', ext: 'gif', mime: 'image/gif', test: b => b[0] === 0x47 && b[1] === 0x49 && b[2] === 0x46 },
  { kind: 'image', ext: 'webp', mime: 'image/webp', test: b => b[8] === 0x57 && b[9] === 0x45 && b[10] === 0x42 && b[11] === 0x50 },
  // فحص webm قبل mkv: الترويسة نفسها، والفرق في نوع المحتوى داخل الملف.
  { kind: 'video', ext: 'webm', mime: 'video/webm', test: b => b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3 },
  // عائلة MP4 (mp4/3gp/m4a) لا تُفحص هنا: علامتها واحدة `ftyp`، والتمييز
  // يحتاج قراءة العلامة الداخلية ومسارات الملف — انظر sniffMp4Family.
  { kind: 'audio', ext: 'ogg', mime: 'audio/ogg', test: b => b[0] === 0x4f && b[1] === 0x67 && b[2] === 0x67 && b[3] === 0x53 },
  { kind: 'audio', ext: 'wav', mime: 'audio/wav', test: b => b[0] === 0x52 && b[1] === 0x49 && b[2] === 0x46 && b[3] === 0x46 && b[8] === 0x57 && b[9] === 0x41 && b[10] === 0x56 && b[11] === 0x45 },
  { kind: 'audio', ext: 'mp3', mime: 'audio/mpeg', test: b => b[0] === 0x49 && b[1] === 0x44 && b[2] === 0x33 },
  { kind: 'audio', ext: 'mp3', mime: 'audio/mpeg', test: b => b[0] === 0xff && (b[1] & 0xe0) === 0xe0 },
  { kind: 'audio', ext: 'aac', mime: 'audio/aac', test: b => b[0] === 0xff && (b[1] & 0xf6) === 0xf0 },
]

/**
 * يتحقق أن البايتات وسيط فعلي ويُعيد نوعه وامتداده.
 *
 * الاعتماد على نوع يرسله العميل كان يسمح برفع أي ملف (سكريبت HTML مثلاً)
 * وتخزينه بامتداد صورة، فيصبح رابطاً يُخدَم بترويسة صورة مزيفة. الفحص هنا
 * يجعل ما يُخزَّن وسيطاً حقيقياً فقط.
 */
function sniffMedia(bytes: Uint8Array): MediaSig | null {
  if (bytes.length < 16) return null
  if (bytes[4] === 0x66 && bytes[5] === 0x74 && bytes[6] === 0x79 && bytes[7] === 0x70) {
    return sniffMp4Family(bytes)
  }
  for (const s of MEDIA_SIGNATURES) if (s.test?.(bytes)) return s
  return null
}

/**
 * يميّز داخل عائلة MP4 بين فيديو و3gp وصوت m4a.
 *
 * كلها تشترك في علامة `ftyp` عند البايت الرابع، فترتيب الجدول وحده كان
 * يجعل أول قاعدة mp4 تلتقط كل ملفات m4a أيضاً — أي أن كل رسالة صوتية
 * سُجّلت من التطبيق خُزّنت كـ«فيديو»، فعُرضت بمشغّل فيديو بدل موجة صوتية.
 * التمييز الصحيح: العلامة الداخلية (bytes 8..11) ثم وجود مسار فيديو `vide`
 * داخل الملف؛ ملف صوتي لا مسار فيديو فيه.
 */
function sniffMp4Family(bytes: Uint8Array): MediaSig {
  const brand = String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11])
  const audioBrand = brand === 'M4A ' || brand === 'M4B ' ||
    brand === 'M4P ' || brand === 'F4A '
  const is3gp = brand.startsWith('3gp') || brand.startsWith('3g2')
  // مسارات الملف تكون في `moov`، وهو إمّا في مقدّمة الملف (faststart) أو في
  // آخر. نفحص الطرفين فقط بدل فكّ الملف كله: يكفي للتمييز ويظل رخيصاً على
  // المقاطع الكبيرة. فكّ latin1 يكفي لمقارنة ASCII بلا تحقق UTF-8.
  const dec = new TextDecoder('latin1')
  const edge = 64 * 1024
  const head = dec.decode(bytes.subarray(0, Math.min(edge, bytes.length)))
  const tail = bytes.length > edge
    ? dec.decode(bytes.subarray(Math.max(0, bytes.length - edge)))
    : ''
  const hasVideo = head.includes('vide') || tail.includes('vide')
  const hasAudio = head.includes('soun') || tail.includes('soun')

  if (hasVideo) {
    return is3gp
      ? { kind: 'video', ext: '3gp', mime: 'video/3gpp' }
      : { kind: 'video', ext: 'mp4', mime: 'video/mp4' }
  }
  if (hasAudio || audioBrand || is3gp) {
    return { kind: 'audio', ext: 'm4a', mime: 'audio/mp4' }
  }
  // بلا مسار ظاهر — الغالب في مقاطع الجوال فيديو، وهذا الاحتياط يحفظ
  // السلوك القديم بدل رفض الملف.
  return audioBrand
    ? { kind: 'audio', ext: 'm4a', mime: 'audio/mp4' }
    : { kind: 'video', ext: 'mp4', mime: 'video/mp4' }
}

/** تنقية النص: نحذف محارف التحكم وعلامات الاتجاه المزيفة. */
function cleanText(raw: unknown, max: number): string {
  return String(raw ?? '')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, '')
    .replace(/[\u202A-\u202E\u2066-\u2069]/g, '')
    .trim()
    .slice(0, max)
}

interface ChatProfile { user_id: string; nickname: string; avatar_key: string; notify: number }

async function chatProfiles(XDB: D1Database, ids: string[]): Promise<Map<string, ChatProfile>> {
  const out = new Map<string, ChatProfile>()
  const uniq = [...new Set(ids.filter(Boolean))].slice(0, 200)
  if (!uniq.length) return out
  // استعلام واحد بقائمة معاملات: بديل الاستعلام لكل مستخدم كان يضرب حدّ
  // استعلامات D1 في قسم نشط بسرعة.
  const ph = uniq.map((_, i) => `?${i + 1}`).join(',')
  const res = await XDB.prepare(
    `SELECT user_id, nickname, avatar_key, notify FROM x_chat_profiles WHERE user_id IN (${ph})`
  ).bind(...uniq).all<ChatProfile>()
  for (const r of res.results ?? []) out.set(r.user_id, r)
  return out
}

/** إجراءات المالك الفعّالة على مستخدم — كتم سارٍ وطرد غير منتهٍ. */
async function chatRestriction(env: Env, userId: string, roomId: string): Promise<{
  muted: boolean; kicked: boolean; reason: string; until: number
}> {
  const now = Date.now()
  const rows = await env.XDB.prepare(
    `SELECT kind, room_id, reason, until FROM x_chat_actions WHERE user_id = ?1`
  ).bind(userId).all<{ kind: string; room_id: string; reason: string; until: number }>()
  let muted = false, kicked = false, reason = '', until = 0
  for (const r of rows.results ?? []) {
    // room_id فارغ = يسري على كل الأقسام
    if (r.room_id && r.room_id !== roomId) continue
    // until === 0 يعني بلا نهاية، للنوعين.
    const live = r.until === 0 || r.until > now
    if (!live) continue
    if (r.kind === 'mute') { muted = true; if (r.until > until) until = r.until }
    if (r.kind === 'kick') { kicked = true; if (r.until > until) until = r.until }
    if (r.reason) reason = r.reason
  }
  return { muted, kicked, reason, until }
}

/** مشتركون فعلاً: اشتراك سارٍ (expires_at مستقبلي) أو بلا انتهاء. */
function isSubscriber(user: XUser | null): boolean {
  if (!user) return false
  if (user.role === 'owner') return true
  return user.expires_at === 0 || user.expires_at > Date.now()
}

/**
 * من يستطيع الكتابة؟ قرار واحد في مكان واحد.
 *
 * كان الفحص موزّعاً في كل مسار، وأي مسار جديد ينسى فحصاً يفتح ثغرة. هنا
 * تُرجع السبب أيضاً، فيظهر للمستخدم منع مفهوم لا خطأ غامض.
 */
function chatWriteAllowed(
  settings: XSettings, caller: Caller, user: XUser | null,
): { ok: boolean; reason: string } {
  if (caller.role === 'owner') return { ok: true, reason: '' }
  if (settings.chatReadOnly) return { ok: false, reason: 'الدردشة في وضع القراءة فقط' }
  if (!user) return { ok: false, reason: 'أنشئ حساباً للمشاركة في الدردشة' }
  if (!user.active) return { ok: false, reason: 'الحساب بانتظار تفعيل المالك' }
  if (settings.chatWriteScope === 'subscribers' && !isSubscriber(user)) {
    return { ok: false, reason: 'الكتابة للمشتركين فقط — تواصل مع المالك' }
  }
  return { ok: true, reason: '' }
}

/** من يرسل صوتاً/فيديو؟ المالك، والمشتركون السارون فقط. */
function chatMediaAllowed(
  settings: XSettings, caller: Caller, user: XUser | null,
): { ok: boolean; reason: string } {
  if (caller.role === 'owner') return { ok: true, reason: '' }
  if (settings.chatMediaScope === 'none') {
    return { ok: false, reason: 'إرسال المقاطع موقوف حالياً' }
  }
  if (!isSubscriber(user)) {
    return { ok: false, reason: 'الصوت والفيديو للمشتركين السارين فقط' }
  }
  return { ok: true, reason: '' }
}

/** شكل الرسالة كما تُرسل للتطبيق — يُبنى في مكان واحد. */
function chatMessageJson(
  m: {
    id: string; room_id: string; user_id: string; kind: string
    body: string; media_key: string; media_mime: string; media_size: number
    created_at: number; waveform?: string; media_seconds?: number
  },
  p: ChatProfile | undefined,
  meId: string,
): Record<string, unknown> {
  return {
    id: m.id,
    roomId: m.room_id,
    kind: m.kind,
    body: m.body,
    mediaUrl: m.media_key ? `/v1/media/${m.media_key}` : '',
    mediaMime: m.media_mime,
    mediaSize: m.media_size,
    // مخطط الموجة يُرسل كسلسلة أرقام مفصولة بفواصل ويُفكّ في التطبيق.
    // الصيغة النصّية توفّر تحويلات JSON لعشرات الأرقام في كل رسالة صوتية.
    waveform: m.waveform ?? '',
    seconds: m.media_seconds ?? 0,
    at: m.created_at,
    mine: m.user_id === meId,
    author: {
      id: m.user_id,
      nickname: p?.nickname || '',
      avatarUrl: p?.avatar_key ? `/v1/media/${p.avatar_key}` : '',
    },
  }
}

/**
 * المشاهدون لكل رسالة — من تجاوز ختمه الزمني زمن الرسالة.
 *
 * التخزين ختم واحد لكل (مستخدم، قسم) لا صف لكل مشاهدة: كلفة الكتابة تبقى
 * ثابتة مهما كثرت الرسائل، والقراءة استعلام صغير واحد. الصور تُعرض حتى 8
 * مشاهدين فقط — قائمة أطول لا تُقرأ على شاشة جوال.
 */
async function chatSeers(
  env: Env, roomId: string, times: number[], excludeId: string,
): Promise<Map<number, { id: string; nickname: string; avatarUrl: string }[]>> {
  const out = new Map<number, { id: string; nickname: string; avatarUrl: string }[]>()
  if (!times.length) return out
  const min = Math.min(...times)
  const rows = await env.XDB.prepare(
    `SELECT user_id, last_at FROM x_chat_seen
     WHERE room_id = ?1 AND last_at >= ?2 AND user_id <> ?3
     ORDER BY last_at DESC LIMIT 200`
  ).bind(roomId, min, excludeId).all<{ user_id: string; last_at: number }>()
  const seen = rows.results ?? []
  if (!seen.length) return out
  const profiles = await chatProfiles(env.XDB, seen.map(s => s.user_id))
  for (const t of times) {
    const list = seen
      .filter(s => s.last_at >= t)
      .slice(0, 8)
      .map(s => {
        const p = profiles.get(s.user_id)
        return {
          id: s.user_id,
          nickname: p?.nickname || '',
          avatarUrl: p?.avatar_key ? `/v1/media/${p.avatar_key}` : '',
        }
      })
    out.set(t, list)
  }
  return out
}

/**
 * إحصاء أعضاء القسم: كم عضواً شارك فيه، وكم منهم متصل الآن.
 *
 * «متصل» يعني ختم مشاهدة حُدّث قبل دقيقتين. الختم يُحدَّث في كل دورة تحديث
 * دوري، فالرقم يعكس وجوداً فعلياً لا تخميناً. العتبة دقيقتان لأن أبطأ دورة
 * تحديث مسموحة 30 ثانية، فدقيقتان تمنع ظهور العضو متصلاً وهو خرج للتوّ.
 */
async function chatRoomStats(
  env: Env, roomId: string,
): Promise<{ members: number; online: number }> {
  const since = Date.now() - 120_000
  const [mem, on] = await Promise.all([
    env.XDB.prepare(
      `SELECT COUNT(DISTINCT user_id) c FROM x_chat_messages
       WHERE room_id = ?1 AND deleted = 0`
    ).bind(roomId).first<{ c: number }>(),
    env.XDB.prepare(
      `SELECT COUNT(*) c FROM x_chat_seen
       WHERE room_id = ?1 AND seen_at >= ?2`
    ).bind(roomId, since).first<{ c: number }>(),
  ])
  return { members: Number(mem?.c ?? 0), online: Number(on?.c ?? 0) }
}

/**
 * البثّ التفاضلي: يُرجع الجديد بعد `since` وحده، أو الأحدث صفحةً واحدة.
 *
 * هذا ما يمنع تحميل المحادثة كاملة كل مرة، ويمنع الانهيار عند آلاف الرسائل:
 * الطلب الدوري عادةً يحمل صفراً أو رسالة أو رسالتين، والصفحة الأولى محدودة
 * بـ40، والأقدم تُجلب عند التمرير للأعلى على دفعات.
 */
async function chatPage(
  env: Env, roomId: string, opts: { since?: number; before?: number; limit: number },
): Promise<{ messages: any[]; hasMore: boolean }> {
  const { since = 0, before = 0, limit } = opts
  let rows: D1Result<any>
  if (since > 0) {
    // رسائل جديدة منذ آخر تحديث — تصاعدي لنعرضها بترتيبها الطبيعي
    rows = await env.XDB.prepare(
      `SELECT id, room_id, user_id, kind, body, media_key, media_mime, media_size, created_at, waveform, media_seconds
       FROM x_chat_messages
       WHERE room_id = ?1 AND deleted = 0 AND created_at > ?2
       ORDER BY created_at ASC LIMIT ?3`
    ).bind(roomId, since, limit).all<any>()
    return { messages: rows.results ?? [], hasMore: false }
  }
  rows = await env.XDB.prepare(
    `SELECT id, room_id, user_id, kind, body, media_key, media_mime, media_size, created_at, waveform, media_seconds
     FROM x_chat_messages
     WHERE room_id = ?1 AND deleted = 0 ${before > 0 ? 'AND created_at < ?3' : ''}
     ORDER BY created_at DESC LIMIT ?2`
  ).bind(...(before > 0 ? [roomId, limit, before] : [roomId, limit])).all<any>()
  const list = rows.results ?? []
  // الأحدث أولاً في الاستعلام، ويُعرض تصاعدياً في التطبيق
  return { messages: list.slice().reverse(), hasMore: list.length === limit }
}





// ───────────────────────── الدفع عبر FCM ─────────────────────────

/**
 * الدفع الحقيقي لإشعارات أندرويد.
 *
 * يحتاج حساب خدمة Firebase (سرّ `FCM_SERVICE_ACCOUNT`). بلا هذا السرّ تبقى
 * كل الدوال هنا صامتة: التطبيق يعمل، والإشعارات المحلية تعمل، ولا دفع.
 * هذا مقصود — لا نريد بناءً يفشل لأن سرّاً غير مضبوط في بيئة لم تُهيّأ بعد.
 *
 * المسار: نوقّع JWT بـ RS256 بمفتاح الحساب، نستبدله برمز وصول من Google،
 * ثم نرسل للجهاز عبر FCM HTTP v1. لا نستخدم المفتاح القديم (server key):
 * أوقفت Google الدفع به وأصبح غير موثوق.
 */

interface FcmAccount {
  project_id: string
  client_email: string
  private_key: string
}

let _fcmAccount: FcmAccount | null | undefined
let _fcmToken: { value: string; exp: number } | null = null

function fcmAccount(env: Env): FcmAccount | null {
  if (_fcmAccount !== undefined) return _fcmAccount
  const raw = env.FCM_SERVICE_ACCOUNT
  if (!raw) return (_fcmAccount = null)
  try {
    const j = JSON.parse(raw) as FcmAccount
    if (!j.client_email || !j.private_key) return (_fcmAccount = null)
    // الأسرار تُخزَّن غالباً بأسطر مهرَّبة؛ نعيدها قبل الاستخدام وإلا فشل
    // تحليل المفتاح برسالة غامضة.
    if (!j.private_key.includes('\n')) j.private_key = j.private_key.replace(/\\n/g, '\n')
    if (env.FCM_PROJECT_ID) j.project_id = env.FCM_PROJECT_ID
    return (_fcmAccount = j)
  } catch {
    return (_fcmAccount = null)
  }
}

function b64url(bytes: Uint8Array | string): string {
  const bin = typeof bytes === 'string'
    ? bytes
    : Array.from(bytes, b => String.fromCharCode(b)).join('')
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')
  const bin = atob(body)
  const out = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i)
  return out.buffer
}

/** رمز وصول Google، ويُخزَّن حتى انتهائه لتجنّب توقيع JWT لكل إشعار. */
async function fcmAccessToken(account: FcmAccount): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000)
  if (_fcmToken && _fcmToken.exp > now + 60) return _fcmToken.value
  try {
    const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
    const claim = b64url(JSON.stringify({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }))
    const key = await crypto.subtle.importKey(
      'pkcs8', pemToPkcs8(account.private_key),
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign'],
    )
    const sig = await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claim}`),
    )
    const jwt = `${header}.${claim}.${b64url(new Uint8Array(sig))}`
    const res = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    })
    if (!res.ok) return null
    const j = await res.json() as { access_token?: string; expires_in?: number }
    if (!j.access_token) return null
    _fcmToken = { value: j.access_token, exp: now + (j.expires_in ?? 3600) }
    return _fcmToken.value
  } catch {
    return null
  }
}

interface PushPayload {
  title: string
  body: string
  /** حمولة الوجهة كما يفكّها التطبيق: {k:'chat',r:'...'} أو {k:'ad'}. */
  target: { k: string; r?: string }
  /** معرّف لإزالة التكرار عند إعادة المحاولة. */
  collapseKey?: string
}

/**
 * يرسل إشعاراً لرموز أجهزة. يُعيد عدد ما قُبل، ويمسح الرموز الميتة.
 *
 * الرمز الميت (`UNREGISTERED` أو `INVALID_ARGUMENT`) يُحذف فوراً: إبقاؤه
 * يجعل كل إرسال لاحق يدفع ثمناً بلا أمل، ويخفي أن التثبيت زال.
 */
async function fcmSend(
  env: Env, tokens: string[], payload: PushPayload,
): Promise<number> {
  const account = fcmAccount(env)
  if (!account || tokens.length === 0) return 0
  const token = await fcmAccessToken(account)
  if (!token) return 0

  const url = `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`
  let sent = 0
  const dead: string[] = []

  // التزامن المحدود: قسم نشِط قد يحمل مئات الأجهزة، وفتح نداء لكل رمز دفعة
  // واحدة يستهلك حدود الاتصال. عشرات متوازية تكفي بلا انفجار.
  const queue = [...tokens]
  const workers = Array.from({ length: Math.min(10, queue.length) }, async () => {
    for (;;) {
      const t = queue.shift()
      if (!t) return
      try {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            authorization: `Bearer ${token}`,
            'content-type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: t,
              // `data` لا `notification`: نريد التطبيق يبني الإشعار بنفسه
              // فيظهر بنفس القناة والأيقونة والوجهة التي يعرفها.
              data: {
                title: payload.title,
                body: payload.body,
                target: JSON.stringify(payload.target),
              },
              android: {
                priority: 'HIGH',
                ...(payload.collapseKey ? { collapse_key: payload.collapseKey } : {}),
              },
            },
          }),
        })
        if (res.ok) { sent++; continue }
        const j = await res.json().catch(() => null) as
          { error?: { status?: string; details?: Array<{ errorCode?: string }> } } | null
        const status = j?.error?.status ?? ''
        const code = j?.error?.details?.[0]?.errorCode ?? ''
        if (status === 'NOT_FOUND' || status === 'INVALID_ARGUMENT' ||
            code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT') {
          dead.push(t)
        }
      } catch {
        // خطأ شبكة عابر: الرمز سليم، نتركه للمحاولة القادمة.
      }
    }
  })
  await Promise.all(workers)

  if (dead.length > 0) {
    await env.XDB.prepare(
      `DELETE FROM x_push_tokens WHERE token IN (${dead.map(() => '?').join(',')})`
    ).bind(...dead).run().catch(() => {})
  }
  return sent
}

/** يرسل لكل أجهزة مستخدم إلا جهازه الحالي. */
async function pushToUser(
  env: Env, userId: string, payload: PushPayload, exceptToken = '',
): Promise<number> {
  if (!userId) return 0
  const rows = await env.XDB.prepare(
    'SELECT token FROM x_push_tokens WHERE user_id = ?1'
  ).bind(userId).all<{ token: string }>()
  const tokens = (rows.results ?? []).map(r => r.token).filter(t => t && t !== exceptToken)
  return fcmSend(env, tokens, payload)
}

/** يرسل لكل الأجهزة المسجّلة — لإعلان عام. */
async function pushToAll(
  env: Env, payload: PushPayload, exceptToken = '',
): Promise<number> {
  const rows = await env.XDB.prepare('SELECT token FROM x_push_tokens')
    .all<{ token: string }>()
  const tokens = (rows.results ?? []).map(r => r.token).filter(t => t && t !== exceptToken)
  return fcmSend(env, tokens, payload)
}

/** هل الدفع مهيّأ؟ يظهر للتشخيص في رد لوحة المالك. */
function pushEnabled(env: Env): boolean {
  return fcmAccount(env) !== null
}

/**
 * ينبّه أعضاء القسم برسالة جديدة.
 *
 * الشروط مطابقة لما يقرّره التطبيق في جانبه، لأن الخادم هو من يملك القائمة
 * الكاملة للأجهزة: لا إشعار لصاحب الرسالة، ولا لمن كتم الإشعارات.
 *
 * ولا ننتظر النتيجة في مسار الطلب: الإرسال قد يستغرق ثواني مع مئات الأجهزة،
 * وإرسال الرسالة نفسه يجب أن يعود فوراً. النداء يقع عبر `waitUntil` فيتمّ
 * في الخلفية بلا تأخير المستخدم.
 */
async function pushRoomMessage(
  env: Env, roomId: string, authorId: string, authorName: string, preview: string,
): Promise<number> {
  if (!pushEnabled(env)) return 0
  const rows = await env.XDB.prepare(
    `SELECT t.token AS token, COALESCE(p.notify, 1) AS notify
     FROM x_push_tokens t
     LEFT JOIN x_chat_profiles p ON p.user_id = t.user_id
     WHERE t.user_id <> ?1`
  ).bind(authorId).all<{ token: string; notify: number }>()
  const tokens = (rows.results ?? [])
    .filter(r => r.notify !== 0)
    .map(r => r.token)
  if (!tokens.length) return 0
  return fcmSend(env, tokens, {
    title: authorName || 'رسالة جديدة',
    body: preview || 'أرسل مرفقاً',
    target: { k: 'chat', r: roomId },
    // الرسائل المتتابعة في القسم نفسه تُطوى لا تُكدَّس.
    collapseKey: `room_${roomId}`,
  })
}

/**
 * سطر مختصر للرسالة يُعرض في الإشعار.
 *
 * رسالة الوسائط جسدها فارغ غالباً، فتظهر في الإشعار فراغاً بلا معنى. نستبدلها
 * بوصف قصير، ونطابق ما يعرضه التطبيق في جانبه حتى لا يختلف النصّان.
 */
function chatPreview(kind: string, body: string, seconds: number): string {
  const text = (body ?? '').trim()
  if (text) return text.length <= 120 ? text : `${text.slice(0, 120)}…`
  if (kind === 'image') return 'أرسل صورة'
  if (kind === 'video') return 'أرسل مقطع فيديو'
  if (kind === 'audio') return seconds > 0 ? `أرسل رسالة صوتية (${seconds} ث)` : 'أرسل رسالة صوتية'
  return ''
}


export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)
    const path = url.pathname

    try {
      if (!['GET', 'POST', 'PUT', 'DELETE'].includes(request.method)) throw new HttpError(405, 'method not allowed')
      if (path === '/health') return json({ ok: true, ts: Date.now() })

      if (BLOCKED_UA.test(request.headers.get('user-agent') ?? '')) throw new HttpError(403, 'forbidden')
      // مسارات المالك وتسجيل الدخول معفاة من فحص الحظر: بدون ذلك يبقى
      // المالك خارج تطبيقه نهائياً إذا حُظر جهازه أو عنوانه (نقرة خاطئة على
      // زر الحظر، أو حظر تلقائي)، لأنه لا يصل لصفحة إلغاء الحظر أصلاً —
      // فحص الحظر يسبق المصادقة. بقية المسارات محمية كما هي، والوصول إلى
      // /v1/owner/* يظل محكوماً بجلسة owner موقّعة.
      const banExempt = path.startsWith('/v1/owner') || path === '/v1/auth/login'
      if (!banExempt) {
        await assertIpClean(env, request)
        await assertDeviceAllowed(env, request)
        await trackDeviceFarm(env, request)
      }

      // توقيع التطبيق إلزامي لكل /v1/* — السكريبتات الخارجية تموت هنا
      if (path.startsWith('/v1/')) await verifySignature(env, request)

      const settings = await xSettings(env.XDB)
      if (settings.appLocked && !path.startsWith('/v1/owner')) {
        throw new HttpError(503, settings.lockMessage || 'التطبيق متوقف مؤقتاً للصيانة')
      }
      const gate = versionGate(request, settings)
      if (gate) return gate

      // ---------- عام (موقّع، بدون جلسة) ----------

      if (path === '/v1/bootstrap' && request.method === 'GET') {
        return json({
          ok: true,
          serverTime: Date.now(),
          settings: {
            // المنحة اليومية الواحدة لكل الأدوار.
            dailyFreeQuota: settings.dailyFreeQuota,
            guestFileQuota: settings.guestFileQuota,
            guestCompatQuota: settings.guestCompatQuota,
            compatSearchCost: settings.compatSearchCost,
            minVersion: settings.minVersion,
            telegramLink: settings.telegramLink,
            schematicsLocked: settings.schematicsLocked,
            compatLocked: settings.compatLocked,
            packages: settings.packages,
            privacyPolicy: settings.privacyPolicy,
            // الدردشة تُعلن وجودها مبكراً حتى يعرف التطبيق أي تبويب يعرض.
            chatEnabled: settings.chatEnabled
          },
          update: {
            message: settings.updateMessage,
            url: settings.updateUrl,
            imageUrl: settings.updateImageUrl
          },
          announcements: await announcements(env)
        })
      }

      if (path === '/v1/install' && request.method === 'POST') {
        const body = await request.json() as { installId?: string; appVersion?: string }
        const installId = body.installId?.trim()
        if (!installId || installId.length > 80) throw new HttpError(400, 'installId required')
        const now = new Date().toISOString()
        await env.XDB.prepare(
          `INSERT INTO x_installs (install_id, device_id, app_version, first_seen, last_seen, last_ip)
           VALUES (?1, ?2, ?3, ?4, ?4, ?5)
           ON CONFLICT(install_id) DO UPDATE SET last_seen = ?4, app_version = ?3, last_ip = ?5`
        ).bind(installId, deviceOf(request) || null, body.appVersion ?? 'unknown', now, ip(request)).run()
        return json({ ok: true })
      }

      // ---------- المصادقة ----------

      if (path === '/v1/auth/guest' && request.method === 'POST') {
        // 60 بدل 10: إنشاء الجلسة يحدث في كل فتح، والحدّ الضيّق كان يرفض
        // المستخدم في أول تشغيل. المفتاح صار الجهاز فلا يضر أحداً بغيره.
        await rateLimit(env, request, 'guest', 60, 3600)
        const dev = deviceOf(request)
        if (!dev) throw new HttpError(400, 'deviceId required')
        const token = await signJwt({ sub: `guest_${dev}`, role: 'guest', dev }, env.X_JWT_SECRET, 7 * DAY)
        return json({ token, user: { id: `guest_${dev}`, role: 'guest' } })
      }

      if (path === '/v1/auth/register' && request.method === 'POST') {
        await rateLimit(env, request, 'register', 8, 3600)
        const body = await request.json() as { username?: string; password?: string; displayName?: string; note?: string }
        const username = body.username?.trim() ?? ''
        const password = body.password ?? ''
        if (!/^[\w.\-@]{3,60}$/.test(username)) throw new HttpError(400, 'اسم مستخدم غير صالح')
        if (password.length < 6) throw new HttpError(400, 'كلمة المرور قصيرة')
        if (await xUserByName(env.XDB, username)) throw new HttpError(409, 'اسم المستخدم مستخدم')
        const id = `u_${uid()}`
        await env.XDB.batch([
          env.XDB.prepare(
            `INSERT INTO x_users (id, username, display_name, password_hash, role, active, device_id, expires_at, created_at)
             VALUES (?1, ?2, ?3, ?4, 'user', 0, ?5, 0, ?6)`
          ).bind(id, username, body.displayName?.trim() ?? '', await hashPassword(password), deviceOf(request) || null, new Date().toISOString()),
          env.XDB.prepare(
            `INSERT INTO x_requests (id, username, note, device_id, status, created_at) VALUES (?1, ?2, ?3, ?4, 'pending', ?5)`
          ).bind(`r_${uid()}`, username, body.note?.trim() ?? '', deviceOf(request) || null, new Date().toISOString())
        ])
        return json({ ok: true, pending: true, telegram: settings.telegramLink })
      }

      if (path === '/v1/auth/login' && request.method === 'POST') {
        await rateLimit(env, request, 'login', 10, 600)
        const body = await request.json() as { username?: string; password?: string }
        const user = await xUserByName(env.XDB, body.username?.trim() ?? '')
        if (!user || !(await verifyPassword(body.password ?? '', (user as any).password_hash ?? ''))) {
          await noteAbuse(env, request, 'bad_login', 'low')
          await logSecurity(env, request, 'bad_login', `user=${body.username ?? ''}`)
          throw new HttpError(401, 'بيانات الدخول غير صحيحة')
        }
        if (!user.active) throw new HttpError(403, 'الحساب بانتظار تفعيل المالك')
        const token = await signJwt({ sub: user.id, role: user.role }, env.X_JWT_SECRET, 30 * DAY)
        return json({
          token,
          user: { id: user.id, username: user.username, displayName: user.display_name, role: user.role }
        })
      }

      // إنشاء حساب المالك لأول مرة — محمي بمفتاح سري + يعمل مرة واحدة فقط
      if (path === '/v1/owner/bootstrap' && request.method === 'POST') {
        const key = request.headers.get('x-owner-key')?.trim()
        if (!env.X_OWNER_KEY || key !== env.X_OWNER_KEY) {
          await noteAbuse(env, request, 'bad_owner_key')
          await logSecurity(env, request, 'bad_owner_key')
          throw new HttpError(403, 'forbidden')
        }
        const existing = await env.XDB.prepare("SELECT id FROM x_users WHERE role = 'owner' LIMIT 1").first()
        if (existing) throw new HttpError(409, 'owner exists')
        const body = await request.json() as { username?: string; password?: string }
        const username = body.username?.trim() ?? 'owner'
        if ((body.password ?? '').length < 8) throw new HttpError(400, 'password too short')
        await env.XDB.prepare(
          `INSERT INTO x_users (id, username, display_name, password_hash, role, active, device_id, expires_at, created_at)
           VALUES (?1, ?2, 'المالك', ?3, 'owner', 1, NULL, 0, ?4)`
        ).bind(`owner_${uid()}`, username, await hashPassword(body.password!), new Date().toISOString()).run()
        return json({ ok: true })
      }

      // ---------- دخول المالك: مسار معزول بسرّ مستقل ----------
      // لا يمرّ على authenticate العادي: جلسته تُوقَّع بمفتاح مختلف وتحمل
      // typ=owner، فلا يمكن تحويل جلسة مستخدم عادي إلى جلسة مالك.
      if (path === '/v1/owner/login' && request.method === 'POST') {
        await ownerLoginGuard(env)
        const body = await request.json() as { username?: string; password?: string }
        const user = await xUserByName(env.XDB, body.username?.trim() ?? '')
        if (!user || user.role !== 'owner' ||
            !(await verifyPassword(body.password ?? '', (user as any).password_hash ?? ''))) {
          await noteOwnerLoginFail(env, request)
          // نفس الرسالة للحالات الثلاث: لا نكشف وجود الحساب ولا دوره.
          throw new HttpError(401, 'بيانات الدخول غير صحيحة')
        }
        await clearOwnerLoginFails(env)
        await logSecurity(env, request, 'owner_login_ok', `uid=${user.id}`)
        const token = await signOwnerJwt(env, { sub: user.id, role: 'owner' }, 12 * 3600)
        return json({
          ok: true,
          token,
          expiresIn: 12 * 3600,
          user: { id: user.id, username: user.username, role: 'owner' }
        }, 200, { 'cache-control': 'no-store' })
      }

      // ---------- كل المسارات التالية تتطلب جلسة (زائر أو مستخدم) ----------

      const auth = await authenticate(env, request)
      const caller = auth.caller

      // ---------- بيانات التوافقات (قراءة من المرآة فقط) ----------

      if (path === '/v1/data/brands' && request.method === 'GET') {
        await rateLimit(env, request, 'list', 300, 600)
        if (caller.role === 'guest' && settings.compatLocked) {
          throw new HttpError(403, 'التوافقات للمشتركين فقط — تواصل مع المالك')
        }
        const brands = (await mirrorCollection(env.MIRROR, 'brands')).map(d => ({ id: d.id, ...d.fields }))
        // شركات فرعية افتراضية (Redmi/POCO/Oppo/Honor/iQOO) — قراءة فقط من ملفات الشركات الأم
        const files = new Set(brands.map(b => (b as any).file))
        for (const vb of VIRTUAL_SUB_BRANDS) {
          if (files.has(vb.file)) {
            brands.push({
              id: `v_${vb.key}`, name: vb.name, file: vb.file,
              imageUrl: '', records: 0, models: 0, virtual: true, keyword: vb.key
            } as any)
          }
        }
        return json({ brands })
      }

      // دخول شركة: هنا يقع الخصم الوحيد. ينفصل عن البحث كي يدفع المستخدم
      // مرة واحدة عند فتح الشركة ويُعرض له رصيده قبل أن يكتب أي حرف.
      if (path === '/v1/data/compat/open' && request.method === 'POST') {
        const body = await request.json() as { brand?: string }
        const brandRef = String(body.brand ?? '').trim().slice(0, 80)
        const fp = await walletOf(env, request)
        const r = await ensureCompatOpen(env, ctx, caller, settings, fp, brandRef || 'all')
        return json({
          ok: true,
          charged: r.charged, source: r.source,
          remaining: r.freeLeft, balance: r.balance
        }, 200, { 'cache-control': 'no-store' })
      }

      // بحث التوافقات — بعد دخول الشركة، بلا خصم إضافي.
      // POST لا GET: البحث فعل مكلّف لا يجوز أن يُخزَّن في الكاش أو يُستدعى
      // تلقائياً من متصفح/زاحف، ولا يظهر نصه في سجلات الوسطاء.
      if (path === '/v1/data/compat/search' && request.method === 'POST') {
        await Promise.all([
          rateLimit(env, request, 'compatsearch', 240, 600),
          rateLimit(env, request, 'compatsearchhour', 120, 3600)
        ])
        if (caller.role === 'guest' && settings.compatLocked) {
          throw new HttpError(403, 'التوافقات للمشتركين فقط — تواصل مع المالك')
        }
        const body = await request.json() as {
          q?: string; brand?: string; type?: string; limit?: number
        }
        // حدود صارمة: نص طويل أو نوع غير معروف يزيد كلفة LIKE بلا فائدة
        const q = String(body.q ?? '').trim().slice(0, 64).toLowerCase()
        let brandRef = String(body.brand ?? '').trim().slice(0, 80)
        const type = String(body.type ?? '').trim().slice(0, 24).toUpperCase()

        let brandFile = brandRef || undefined
        let keyword: string | undefined
        if (brandRef.startsWith('v_')) {
          const vb = VIRTUAL_SUB_BRANDS.find(v => `v_${v.key}` === brandRef)
          brandFile = vb?.file
          keyword = vb?.key
        }
        // نوع غير معروف لا يطابق شيئاً — نرفضه بدل تمريره للاستعلام
        if (type && !COMPAT_TYPES.includes(type)) {
          throw new HttpError(400, 'نوع قطعة غير معروف')
        }
        const types = brandFile
          ? await cached(env, `ctypes:${brandFile}`, 3600, () => compatTypesOf(env.MIRROR, brandFile!))
          : [...COMPAT_TYPES]

        // لا خصم على استعلام فارغ: هو استعراض لأنواع الشركة لا سحب بيانات.
        if (!q) {
          return json({ records: [], types, charged: false, remaining: -1 },
            200, { 'cache-control': 'no-store' })
        }

        // الخصم عند دخول الشركة أول مرة في اليوم — لا مع كل نص.
        const fp = await walletOf(env, request)
        const r = await ensureCompatOpen(
          env, ctx, caller, settings, fp, brandRef || 'all')

        const results = await mirrorSearchCompat(env.MIRROR, {
          query: q, brandFile, keyword,
          type: type || undefined,
          limit: Math.max(1, Math.min(Number(body.limit) || 60, 120))
        })
        return json({
          records: results.map(d => ({ id: d.id, ...d.fields })),
          types, charged: r.charged, source: r.source,
          remaining: r.freeLeft,
          balance: r.balance
        }, 200, {
          'cache-control': 'no-store',
          'x-content-type-options': 'nosniff'
        })
      }

      // نفس بحث npm التوافقات لكن بـ GET — يُستعمل للتشخيص وللإصدارات
      // القديمة من التطبيق. يخضع لنفس الخصم تماماً.
      //
      // استعلام فارغ مرفوض: كان يسمح بسحب سجلات شركة كاملة (حتى 500 سجل)
      // بصفر بطاقات، فيكفي المهاجم أن يمرّ على كل الشركات ليحصل على كل
      // التوافقات مجاناً — أي أن نظام العملات كان بلا معنى.
      if (path === '/v1/data/compatibility' && request.method === 'GET') {
        await rateLimit(env, request, 'compat', 60, 600)
        if (caller.role === 'guest' && settings.compatLocked) {
          throw new HttpError(403, 'التوافقات للمشتركين فقط — تواصل مع المالك')
        }
        const q = url.searchParams.get('q')?.trim().slice(0, 64).toLowerCase() ?? ''
        if (!q) {
          throw new HttpError(400, 'نص البحث مطلوب — استخدم /v1/data/compat/search')
        }
        let brandRef = url.searchParams.get('brand')?.trim() ?? ''
        const type = (url.searchParams.get('type')?.trim() ?? '').toUpperCase()
        if (type && !COMPAT_TYPES.includes(type)) {
          throw new HttpError(400, 'نوع قطعة غير معروف')
        }
        let brandFile = brandRef || undefined
        let keyword: string | undefined
        if (brandRef.startsWith('v_')) {
          const vb = VIRTUAL_SUB_BRANDS.find(v => `v_${v.key}` === brandRef)
          brandFile = vb?.file
          keyword = vb?.key
        }
        const fp = await walletOf(env, request)
        const r = await ensureCompatOpen(
          env, ctx, caller, settings, fp, brandRef || 'all')
        const results = await mirrorSearchCompat(env.MIRROR, {
          query: q, brandFile, keyword,
          type: type || undefined,
          limit: Math.min(Number(url.searchParams.get('limit')) || 60, 120)
        })
        return json({
          records: results.map(d => ({ id: d.id, ...d.fields })),
          charged: r.charged, source: r.source,
          remaining: r.freeLeft,
          balance: r.balance
        }, 200, {
          'cache-control': 'no-store',
          'x-quota-remaining': String(r.freeLeft)
        })
      }

      if (path === '/v1/me' && request.method === 'GET') {
        const fp = await walletOf(env, request)
        const freeUsed = await dailyFreeUsed(env.XDB, fp)
        const freeLimit = Math.max(0, Math.floor(Number(settings.dailyFreeQuota) || 0))
        const wallet = caller.role === 'guest'
          ? await env.XDB.prepare(
              'SELECT balance, expires_at FROM x_guest_wallets WHERE device_id = ?1'
            ).bind(fp).first<{ balance: number; expires_at: number }>()
          : null
        // رصيد واحد للجميع: بطاقات المشترك ومحفظة الزائر في نفس العدّاد،
        // والمنحة اليومية تُضاف إليه في العرض كما تُخصم منه فعلاً.
        const coins = caller.role === 'user'
          ? auth.user?.quota_balance ?? 0
          : caller.role === 'guest'
            ? wallet?.balance ?? 0
            : 0
        const expiresAt = caller.role === 'user'
          ? auth.user?.quota_expires_at ?? 0
          : wallet?.expires_at ?? 0
        const freeLeft = Math.max(0, freeLimit - freeUsed)
        return json({
          user: {
            id: caller.uid, role: caller.role,
            username: auth.user?.username ?? null,
            displayName: auth.user?.display_name ?? ''
          },
          // العدّاد الموحّد — مصدر واحد للشريط الأعلى في التطبيق.
          wallet: {
            freeLimit, freeUsed, freeLeft,
            coins, expiresAt,
            totalLeft: caller.role === 'owner' ? -1 : freeLeft + coins,
            cost: Math.max(1, Math.floor(Number(settings.compatSearchCost) || 1))
          },
          // حقول قديمة تبقى للنسخ السابقة من التطبيق، بنفس أرقام العدّاد
          // الموحّد كي لا ترى رقماً يخالف ما يُخصم.
          quota: { used: freeUsed, limit: freeLimit },
          compatQuota: caller.role === 'owner'
            ? null
            : {
                used: freeUsed,
                limit: freeLimit,
                cost: Math.max(1, Math.floor(Number(settings.compatSearchCost) || 1))
              },
          cards: caller.role === 'owner'
            ? null
            : { balance: coins, expiresAt }
        })
      }

      if (path === '/v1/schem/brands' && request.method === 'GET') {
        await rateLimit(env, request, 'list', 300, 600)
        if (caller.role === 'guest' && settings.schematicsLocked) {
          throw new HttpError(403, 'المخططات للمشتركين فقط — تواصل مع المالك')
        }
        const [catalog, local] = await Promise.all([readCatalogBrands(env), listLocalBrands(env)])
        const merged = new Map<string, CatalogBrand>()
        for (const b of catalog) merged.set(b.name.toLowerCase(), b)
        for (const b of local) merged.set(b.name.toLowerCase(), b)
        return json({ brands: [...merged.values()].sort((a, b) => a.name.localeCompare(b.name)) })
      }

      const modelsMatch = path.match(/^\/v1\/schem\/brands\/(.+)\/models$/)
      if (modelsMatch && request.method === 'GET') {
        await rateLimit(env, request, 'list', 300, 600)
        if (caller.role === 'guest' && settings.schematicsLocked) {
          throw new HttpError(403, 'المخططات للمشتركين فقط — تواصل مع المالك')
        }
        const brandId = decodeURIComponent(modelsMatch[1])
        const q = url.searchParams.get('q')?.trim().toLowerCase() ?? ''
        const models = brandId.startsWith(LOCAL_PREFIX)
          ? await listLocalModels(env, brandId)
          : (await readBrandCatalog(env, brandId))?.models ?? []
        return json({
          models: models
            .filter(m => !q || m.name.toLowerCase().includes(q))
        })
      }

      const filesMatch = path.match(/^\/v1\/schem\/folders\/(.+)\/files$/)
      if (filesMatch && request.method === 'GET') {
        await rateLimit(env, request, 'list', 300, 600)
        const folderId = decodeURIComponent(filesMatch[1])
        let files: CatalogEntry[]
        if (folderId.startsWith(LOCAL_PREFIX)) {
          files = await listLocalFiles(env, folderId)
        } else {
          const segs = folderId.startsWith('r2:') ? folderId.slice(3).split('/') : []
          const catalog = segs.length >= 3 ? await readBrandCatalog(env, `r2:${segs[0]}`) : null
          files = catalog?.folders?.[folderId] ?? []
        }
        return json({ files })
      }

      const fileMatch = path.match(/^\/v1\/file\/(.+)$/)
      if (fileMatch && request.method === 'GET') {
        const fileId = decodeURIComponent(fileMatch[1])
        await Promise.all([
          rateLimit(env, request, 'files', 200, 600),
          rateLimit(env, request, 'fileshour', 120, 3600)
        ])
        const r2Key = fileId.startsWith(LOCAL_PREFIX)
          ? LOCAL_R2 + fileId.slice(LOCAL_PREFIX.length)
          : `schem/${fileId}`

        // لا تُستهلك الحصة إلا إذا كان الملف موجوداً فعلاً
        const headObj = await env.SCHEMATICS.head(r2Key)
        if (!headObj) throw new HttpError(404, 'file not found')
        const fp = await walletOf(env, request)
        // إعادة فتح نفس الملف في اليوم نفسه لا تُخصم مرتين: المستخدم يغلق
        // المخطط ليعود إليه بعد دقيقة، والخصم في كل مرة كان يستنزف رصيده على
        // ملف واحد. لا يُمنع فتح ملفات أخرى — كل ملف جديد يُخصم مرة.
        const remaining = caller.role === 'owner'
          ? -1
          : await consumeFileOnce(env, ctx, caller, settings, fp, r2Key)

        // كاش الحافة: النص المشفر ثابت لكل (ملف+إصدار) — فتح فوري في نفس المنطقة
        // حتى على إنترنت ضعيف. الفحص الأمني والحصة يسبقان الكاش دائماً.
        const cacheKey = new Request(
          `https://x-edge.internal/enc/${encodeURIComponent(r2Key)}?e=${encodeURIComponent(headObj.etag)}`)
        const hit = await caches.default.match(cacheKey)
        if (hit) {
          const h = new Headers(hit.headers)
          h.set('x-quota-remaining', String(remaining === Number.MAX_SAFE_INTEGER ? -1 : remaining))
          h.set('x-cache', 'HIT')
          h.set('cache-control', 'no-store')
          return new Response(hit.body, { status: 200, headers: h })
        }

        const object = await env.SCHEMATICS.get(r2Key)
        if (!object?.body) throw new HttpError(404, 'file not found')
        const plain = await object.arrayBuffer()

        const nonce = await fileNonce(env, r2Key, headObj.etag)
        const cipher = await crypto.subtle.encrypt(
          { name: 'AES-CTR', counter: nonce, length: 64 },
          await fileCryptoKey(env), plain)

        const headers = new Headers()
        headers.set('content-type', 'application/octet-stream')
        headers.set('x-enc', 'aes-ctr')
        headers.set('x-enc-nonce', [...nonce].map(b => b.toString(16).padStart(2, '0')).join(''))
        headers.set('x-orig-type', headObj.httpMetadata?.contentType ?? 'application/octet-stream')
        headers.set('x-orig-size', String(headObj.size))
        headers.set('etag', headObj.etag)
        headers.set('cache-control', 'no-store')
        headers.set('x-quota-remaining', String(remaining === Number.MAX_SAFE_INTEGER ? -1 : remaining))
        headers.set('x-cache', 'MISS')

        const response = new Response(cipher, { status: 200, headers })
        if (cipher.byteLength < 128 * 1024 * 1024) {
          const copy = response.clone()
          copy.headers.set('cache-control', 'public, max-age=86400')
          ctx.waitUntil(caches.default.put(cacheKey, copy))
        }
        return response
      }

      // ---------- الدردشة المجتمعية ----------

      // المستخدم الحالي إن كان مسجّلاً (الزائر بلا صف في x_users).
      const chatUser = auth.user

      // حالة الدردشة: الأقسام، السمات، القيود على المستخدم الحالي.
      // متاحة لكل من يحمل جلسة صالحة (زائر أو مسجّل أو مشترك).
      if (path === '/v1/chat/state' && request.method === 'GET') {
        await rateLimit(env, request, 'list', 300, 600)
        const meId = chatUser?.id ?? `guest:${caller.uid}`
        const mine = await env.XDB.prepare(
          'SELECT nickname, avatar_key, notify FROM x_chat_profiles WHERE user_id = ?1'
        ).bind(meId).first<{ nickname: string; avatar_key: string; notify: number }>()
        // الزوار بلا حساب لا يمكن كتمهم بحساب: معرّفهم مرتبط بالجهاز وحده.
        const rest = chatUser
          ? await chatRestriction(env, chatUser.id, '')
          : { muted: false, kicked: false, reason: '', until: 0 }
        const write = chatWriteAllowed(settings, caller, chatUser)
        const media = chatMediaAllowed(settings, caller, chatUser)
        return json({
          enabled: settings.chatEnabled,
          readOnly: settings.chatReadOnly,
          theme: settings.chatTheme,
          welcome: settings.chatWelcome,
          maxLength: settings.chatMaxLength,
          imagesEnabled: settings.chatImagesEnabled,
          writeScope: settings.chatWriteScope,
          mediaScope: settings.chatMediaScope,
          maxMediaMb: settings.chatMaxMediaMb,
          mediaSeconds: settings.chatMediaSeconds,
          pollMs: settings.chatPollMs,
          rooms: settings.chatRooms,
          canWrite: write.ok,
          writeBlockedReason: write.ok ? '' : write.reason,
          canSendMedia: media.ok,
          mediaBlockedReason: media.ok ? '' : media.reason,
          isSubscriber: isSubscriber(chatUser),
          me: {
            id: meId,
            nickname: mine?.nickname ?? '',
            avatarUrl: mine?.avatar_key ? `/v1/media/${mine.avatar_key}` : '',
            notify: mine?.notify !== 0,
            role: caller.role,
          },
          restriction: rest,
        })
      }

      /**
       * الرسائل — بثلاثة أنماط:
       *   since  : الجديد بعد ختم زمني (التحديث الدوري) — عادةً صفر أو رسالة.
       *   before : دفعة أقدم عند التمرير للأعلى.
       *   بلا شيء: أحدث صفحة عند أول فتح.
       * لا تُحمَّل المحادثة كاملة في أي حال.
       */
      if (path === '/v1/chat/messages' && request.method === 'GET') {
        await rateLimit(env, request, 'chatread', 1200, 600)
        if (!settings.chatEnabled) throw new HttpError(403, 'الدردشة موقوفة حالياً')
        const roomId = url.searchParams.get('room') ?? ''
        const room = settings.chatRooms.find(r => r.id === roomId)
        if (!room) throw new HttpError(404, 'القسم غير موجود')
        const since = Number(url.searchParams.get('since')) || 0
        const before = Number(url.searchParams.get('before')) || 0
        // حدّ الدفعة: 60 كافٍ لتمرير مريح، وأكثر منه يثقل الرد على الجوال.
        const limit = Math.max(1, Math.min(60, Number(url.searchParams.get('limit')) || 40))

        const page = await chatPage(env, roomId, { since, before, limit })
        const list = page.messages
        const meId = chatUser?.id ?? `guest:${caller.uid}`
        const profiles = await chatProfiles(env.XDB, list.map(m => m.user_id))
        // صور المشاهدين: تُحسب للرسائل التي كتبها غيري فقط، وفي نمط
        // التحديث الدوري للرسائل الجديدة وحدها.
        const others = list.filter(m => m.user_id !== meId).map(m => m.created_at)
        const seers = await chatSeers(env, roomId, others, meId)
        // إحصاء الأعضاء في نمط الفتح فقط: عدّاد لا يتغيّر كل أربع ثوانٍ،
        // وحسابه في كل دورة تحديث دوري هدر بلا فائدة.
        const stats = since > 0
          ? null
          : await chatRoomStats(env, roomId)
        return json({
          room: room.id,
          messages: list.map(m => ({
            ...chatMessageJson(m, profiles.get(m.user_id), meId),
            seenBy: seers.get(m.created_at) ?? [],
          })),
          hasMore: page.hasMore,
          members: stats?.members ?? null,
          online: stats?.online ?? null,
        })
      }

      /**
       * حذف رسالة — لصاحبها فقط، وللمالك على أي رسالة.
       *
       * الحذف نصفي (deleted = 1) لا محو للصف: يحفظ سجل الإشراف ويحول دون
       * أن يعيد الطلبُ الدوري رسالةً حُذفت لأن اتصالاً قديماً ما زال يراقب.
       * ولا يُحذف ملف الوسيط من R2: يفعل ذلك مهمة تنظيف مستقلة، وحذفه هنا
       * يُبقي الرسائل القديمة في نوافذ مفتوحة بلا صورة فجأة.
       */
      if (path === '/v1/chat/delete' && request.method === 'POST') {
        await rateLimit(env, request, 'chatwrite', 40, 60)
        const body = await request.json<{ id?: string }>()
          .catch(() => ({} as { id?: string }))
        const msgId = String(body.id ?? '').trim().slice(0, 80)
        if (!msgId) throw new HttpError(400, 'معرّف الرسالة مطلوب')
        const row = await env.XDB.prepare(
          'SELECT user_id, room_id, media_key FROM x_chat_messages WHERE id = ?1 AND deleted = 0'
        ).bind(msgId).first<{ user_id: string; room_id: string; media_key: string }>()
        if (!row) throw new HttpError(404, 'الرسالة غير موجودة')
        const meId = chatUser?.id ?? `guest:${caller.uid}`
        // المالك يحذف أي رسالة؛ غيره يحذف رسالته وحدها.
        if (caller.role !== 'owner' && row.user_id !== meId) {
          throw new HttpError(403, 'يمكنك حذف رسائلك وحدها')
        }
        await env.XDB.prepare(
          'UPDATE x_chat_messages SET deleted = 1 WHERE id = ?1'
        ).bind(msgId).run()
        await logSecurity(env, request, 'chat_delete',
          `حذف رسالة ${msgId} في ${row.room_id}${caller.role === 'owner' ? ' (المالك)' : ''}`)
        return json({ ok: true, id: msgId, roomId: row.room_id })
      }

      /**
       * إعلام الخادم أن المستخدم بلغ آخر رسالة في القسم.
       *
       * هذا ما يجعل «من رأى الرسالة» ممكناً: ختم واحد لكل (مستخدم، قسم).
       * ولا يُحرَّك الختم للخلف أبداً، فطلب متأخر لا يمحو مشاهدة سابقة.
       */
      if (path === '/v1/chat/seen' && request.method === 'POST') {
        await rateLimit(env, request, 'chatread', 1200, 600)
        if (!chatUser) return json({ ok: true, skipped: true })
        const body = await request.json<{ room?: string; at?: number }>()
          .catch(() => ({} as { room?: string; at?: number }))
        const roomId = String(body.room ?? '')
        if (!settings.chatRooms.some(r => r.id === roomId)) {
          throw new HttpError(404, 'القسم غير موجود')
        }
        const at = Math.max(0, Math.min(Date.now(), Math.floor(Number(body.at) || 0)))
        if (at <= 0) return json({ ok: true, skipped: true })
        await env.XDB.prepare(
          `INSERT INTO x_chat_seen (user_id, room_id, last_at, seen_at)
           VALUES (?1, ?2, ?3, ?4)
           ON CONFLICT(user_id, room_id) DO UPDATE SET
             last_at = MAX(x_chat_seen.last_at, excluded.last_at),
             seen_at = excluded.seen_at`
        ).bind(chatUser.id, roomId, at, new Date().toISOString()).run()
        return json({ ok: true })
      }

      // إرسال رسالة نصية أو وسيط (صورة/صوت/فيديو).
      if (path === '/v1/chat/send' && request.method === 'POST') {
        await rateLimit(env, request, 'chatwrite', 40, 60)
        if (!settings.chatEnabled) throw new HttpError(403, 'الدردشة موقوفة حالياً')

        const write = chatWriteAllowed(settings, caller, chatUser)
        if (!write.ok) throw new HttpError(403, write.reason)

        // لا كتابة بلا هوية: من يدخل باسم «عضو» يملأ الدردشة بأسماء متطابقة
        // يتعذّر تمييز أصحابها، ولا يمكن ردّ رسالة على أحدهم. الكنية أو الصورة
        // شرط قبل أول رسالة — والمطالبة بها عند الإرسال لا عند القراءة، حتى
        // يبقى التصفّح مفتوحاً لمن لم يقرّر بعد.
        if (chatUser && caller.role !== 'owner') {
          const prof = await env.XDB.prepare(
            'SELECT nickname, avatar_key FROM x_chat_profiles WHERE user_id = ?1'
          ).bind(chatUser.id)
            .first<{ nickname: string; avatar_key: string }>()
          const hasNick = (prof?.nickname ?? '').trim().length >= 2
          const hasAvatar = (prof?.avatar_key ?? '').length > 0
          if (!hasNick && !hasAvatar) {
            throw new HttpError(403,
              'اختر كنية أو صورة شخصية قبل المراسلة')
          }
        }

        const body = await request.json<{
          room?: string; text?: string; mediaB64?: string
          imageB64?: string; mediaSeconds?: number; waveform?: number[]
        }>().catch(() => ({} as {
          room?: string; text?: string; mediaB64?: string
          imageB64?: string; mediaSeconds?: number; waveform?: number[]
        }))
        const roomId = String(body.room ?? '')
        const room = settings.chatRooms.find(r => r.id === roomId)
        if (!room) throw new HttpError(404, 'القسم غير موجود')

        if (chatUser && caller.role !== 'owner') {
          const rest = await chatRestriction(env, chatUser.id, roomId)
          if (rest.kicked) {
            throw new HttpError(403, rest.reason
              ? `تم إخراجك من الدردشة: ${rest.reason}`
              : 'تم إخراجك من الدردشة مؤقتاً')
          }
          if (rest.muted) {
            throw new HttpError(403, rest.reason
              ? `أنت مكتوم: ${rest.reason}`
              : 'أنت مكتوم من الكتابة في الدردشة')
          }
        }

        const text = cleanText(body.text, settings.chatMaxLength)
        // نستقبل imageB64 القديم أيضاً كي لا تتعطل نسخة مثبّتة سابقة.
        const rawMedia = String(body.mediaB64 ?? body.imageB64 ?? '')
        let kind: ChatKind = 'text'
        let mediaKey = ''
        let mediaMime = ''
        let mediaSize = 0
        // مدة المقطع تُحفظ مع الرسالة: المشغّل يحتاجها لعرض الطول ورسم
        // موضع الموجة قبل بدء التشغيل، وللتحقق من الحد الأقصى للمدة.
        let mediaSeconds = 0

        // مخطط الموجة اختياري وبلا قيمة أمنية: أرقام تُرسم فقط. نطبيعها
        // بدل رفضها — مقطع قديم أو نسخة لا ترسله يبقى يعمل بمخطط افتراضي.
        // 64 نقطة تكفي لعرض شريط صوتي على الجوال، ونطاق 0..1 يكفي للرسم.
        let waveform = ''
        if (Array.isArray(body.waveform) && body.waveform.length) {
          const pts = body.waveform
            .slice(0, 64)
            .map(v => Math.max(0, Math.min(1, Number(v) || 0)))
          if (pts.length) waveform = pts.map(v => v.toFixed(3)).join(',')
        }

        if (rawMedia) {
          const payload = rawMedia.replace(/^data:[^,]+,/, '')
          const maxBytes = settings.chatMaxMediaMb * 1024 * 1024
          // base64 يضخّم 4/3، فنرفض مبكراً قبل فكّه في الذاكرة.
          if (payload.length > Math.ceil(maxBytes * 4 / 3) + 64) {
            throw new HttpError(413, `الملف كبير (أقصى ${settings.chatMaxMediaMb}MB)`)
          }
          let bytes: Uint8Array
          try {
            bytes = Uint8Array.from(atob(payload), c => c.charCodeAt(0))
          } catch {
            throw new HttpError(400, 'صيغة الملف غير صالحة')
          }
          if (bytes.length > maxBytes) {
            throw new HttpError(413, `الملف كبير (أقصى ${settings.chatMaxMediaMb}MB)`)
          }
          const sig = sniffMedia(bytes)
          if (!sig) throw new HttpError(400, 'نوع الملف غير مدعوم')

          if (sig.kind === 'image') {
            if (!settings.chatImagesEnabled) throw new HttpError(403, 'رفع الصور موقوف')
            // الصور متاحة لكل من يكتب، والمقاطع للمشتركين وحدهم.
            if (bytes.length > 3 * 1024 * 1024) {
              throw new HttpError(413, 'الصورة كبيرة (أقصى 3MB)')
            }
          } else {
            const media = chatMediaAllowed(settings, caller, chatUser)
            if (!media.ok) throw new HttpError(403, media.reason)
            const secs = Math.max(0, Math.floor(Number(body.mediaSeconds) || 0))
            // المدة تُتحقق إن أرسلها التطبيق: الحجم وحده لا يمنع مقطعاً
            // طويلاً بجودة منخفضة، والمدة هي ما يثقل التخزين والبث.
            if (secs > settings.chatMediaSeconds) {
              throw new HttpError(413, `المقطع أطول من ${settings.chatMediaSeconds} ثانية`)
            }
            mediaSeconds = secs
          }

          kind = sig.kind
          mediaMime = sig.mime
          mediaSize = bytes.length
          const id = `chat_${uid()}`
          mediaKey = `chat/${roomId}/${id}.${sig.ext}`
          await env.XMEDIA.put(mediaKey, bytes, { httpMetadata: { contentType: sig.mime } })
          const at = Date.now()
          await env.XDB.prepare(
            `INSERT INTO x_chat_messages
               (id, room_id, user_id, kind, body, media_key, media_mime, media_size, created_at, waveform, media_seconds)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)`
          ).bind(
            id, roomId, chatUser!.id, kind, text, mediaKey, mediaMime, mediaSize, at, waveform, mediaSeconds
          ).run()
          const profiles = await chatProfiles(env.XDB, [chatUser!.id])
          const authorName = profiles.get(chatUser!.id)?.nickname || 'عضو'
          const preview = chatPreview(kind, text, mediaSeconds)
          ctx.waitUntil(pushRoomMessage(
            env, roomId, chatUser!.id, authorName, preview,
          ).catch(() => 0))
          return json({
            ok: true,
            message: chatMessageJson({
              id, room_id: roomId, user_id: chatUser!.id, kind,
              body: text, media_key: mediaKey, media_mime: mediaMime,
              media_size: mediaSize, created_at: at, waveform,
              media_seconds: mediaSeconds,
            }, profiles.get(chatUser!.id), chatUser!.id),
          })
        }

        if (!text) throw new HttpError(400, 'اكتب رسالة أولاً')
        const id = `chat_${uid()}`
        const at = Date.now()
        await env.XDB.prepare(
          `INSERT INTO x_chat_messages
             (id, room_id, user_id, kind, body, media_key, media_mime, media_size, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5, '', '', 0, ?6)`
        ).bind(id, roomId, chatUser!.id, kind, text, at).run()
        const profiles = await chatProfiles(env.XDB, [chatUser!.id])
        const authorName = profiles.get(chatUser!.id)?.nickname || 'عضو'
        ctx.waitUntil(pushRoomMessage(
          env, roomId, chatUser!.id, authorName, chatPreview(kind, text, 0),
        ).catch(() => 0))
        return json({
          ok: true,
          message: chatMessageJson({
            id, room_id: roomId, user_id: chatUser!.id, kind,
            body: text, media_key: '', media_mime: '', media_size: 0, created_at: at,
          }, profiles.get(chatUser!.id), chatUser!.id),
        })
      }

      /**
       * تسجيل رمز جهاز الدفع.
       *
       * يُستدعى كلما أمكن الحصول على رمز (عند الإقلاع، وبعد كل تدوير رمز)
       * والحفظ `INSERT OR REPLACE` لأن الرمز قد ينتقل بين مستخدمين على الجهاز
       * نفسه — تسجيل دخول آخر يملك الرمز، والقديم يجب ألا يبقى مالكاً له.
       */
      if (path === '/v1/push/register' && request.method === 'POST') {
        await rateLimit(env, request, 'chatwrite', 40, 60)
        const body = await request.json() as { token?: string; platform?: string }
        const token = (body.token ?? '').trim()
        // الرمز يأتي من FCM وطوله يتجاوز المئة؛ نرفض القصير الواضح أنه ليس رمزاً
        // بدل تخزين قيم عابثة تُثقل كل إرسال لاحق.
        if (token.length < 20 || token.length > 4096) {
          throw new HttpError(400, 'رمز الدفع غير صالح')
        }
        const meId = chatUser?.id ?? `guest:${caller.uid}`
        await env.XDB.prepare(
          `INSERT INTO x_push_tokens (token, user_id, platform, updated_at)
           VALUES (?1, ?2, ?3, ?4)
           ON CONFLICT(token) DO UPDATE SET
             user_id = excluded.user_id,
             platform = excluded.platform,
             updated_at = excluded.updated_at`
        ).bind(
          token, meId,
          (body.platform ?? 'android').slice(0, 16),
          new Date().toISOString(),
        ).run()
        return json({ ok: true, push: pushEnabled(env) })
      }

      // إلغاء التسجيل عند تسجيل الخروج: بلا هذا يظل الجهاز يستقبل إشعارات
      // حسابٍ لم يعد يستخدمه.
      if (path === '/v1/push/unregister' && request.method === 'POST') {
        await rateLimit(env, request, 'chatwrite', 40, 60)
        const body = await request.json() as { token?: string }
        const token = (body.token ?? '').trim()
        if (token) {
          await env.XDB.prepare('DELETE FROM x_push_tokens WHERE token = ?1')
            .bind(token).run()
        }
        return json({ ok: true })
      }

      // ملف الدردشة: كنية، صورة شخصية، وكتم الإشعارات من جهة المستخدم.
      // الكنية تُنقّى من محارف الاتجاه حتى لا ينتحل أحد اسم غيره بتشكيل بصري.
      if (path === '/v1/chat/profile' && request.method === 'PUT') {
        await rateLimit(env, request, 'chatwrite', 40, 60)
        if (!chatUser) throw new HttpError(403, 'أنشئ حساباً أولاً')
        const body = await request.json<{
          nickname?: string; imageB64?: string; clearAvatar?: boolean; notify?: boolean
        }>().catch(() => ({} as {
          nickname?: string; imageB64?: string; clearAvatar?: boolean; notify?: boolean
        }))

        const nickname = cleanText(body.nickname, 24)
        let avatarKey: string | null = null
        if (body.imageB64) {
          const raw = String(body.imageB64).replace(/^data:[^,]+,/, '')
          if (raw.length > 3 * 1024 * 1024) throw new HttpError(413, 'الصورة كبيرة (أقصى 1.5MB)')
          let bytes: Uint8Array
          try {
            bytes = Uint8Array.from(atob(raw), c => c.charCodeAt(0))
          } catch {
            throw new HttpError(400, 'صيغة الصورة غير صالحة')
          }
          if (bytes.length > 1.5 * 1024 * 1024) throw new HttpError(413, 'الصورة كبيرة (أقصى 1.5MB)')
          const sig = sniffMedia(bytes)
          if (!sig || sig.kind !== 'image') throw new HttpError(400, 'الملف ليس صورة صالحة')
          avatarKey = `chat/avatars/${chatUser.id}.${sig.ext}`
          await env.XMEDIA.put(avatarKey, bytes, { httpMetadata: { contentType: sig.mime } })
        } else if (body.clearAvatar) {
          avatarKey = ''
        }

        const cur = await env.XDB.prepare(
          'SELECT nickname, avatar_key, notify FROM x_chat_profiles WHERE user_id = ?1'
        ).bind(chatUser.id).first<{ nickname: string; avatar_key: string; notify: number }>()

        const nextNick = body.nickname === undefined ? (cur?.nickname ?? '') : nickname
        const nextAvatar = avatarKey === null ? (cur?.avatar_key ?? '') : avatarKey
        const nextNotify = body.notify === undefined
          ? (cur?.notify ?? 1)
          : (body.notify ? 1 : 0)
        await env.XDB.prepare(
          `INSERT INTO x_chat_profiles (user_id, nickname, avatar_key, notify, updated_at)
           VALUES (?1, ?2, ?3, ?4, ?5)
           ON CONFLICT(user_id) DO UPDATE SET
             nickname = excluded.nickname,
             avatar_key = excluded.avatar_key,
             notify = excluded.notify,
             updated_at = excluded.updated_at`
        ).bind(
          chatUser.id, nextNick, nextAvatar, nextNotify, new Date().toISOString()
        ).run()

        return json({
          ok: true,
          nickname: nextNick,
          avatarUrl: nextAvatar ? `/v1/media/${nextAvatar}` : '',
          notify: nextNotify === 1,
        })
      }





      // ---------- وسائط الإعلانات (صور ترفعها اللوحة) ----------

      const mediaMatch = path.match(/^\/v1\/media\/(.+)$/)
      if (mediaMatch && request.method === 'GET') {
        const key = decodeURIComponent(mediaMatch[1])
        if (!/^[\w\-./]{3,200}$/.test(key) || key.includes('..')) throw new HttpError(400, 'bad key')
        const obj = await env.XMEDIA.get(key)
        if (!obj?.body) throw new HttpError(404, 'not found')
        const headers = new Headers()
        obj.writeHttpMetadata(headers)
        // محتوى الدردشة خاص بمستخدمي التطبيق: `private` يمنع أي وسيط مشترك
        // من الاحتفاظ بصور الأعضاء، بخلاف صور الإعلانات التي يجوز كاشها.
        headers.set('cache-control', key.startsWith('chat/')
          ? 'private, max-age=86400'
          : 'public, max-age=86400')
        return new Response(obj.body, { headers })
      }


      // ---------- لوحة المالك ----------

      if (path.startsWith('/v1/owner/')) {
        // جلسة المالك تُتحقق بسرّها المستقل و`typ=owner`، لا بدور داخل جلسة
        // عادية. أي رمز آخر — ولو صحّ توقيعه — لا يفتح اللوحة.
        const ownerToken = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '').trim() ?? ''
        let ownerPayload: Record<string, any>
        try {
          ownerPayload = await verifyOwnerJwt(env, ownerToken)
        } catch {
          await logSecurity(env, request, 'non_owner_admin_attempt', `path=${path}`)
          throw new HttpError(401, 'جلسة المالك غير صالحة')
        }
        if (ownerPayload.sub !== caller.uid) {
          await logSecurity(env, request, 'owner_session_uid_mismatch', `jwt=${ownerPayload.sub} caller=${caller.uid}`)
          throw new HttpError(401, 'جلسة المالك غير صالحة')
        }

        // كل ردود اللوحة مشفّرة بمفتاح مشتق من الجلسة نفسها. استجابة مسرّبة
        // (سجل وسيط، نسخة احتياطية، كاش) تبقى غير مقروءة بلا الجلسة.
        const sealed = async (payload: unknown) =>
          json({ enc: await ownerSeal(ownerToken, payload) }, 200, {
            'cache-control': 'no-store',
            'x-enc': 'aes-gcm'
          })

        if (path === '/v1/owner/overview' && request.method === 'GET') {
          const since = new Date(Date.now() - DAY).toISOString()
          const attacks = ATTACK_REASONS.map(() => '?').join(',')
          const [installs, users, pending, attacksToday, activeToday] = await Promise.all([
            // جهاز فريد: إعادة التثبيت أو تحديث النسخة لا تحتسب هاتفاً جديداً
            env.XDB.prepare(
              "SELECT COUNT(DISTINCT COALESCE(device_id, install_id)) c FROM x_installs"
            ).first<{ c: number }>(),
            env.XDB.prepare("SELECT COUNT(*) c FROM x_users WHERE role != 'owner'").first<{ c: number }>(),
            env.XDB.prepare("SELECT COUNT(*) c FROM x_requests WHERE status = 'pending'").first<{ c: number }>(),
            env.XDB.prepare(
              `SELECT COUNT(*) c FROM x_security WHERE at > ?1 AND reason IN (${attacks})`
            ).bind(since, ...ATTACK_REASONS).first<{ c: number }>(),
            env.XDB.prepare(
              "SELECT COUNT(DISTINCT COALESCE(device_id, install_id)) c FROM x_installs WHERE last_seen > ?1"
            ).bind(since).first<{ c: number }>()
          ])
          const byVersion = await env.XDB.prepare(
            `SELECT app_version v, COUNT(DISTINCT COALESCE(device_id, install_id)) c
             FROM x_installs GROUP BY app_version ORDER BY c DESC`
          ).all<{ v: string; c: number }>()
          return sealed({
            installs: installs?.c ?? 0,
            users: users?.c ?? 0,
            pendingRequests: pending?.c ?? 0,
            securityEvents24h: attacksToday?.c ?? 0,
            activeInstalls24h: activeToday?.c ?? 0,
            installsByVersion: byVersion.results ?? [],
            settings
          })
        }

        if (path === '/v1/owner/settings' && request.method === 'GET') {
          return sealed({ settings })
        }

        if (path === '/v1/owner/settings' && request.method === 'PUT') {
          const body = await request.json() as Partial<XSettings>
          const next: XSettings = {
            // المنحة اليومية الواحدة: تُطبَّق على الزوار والمسجّلين والمشتركين.
            // الحقلان القديمان يُشتقّان منها ويُحفظان بنفس القيمة كي لا تظن
            // نسخة قديمة من التطبيق أن المالك ألغى المنحة.
            dailyFreeQuota: Math.max(0, Math.min(1000, Math.floor(Number(body.dailyFreeQuota ?? settings.dailyFreeQuota) || 0))),
            guestFileQuota: 0,
            minVersion: Math.max(0, Number(body.minVersion ?? settings.minVersion) || 0),
            blockedVersions: Array.isArray(body.blockedVersions)
              ? body.blockedVersions.map(Number).filter(Number.isSafeInteger) : settings.blockedVersions,
            telegramLink: typeof body.telegramLink === 'string' && /^https?:\/\//.test(body.telegramLink)
              ? body.telegramLink.trim() : settings.telegramLink,
            schematicsLocked: body.schematicsLocked ?? settings.schematicsLocked,
            compatLocked: body.compatLocked ?? settings.compatLocked,
            compatSearchCost: Math.max(0, Math.min(1000, Math.floor(Number(body.compatSearchCost ?? settings.compatSearchCost) || 0))),
            guestCompatQuota: 0,
            appLocked: body.appLocked ?? settings.appLocked,
            lockMessage: typeof body.lockMessage === 'string' ? body.lockMessage.slice(0, 300) : settings.lockMessage,
            updateMessage: typeof body.updateMessage === 'string' ? body.updateMessage.slice(0, 500) : settings.updateMessage,
            updateUrl: typeof body.updateUrl === 'string' && (!body.updateUrl || /^https?:\/\//.test(body.updateUrl))
              ? body.updateUrl.trim() : settings.updateUrl,
            updateImageUrl: typeof body.updateImageUrl === 'string' ? body.updateImageUrl.slice(0, 500) : settings.updateImageUrl,
            // باقات البطاقات — تحقق صارم: عدد بطاقات وصلاحية وسعر ووصف
            packages: Array.isArray(body.packages)
              ? body.packages
                  .map(p => ({
                    // بلا Math.max(1,...): كان يرفع الصفر إلى واحد فيمرّ من
                    // المرشّح أدناه باقةٌ بلا بطاقات.
                    cards: Math.min(1000000, Math.max(0, Math.floor(Number(p?.cards) || 0))),
                    price: String(p?.price ?? '').slice(0, 30),
                    days: Math.max(0, Math.min(3650, Math.floor(Number(p?.days) || 0))),
                    desc: String(p?.desc ?? '').slice(0, 120),
                  }))
                  .filter(p => p.cards > 0)
                  .slice(0, 20)
              : settings.packages,
            // سياسة الخصوصية: نص طويل، نحدّه بـ 8000 حرف ونحفظه كما هو.
            // لا نُجري أي تفسير HTML — التطبيق يعرضه نصاً خاماً.
            privacyPolicy: typeof body.privacyPolicy === 'string'
              ? body.privacyPolicy.slice(0, 8000) : settings.privacyPolicy,

            // ── الدردشة: كل حقل يُتحقق ويُحدّ، والمفقود يبقى على قيمته ──
            chatEnabled: body.chatEnabled ?? settings.chatEnabled,
            chatReadOnly: body.chatReadOnly ?? settings.chatReadOnly,
            chatTheme: ['classic', 'bubble', 'dark', 'neon'].includes(String(body.chatTheme))
              ? String(body.chatTheme) : settings.chatTheme,
            chatWelcome: typeof body.chatWelcome === 'string'
              ? body.chatWelcome.slice(0, 300) : settings.chatWelcome,
            chatMaxLength: Math.max(80, Math.min(4000,
              Math.floor(Number(body.chatMaxLength ?? settings.chatMaxLength) || 1000))),
            chatImagesEnabled: body.chatImagesEnabled ?? settings.chatImagesEnabled,
            chatWriteScope: ['all', 'registered', 'subscribers'].includes(String(body.chatWriteScope))
              ? String(body.chatWriteScope) : settings.chatWriteScope,
            chatMediaScope: ['subscribers', 'none'].includes(String(body.chatMediaScope))
              ? String(body.chatMediaScope) : settings.chatMediaScope,
            chatMaxMediaMb: Math.max(1, Math.min(25,
              Math.floor(Number(body.chatMaxMediaMb ?? settings.chatMaxMediaMb) || 12))),
            chatMediaSeconds: Math.max(5, Math.min(300,
              Math.floor(Number(body.chatMediaSeconds ?? settings.chatMediaSeconds) || 120))),
            chatPollMs: Math.max(2000, Math.min(30000,
              Math.floor(Number(body.chatPollMs ?? settings.chatPollMs) || 4000))),
            // الأقسام تُطبَّع بنفس منطق القراءة، فلا يكتب المالك قائمة
            // معرّفات مكررة أو فارغة تُربك الفرز لاحقاً.
            chatRooms: Array.isArray(body.chatRooms) ? normalizeSettings({
              ...DEFAULT_SETTINGS, chatRooms: body.chatRooms,
            }, { chatRooms: body.chatRooms }).chatRooms : settings.chatRooms,
          }
          await env.XDB.prepare(
            `INSERT INTO x_settings (id, data) VALUES ('main', ?1)
             ON CONFLICT(id) DO UPDATE SET data = ?1`
          ).bind(JSON.stringify(next)).run()
          return sealed({ ok: true, settings: next })
        }

        if (path === '/v1/owner/users' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            "SELECT id, username, display_name, role, active, device_id, expires_at, quota_balance, quota_expires_at, created_at FROM x_users WHERE role != 'guest' ORDER BY created_at DESC LIMIT 500"
          ).all()
          return sealed({ users: rows.results ?? [] })
        }

        // إنشاء حساب مفعّل مباشرة — المالك يضيف مشتركين بنفسه
        if (path === '/v1/owner/users' && request.method === 'POST') {
          const body = await request.json() as {
            username?: string; password?: string; displayName?: string
            days?: number; cards?: number; cardDays?: number
          }
          const username = body.username?.trim() ?? ''
          if (!/^[\w.\-@]{3,60}$/.test(username)) throw new HttpError(400, 'اسم مستخدم غير صالح')
          if ((body.password ?? '').length < 6) throw new HttpError(400, 'كلمة المرور قصيرة')
          if (await xUserByName(env.XDB, username)) throw new HttpError(409, 'اسم المستخدم مستخدم')
          const days = Math.max(0, Math.min(3650, Number(body.days) || 0))
          const cards = Math.max(0, Math.min(100000, Math.floor(Number(body.cards) || 0)))
          const cardDays = Math.max(0, Math.min(3650, Number(body.cardDays) || 0))
          await env.XDB.prepare(
            `INSERT INTO x_users (id, username, display_name, password_hash, role, active, device_id, expires_at, quota_balance, quota_expires_at, created_at)
             VALUES (?1, ?2, ?3, ?4, 'user', 1, NULL, ?5, ?6, ?7, ?8)`
          ).bind(
            `u_${uid()}`, username, body.displayName?.trim() ?? '',
            await hashPassword(body.password!),
            days > 0 ? Date.now() + days * DAY * 1000 : 0,
            cards,
            cardDays > 0 ? Date.now() + cardDays * DAY * 1000 : 0,
            new Date().toISOString()
          ).run()
          return sealed({ ok: true })
        }

        // محافظ الزوار: عملات يشتريها الزائر بلا حساب، مفتاحها معرّف الجهاز.
        if (path === '/v1/owner/wallets' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            `SELECT w.device_id, w.balance, w.expires_at, w.updated_at,
                    (SELECT app_version FROM x_installs i
                      WHERE i.device_id = w.device_id
                      ORDER BY last_seen DESC LIMIT 1) app_version,
                    (SELECT last_ip FROM x_installs i
                      WHERE i.device_id = w.device_id
                      ORDER BY last_seen DESC LIMIT 1) last_ip,
                    (SELECT last_seen FROM x_installs i
                      WHERE i.device_id = w.device_id
                      ORDER BY last_seen DESC LIMIT 1) last_seen,
                    (SELECT username FROM x_users u
                      WHERE u.device_id = w.device_id LIMIT 1) username,
                    (SELECT id FROM x_users u
                      WHERE u.device_id = w.device_id LIMIT 1) user_id
             FROM x_guest_wallets w ORDER BY w.updated_at DESC LIMIT 500`
          ).all()
          return sealed({ wallets: rows.results ?? [] })
        }

        // تعديل مباشر: تعيين الرصيد والصلاحية إلى قيم محددة (لا جمع).
        if (path === '/v1/owner/wallets' && request.method === 'PUT') {
          const body = await request.json() as {
            deviceId?: string; coins?: number; days?: number
          }
          const dev = body.deviceId?.trim() ?? ''
          if (!dev || dev.length > 100) throw new HttpError(400, 'معرّف الجهاز مطلوب')
          const coins = Math.max(0, Math.min(1000000, Math.floor(Number(body.coins) || 0)))
          const days = Math.max(0, Math.min(3650, Math.floor(Number(body.days) || 0)))
          const now = new Date().toISOString()
          const existing = await env.XDB.prepare(
            'SELECT device_id FROM x_guest_wallets WHERE device_id = ?1'
          ).bind(dev).first<{ device_id: string }>()
          if (!existing) throw new HttpError(404, 'المحفظة غير موجودة')
          await env.XDB.prepare(
            `UPDATE x_guest_wallets SET balance = ?2, expires_at = ?3, updated_at = ?4
             WHERE device_id = ?1`
          ).bind(dev, coins, days > 0 ? Date.now() + days * DAY * 1000 : 0, now).run()
          return sealed({ ok: true, deviceId: dev, coins, days })
        }

        // حذف محفظة بالكامل.
        const walletDelete = path.match(/^\/v1\/owner\/wallets\/(.+)$/)
        if (walletDelete && request.method === 'DELETE') {
          const dev = decodeURIComponent(walletDelete[1]).trim()
          if (!dev) throw new HttpError(400, 'معرّف الجهاز مطلوب')
          await env.XDB.prepare('DELETE FROM x_guest_wallets WHERE device_id = ?1').bind(dev).run()
          return sealed({ ok: true, deleted: dev })
        }

        // إنقاص أو إضافة بجرعة: جمع/طرح لا تعيين. الرصيد لا ينزل تحت الصفر.
        if (path === '/v1/owner/wallets/adjust' && request.method === 'POST') {
          const body = await request.json() as {
            deviceId?: string; delta?: number; days?: number
          }
          const dev = body.deviceId?.trim() ?? ''
          if (!dev || dev.length > 100) throw new HttpError(400, 'معرّف الجهاز مطلوب')
          const delta = Math.max(-1000000, Math.min(1000000, Math.floor(Number(body.delta) || 0)))
          if (delta === 0) throw new HttpError(400, 'قيمة التعديل مطلوبة')
          const days = Math.max(0, Math.min(3650, Math.floor(Number(body.days) || 0)))
          const now = new Date().toISOString()
          const existing = await env.XDB.prepare(
            'SELECT balance FROM x_guest_wallets WHERE device_id = ?1'
          ).bind(dev).first<{ balance: number }>()
          if (!existing) throw new HttpError(404, 'المحفظة غير موجودة')
          const current = Math.max(0, Number(existing.balance) || 0)
          const next = Math.max(0, current + delta)
          if (days > 0) {
            await env.XDB.prepare(
              `UPDATE x_guest_wallets SET balance = ?2, expires_at = ?3, updated_at = ?4
               WHERE device_id = ?1`
            ).bind(dev, next, Date.now() + days * DAY * 1000, now).run()
          } else {
            await env.XDB.prepare(
              `UPDATE x_guest_wallets SET balance = ?2, updated_at = ?3 WHERE device_id = ?1`
            ).bind(dev, next, now).run()
          }
          return sealed({ ok: true, deviceId: dev, before: current, after: next })
        }

        if (path === '/v1/owner/wallets' && request.method === 'POST') {
          const body = await request.json() as {
            deviceId?: string; coins?: number; days?: number
          }
          const dev = body.deviceId?.trim() ?? ''
          if (!dev || dev.length > 100) throw new HttpError(400, 'معرّف الجهاز مطلوب')
          const coins = Math.max(0, Math.min(1000000, Math.floor(Number(body.coins) || 0)))
          const days = Math.max(0, Math.min(3650, Math.floor(Number(body.days) || 0)))
          if (coins <= 0) throw new HttpError(400, 'عدد العملات مطلوب')
          const now = new Date().toISOString()
          // شحن تراكمي: إعادة الشحن تضيف للرصيد ولا تُصفّره.
          await env.XDB.prepare(
            `INSERT INTO x_guest_wallets (device_id, balance, expires_at, created_at, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?4)
             ON CONFLICT(device_id) DO UPDATE SET
               balance = balance + ?2,
               expires_at = ?3,
               updated_at = ?4`
          ).bind(dev, coins, days > 0 ? Date.now() + days * DAY * 1000 : 0, now).run()
          return sealed({ ok: true })
        }

        // حظر الأجهزة: عرض/حظر/فك
        // القائمة تُثري كل حظر بتفاصيله: من هو صاحبه إن كان له حساب، ومعرّفه،
        // وعنوان IP الذي هاجم منه، وآخر نسخة/IP معروفة للجهاز، وسبب الحظر،
        // وسجل الهجمات المرتبط. الحظر بلا تفاصيل لا يفيد المالك في القرار.
        if (path === '/v1/owner/bans' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            'SELECT * FROM x_bans ORDER BY at DESC LIMIT 300'
          ).all<{ id: string; kind: string; reason: string; permanent: number; at: string }>()

          const bans = await Promise.all((rows.results ?? []).map(async b => {
            const isDevice = b.kind === 'device'
            const dev = isDevice ? b.id : null
            // الحساب المرتبط بالجهاز المحظور — بالمعرّف أو بالمعرّف المربوط
            const account = dev
              ? await env.XDB.prepare(
                  'SELECT id, username, display_name, role, active, device_id FROM x_users WHERE device_id = ?1 LIMIT 1'
                ).bind(dev).first<any>()
              : null
            // آخر ظهور للجهاز: يمنح المالك النسخة والعنوان الأخير
            const install = dev
              ? await env.XDB.prepare(
                  `SELECT app_version, last_ip, last_seen, first_seen FROM x_installs
                   WHERE device_id = ?1 ORDER BY last_seen DESC LIMIT 1`
                ).bind(dev).first<any>()
              : null
            // آخر الأحداث الأمنية: السبب الحقيقي للحظر (هجوم، عبث، تجاوز)
            const events = await env.XDB.prepare(
              `SELECT reason, detail, path, ip, device_id, at FROM x_security
               WHERE (device_id IS NOT NULL AND device_id = ?1)
                  OR (ip IS NOT NULL AND ip = ?2)
               ORDER BY at DESC LIMIT 10`
            ).bind(dev ?? '\u0000', isDevice ? '\u0000' : b.id).all<any>()
            const ips = [...new Set((events.results ?? []).map((e: any) => e.ip).filter(Boolean))]
            return {
              id: b.id,
              kind: b.kind,
              reason: b.reason,
              permanent: b.permanent,
              at: b.at,
              account: account ?? null,
              appVersion: install?.app_version ?? '',
              lastIp: install?.last_ip ?? (isDevice ? '' : b.id),
              lastSeen: install?.last_seen ?? '',
              firstSeen: install?.first_seen ?? '',
              ips,
              events: events.results ?? []
            }
          }))
          return sealed({ bans })
        }
        if (path === '/v1/owner/bans' && request.method === 'POST') {
          const body = await request.json() as {
            deviceId?: string; ip?: string; reason?: string
          }
          const reason = body.reason?.trim() || 'manual'
          const dev = body.deviceId?.trim() ?? ''
          const addr = body.ip?.trim() ?? ''
          if (!dev && !addr) throw new HttpError(400, 'deviceId أو ip مطلوب')
          if (dev.length > 100 || addr.length > 64) throw new HttpError(400, 'قيمة طويلة جداً')
          // لا تحظر نفسك: زر الحظر في تبويب الأمان يعرض جهاز المالك وعنوانه
          // أيضاً، ونقرة واحدة كانت تكفي لقفل التطبيق على المالك نفسه بلا
          // أي طريق للرجوع من داخل التطبيق.
          const selfDev = deviceOf(request)
          const selfAddr = ip(request)
          if (dev && selfDev && dev === selfDev) {
            throw new HttpError(400, 'لا يمكنك حظر جهازك الحالي')
          }
          if (addr && selfAddr !== 'unknown' && addr === selfAddr) {
            throw new HttpError(400, 'لا يمكنك حظر عنوانك الحالي')
          }
          if (dev) await banDevice(env, dev, reason, request)
          if (addr) await banIp(env, addr, reason, request)
          return sealed({ ok: true })
        }
        const unban = path.match(/^\/v1\/owner\/bans\/(.+)$/)
        if (unban && request.method === 'DELETE') {
          const target = decodeURIComponent(unban[1])
          // الهدف قد يكون جهازاً أو عنوان IP — ننظّف المفتاحين معاً.
          await Promise.all([
            env.QUOTA.delete(`devban:${target}`),
            env.QUOTA.delete(`hardban:${target}`)
          ])
          await env.XDB.prepare('DELETE FROM x_bans WHERE id = ?1').bind(target).run()
          return sealed({ ok: true })
        }

        const userAction = path.match(/^\/v1\/owner\/users\/([\w-]+)\/(activate|deactivate|reset-device|delete|extend|quota)$/)
        if (userAction && request.method === 'POST') {
          const [, targetId, action] = userAction
          const target = await xUser(env.XDB, targetId)
          if (!target) throw new HttpError(404, 'user not found')
          if (target.role === 'owner') throw new HttpError(400, 'cannot modify owner')
          if (action === 'activate') {
            await env.XDB.prepare('UPDATE x_users SET active = 1 WHERE id = ?1').bind(targetId).run()
            await env.XDB.prepare("UPDATE x_requests SET status = 'approved' WHERE username = ?1 AND status = 'pending'").bind(target.username).run()
          } else if (action === 'deactivate') {
            await env.XDB.prepare('UPDATE x_users SET active = 0 WHERE id = ?1').bind(targetId).run()
          } else if (action === 'reset-device') {
            await env.XDB.prepare('UPDATE x_users SET device_id = NULL WHERE id = ?1').bind(targetId).run()
          } else if (action === 'extend') {
            const body = await request.json() as { days?: number }
            const days = Math.max(1, Math.min(3650, Number(body.days) || 30))
            await env.XDB.prepare('UPDATE x_users SET expires_at = ?1 WHERE id = ?2')
              .bind(Date.now() + days * DAY * 1000, targetId).run()
          } else if (action === 'quota') {
            // شحن بطاقات: يضيف للرصيد ويحدد صلاحية جديدة — كل الحسابات في السيرفر فقط
            const body = await request.json() as { cards?: number; days?: number }
            const cards = Math.max(0, Math.min(100000, Math.floor(Number(body.cards) || 0)))
            const days = Math.max(0, Math.min(3650, Number(body.days) || 0))
            if (cards <= 0) throw new HttpError(400, 'عدد البطاقات مطلوب')
            await env.XDB.prepare(
              `UPDATE x_users SET
                 quota_balance = quota_balance + ?2,
                 quota_expires_at = ?3
               WHERE id = ?1`
            ).bind(targetId, cards, days > 0 ? Date.now() + days * DAY * 1000 : 0).run()
          } else if (action === 'delete') {
            await env.XDB.prepare('DELETE FROM x_users WHERE id = ?1').bind(targetId).run()
          }
          return sealed({ ok: true })
        }

        if (path === '/v1/owner/requests' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            "SELECT * FROM x_requests ORDER BY created_at DESC LIMIT 200"
          ).all()
          return sealed({ requests: rows.results ?? [] })
        }

        const reqAction = path.match(/^\/v1\/owner\/requests\/([\w-]+)\/(approve|reject)$/)
        if (reqAction && request.method === 'POST') {
          const [, reqId, action] = reqAction
          const req = await env.XDB.prepare('SELECT * FROM x_requests WHERE id = ?1').bind(reqId).first<{ username: string }>()
          if (!req) throw new HttpError(404, 'request not found')
          const status = action === 'approve' ? 'approved' : 'rejected'
          await env.XDB.batch([
            env.XDB.prepare('UPDATE x_requests SET status = ?1 WHERE id = ?2').bind(status, reqId),
            ...(action === 'approve'
              ? [env.XDB.prepare('UPDATE x_users SET active = 1 WHERE username = ?1').bind(req.username)]
              : [])
          ])
          return sealed({ ok: true })
        }

        // سجل الأمان: المشبوه افتراضياً، والكل عند طلبه صراحة.
        // العرض الافتراضي يقتصر على ما يستحق نظرة المالك — هجوم أو تزوير أو
        // عبث — لا كل حدث روتيني. `all=1` يكشف السجل الكامل عند الحاجة.
        if (path === '/v1/owner/security' && request.method === 'GET') {
          const all = url.searchParams.get('all') === '1'
          const marks = SUSPICIOUS_REASONS.map(() => '?').join(',')
          const rows = all
            ? await env.XDB.prepare('SELECT * FROM x_security ORDER BY at DESC LIMIT 300').all()
            : await env.XDB.prepare(
                `SELECT * FROM x_security WHERE reason IN (${marks}) ORDER BY at DESC LIMIT 300`
              ).bind(...SUSPICIOUS_REASONS).all()
          // ملخّص بالنوع يمنح المالك صورة سريعة قبل التفاصيل.
          const byReason = await env.XDB.prepare(
            `SELECT reason, COUNT(*) c, MAX(at) last FROM x_security
             WHERE reason IN (${marks}) GROUP BY reason ORDER BY c DESC`
          ).bind(...SUSPICIOUS_REASONS).all()
          return sealed({
            events: rows.results ?? [],
            attacksOnly: !all,
            summary: byReason.results ?? []
          })
        }

        // حذف سجلات الأمان: الكل، أو نوع واحد، أو ما قبل تاريخ.
        // السجل ينمو بلا حد عملياً، وتركه للقارئ وحده يجعله عديم الفائدة.
        // محميّ بنفس بوابة جلسة المالك لكل مسارات /v1/owner/*.
        if (path === '/v1/owner/security' && request.method === 'DELETE') {
          const reason = url.searchParams.get('reason')?.trim() ?? ''
          const before = Number(url.searchParams.get('before')) || 0
          let deleted = 0
          if (reason) {
            const r = await env.XDB.prepare(
              'DELETE FROM x_security WHERE reason = ?1'
            ).bind(reason).run()
            deleted = Number(r.meta?.changes ?? 0)
          } else if (before > 0) {
            const r = await env.XDB.prepare(
              'DELETE FROM x_security WHERE at < ?1'
            ).bind(new Date(before).toISOString()).run()
            deleted = Number(r.meta?.changes ?? 0)
          } else {
            const r = await env.XDB.prepare('DELETE FROM x_security').run()
            deleted = Number(r.meta?.changes ?? 0)
          }
          await logSecurity(env, request, 'security_logs_cleared')
          return sealed({ ok: true, deleted })
        }

        if (path === '/v1/owner/announcements' && request.method === 'GET') {
          const rows = await env.XDB.prepare('SELECT id, data FROM x_announcements ORDER BY id DESC LIMIT 100').all<{ id: string; data: string }>()
          return sealed({
            announcements: (rows.results ?? []).map(r => ({ id: r.id, ...JSON.parse(r.data) }))
          })
        }

        // إنشاء إعلان — يقبل صورة base64 تُرفع لـ bucket الخاص بـ X
        if (path === '/v1/owner/announcements' && request.method === 'POST') {
          const body = await request.json() as {
            title?: string; subtitle?: string; linkUrl?: string; imageUrl?: string
            imageB64?: string; imageExt?: string
          }
          if (!body.title?.trim()) throw new HttpError(400, 'title required')
          const id = `xann_${uid()}`
          let imageUrl = body.imageUrl?.trim() ?? ''
          if (body.imageB64) {
            const ext = (body.imageExt ?? 'png').replace(/[^\w]/g, '').slice(0, 5) || 'png'
            const bytes = Uint8Array.from(atob(body.imageB64), c => c.charCodeAt(0))
            if (bytes.length > 4 * 1024 * 1024) throw new HttpError(413, 'الصورة كبيرة (أقصى 4MB)')
            const key = `ads/${id}.${ext}`
            const mime = EXT_MIME[ext] ?? 'image/png'
            await env.XMEDIA.put(key, bytes, { httpMetadata: { contentType: mime } })
            imageUrl = `/v1/media/${key}`
          }
          await env.XDB.prepare(
            'INSERT INTO x_announcements (id, data) VALUES (?1, ?2)'
          ).bind(id, JSON.stringify({
            title: body.title.trim(), subtitle: body.subtitle?.trim() ?? '',
            linkUrl: body.linkUrl?.trim() ?? '', imageUrl,
            active: true, order: Date.now(), createdAt: new Date().toISOString()
          })).run()
          // الإعلان يهمّ كل مستخدمي التطبيق، فهو الدفع الوحيد العام.
          // بلا انتظار: نشر الإعلان يجب أن يعود فوراً ولو حمّل الإرسال ثواني.
          ctx.waitUntil(pushToAll(env, {
            title: body.title.trim(),
            body: body.subtitle?.trim() || 'إعلان جديد من MAPX',
            target: { k: 'ad' },
          }).catch(() => 0))
          return sealed({ ok: true, id, imageUrl, pushed: pushEnabled(env) })
        }

        const annDelete = path.match(/^\/v1\/owner\/announcements\/([\w-]+)$/)
        if (annDelete && request.method === 'DELETE') {
          await env.XDB.prepare('DELETE FROM x_announcements WHERE id = ?1').bind(annDelete[1]).run()
          return sealed({ ok: true })
        }

        // ---------- إشراف المالك على الدردشة ----------

        // آخر الرسائل في كل قسم — للمراجعة والحذف.
        if (path === '/v1/owner/chat/messages' && request.method === 'GET') {
          const roomId = url.searchParams.get('room') ?? ''
          const rows = roomId
            ? await env.XDB.prepare(
                `SELECT id, room_id, user_id, kind, body, media_key, media_mime,
                        media_size, created_at, deleted
                 FROM x_chat_messages WHERE room_id = ?1
                 ORDER BY created_at DESC LIMIT 100`
              ).bind(roomId).all<any>()
            : await env.XDB.prepare(
                `SELECT id, room_id, user_id, kind, body, media_key, media_mime,
                        media_size, created_at, deleted
                 FROM x_chat_messages ORDER BY created_at DESC LIMIT 100`
              ).all<any>()
          const list = rows.results ?? []
          const profiles = await chatProfiles(env.XDB, list.map(m => m.user_id))
          const users = new Map<string, string>()
          if (list.length) {
            const ids = [...new Set(list.map(m => m.user_id))]
            const ph = ids.map((_, i) => `?${i + 1}`).join(',')
            const ur = await env.XDB.prepare(
              `SELECT id, username, display_name FROM x_users WHERE id IN (${ph})`
            ).bind(...ids).all<{ id: string; username: string; display_name: string }>()
            for (const u of ur.results ?? []) users.set(u.id, u.display_name || u.username)
          }
          return sealed({
            messages: list.map(m => ({
              id: m.id, roomId: m.room_id, kind: m.kind, body: m.body,
              mediaUrl: m.media_key ? `/v1/media/${m.media_key}` : '',
              mediaMime: m.media_mime, mediaSize: m.media_size,
              at: m.created_at, deleted: !!m.deleted,
              userId: m.user_id,
              username: users.get(m.user_id) ?? '',
              nickname: profiles.get(m.user_id)?.nickname ?? '',
              avatarUrl: profiles.get(m.user_id)?.avatar_key
                ? `/v1/media/${profiles.get(m.user_id)!.avatar_key}` : '',
            })),
          })
        }

        // حذف رسالة: ناعم، فلا يفقد الحوار سياقه ويبقى الأثر للمالك.
        const chatMsgDelete = path.match(/^\/v1\/owner\/chat\/messages\/([\w-]+)$/)
        if (chatMsgDelete && request.method === 'DELETE') {
          await env.XDB.prepare(
            'UPDATE x_chat_messages SET deleted = 1 WHERE id = ?1'
          ).bind(chatMsgDelete[1]).run()
          await logSecurity(env, request, 'owner_chat_delete', `msg=${chatMsgDelete[1]}`)
          return sealed({ ok: true })
        }

        // حذف كل رسائل قسم — يستخدمه المالك عند تنظيف قسم من الفوضى.
        if (path === '/v1/owner/chat/purge' && request.method === 'POST') {
          const body = await request.json<{ room?: string }>().catch(() => ({} as { room?: string }))
          const roomId = String(body.room ?? '')
          if (!roomId) throw new HttpError(400, 'room required')
          await env.XDB.prepare(
            'UPDATE x_chat_messages SET deleted = 1 WHERE room_id = ?1'
          ).bind(roomId).run()
          await logSecurity(env, request, 'owner_chat_purge', `room=${roomId}`)
          return sealed({ ok: true })
        }

        // كتم/طرد: room فارغ = كل الأقسام. الكتم بلا نهاية (until=0)،
        // والطرد بمدة محددة لأن الطرد الدائم بلا سبب يقطع المستخدم عن
        // المجتمع كلياً — والمالك يستطيع تكراره إن لزم.
        if (path === '/v1/owner/chat/action' && request.method === 'POST') {
          const body = await request.json<{
            userId?: string; kind?: string; room?: string
            reason?: string; minutes?: number
          }>().catch(() => ({} as {
            userId?: string; kind?: string; room?: string
            reason?: string; minutes?: number
          }))
          const userId = String(body.userId ?? '')
          const kind = String(body.kind ?? '')
          if (!userId || !['mute', 'kick'].includes(kind)) {
            throw new HttpError(400, 'userId و kind (mute|kick) مطلوبان')
          }
          const roomId = String(body.room ?? '')
          if (roomId && !settings.chatRooms.some(r => r.id === roomId)) {
            throw new HttpError(404, 'القسم غير موجود')
          }
          const target = await xUser(env.XDB, userId)
          if (!target) throw new HttpError(404, 'المستخدم غير موجود')
          if (target.role === 'owner') throw new HttpError(400, 'لا يمكن تقييد المالك')

          // minutes = 0 تعني «دائم» للنوعين. الطرد الدائم قد يبدو حظراً،
          // لكنه يبقى داخل الدردشة وحدها ولا يمس دخول التطبيق.
          const minutes = Math.max(0, Math.min(43200, Math.floor(Number(body.minutes) || 0)))
          const until = minutes > 0 ? Date.now() + minutes * 60000 : 0
          const id = `cact_${uid()}`
          await env.XDB.prepare(
            `INSERT INTO x_chat_actions (id, user_id, kind, room_id, reason, until, at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)`
          ).bind(
            id, userId, kind, roomId,
            cleanText(body.reason, 120), until, new Date().toISOString()
          ).run()
          await logSecurity(env, request, `owner_chat_${kind}`,
            `user=${userId} room=${roomId || 'all'} until=${until}`)
          return sealed({ ok: true, id, until })
        }

        // رفع التقييد عن مستخدم.
        if (path === '/v1/owner/chat/action/clear' && request.method === 'POST') {
          const body = await request.json<{
            userId?: string; kind?: string
          }>().catch(() => ({} as { userId?: string; kind?: string }))
          const userId = String(body.userId ?? '')
          if (!userId) throw new HttpError(400, 'userId required')
          const kind = String(body.kind ?? '')
          if (kind && ['mute', 'kick'].includes(kind)) {
            await env.XDB.prepare(
              'DELETE FROM x_chat_actions WHERE user_id = ?1 AND kind = ?2'
            ).bind(userId, kind).run()
          } else {
            await env.XDB.prepare(
              'DELETE FROM x_chat_actions WHERE user_id = ?1'
            ).bind(userId).run()
          }
          await logSecurity(env, request, 'owner_chat_clear', `user=${userId} kind=${kind || 'all'}`)
          return sealed({ ok: true })
        }

        // قائمة المكتومين والمطرودين — لمتابعة من أوقفه المالك.
        if (path === '/v1/owner/chat/actions' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            `SELECT id, user_id, kind, room_id, reason, until, at
             FROM x_chat_actions ORDER BY at DESC LIMIT 200`
          ).all<any>()
          const list = rows.results ?? []
          const ids = [...new Set(list.map(r => r.user_id))]
          const names = new Map<string, string>()
          if (ids.length) {
            const ph = ids.map((_, i) => `?${i + 1}`).join(',')
            const ur = await env.XDB.prepare(
              `SELECT id, username, display_name FROM x_users WHERE id IN (${ph})`
            ).bind(...ids).all<{ id: string; username: string; display_name: string }>()
            for (const u of ur.results ?? []) names.set(u.id, u.display_name || u.username)
          }
          const now = Date.now()
          return sealed({
            actions: list.map(r => ({
              id: r.id, userId: r.user_id, kind: r.kind, roomId: r.room_id,
              reason: r.reason, until: r.until, at: r.at,
              username: names.get(r.user_id) ?? '',
              // منتهي = لا يزال الصف لكن أثره زال. until === 0 يعني بلا نهاية.
              active: r.until === 0 || r.until > now,
            })),
          })
        }
      }

      throw new HttpError(404, 'not found')
    } catch (err) {
      if (err instanceof HttpError) {
        return json({ ok: false, error: err.message, status: err.status }, err.status)
      }
      return json({ ok: false, error: 'server error' }, 500)
    }
  }
}
