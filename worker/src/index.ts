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
  X_FILE_KEY: string
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
  active: number; device_id: string | null; expires_at: number
}

async function xUser(XDB: D1Database, id: string): Promise<XUser | null> {
  return XDB.prepare('SELECT * FROM x_users WHERE id = ?1').bind(id).first<XUser>()
}

async function xUserByName(XDB: D1Database, username: string): Promise<XUser | null> {
  return XDB.prepare('SELECT * FROM x_users WHERE username = ?1 COLLATE NOCASE').bind(username).first<XUser>()
}

interface XSettings {
  guestFileQuota: number          // عدد الملفات التي يفتحها الزائر يومياً
  minVersion: number              // أدنى إصدار مسموح
  blockedVersions: number[]       // إصدارات موقوفة تحديداً
  telegramLink: string
  schematicsLocked: boolean       // قفل المخططات كلياً عن الزوار
  compatLocked: boolean           // قفل التوافقات عن الزوار
  appLocked: boolean              // قفل التطبيق كلياً (صيانة)
  lockMessage: string
  updateMessage: string           // رسالة شاشة التحديث الإجباري
  updateUrl: string               // رابط زر التحديث
  updateImageUrl: string          // صورة شاشة التحديث
}

const DEFAULT_SETTINGS: XSettings = {
  guestFileQuota: 5,
  minVersion: 1,
  blockedVersions: [],
  telegramLink: 'https://t.me/phonex6',
  schematicsLocked: false,
  compatLocked: false,
  appLocked: false,
  lockMessage: '',
  updateMessage: 'يتوفر إصدار جديد — حدّث التطبيق للمتابعة',
  updateUrl: '',
  updateImageUrl: ''
}

async function xSettings(XDB: D1Database): Promise<XSettings> {
  const row = await XDB.prepare("SELECT data FROM x_settings WHERE id = 'main'").first<{ data: string }>()
  if (!row) return { ...DEFAULT_SETTINGS }
  try { return { ...DEFAULT_SETTINGS, ...JSON.parse(row.data) } } catch { return { ...DEFAULT_SETTINGS } }
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

async function noteAbuse(env: Env, request: Request, reason: string): Promise<void> {
  const addr = ip(request)
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
      if (count + 1 >= 20) {
        const hard = await env.QUOTA.get(`hardban:${addr}`)
        await env.QUOTA.put(`hardban:${addr}`, 'repeat', { expirationTtl: hard ? DAY : 3600 })
        await logSecurity(env, request, 'ip_hardban', `reason=${reason} strikes=${count + 1}`)
      }
    }
  } catch { /* ignore */ }
}

/** حظر جهاز نهائي — لا يفيده تغيير IP أو بروكسي أو حساب جديد */
async function banDevice(env: Env, deviceId: string, reason: string, request?: Request): Promise<void> {
  await env.QUOTA.put(`devban:${deviceId}`, 'perm') // بلا انتهاء
  await env.XDB.prepare(
    `INSERT INTO x_bans (id, kind, reason, permanent, at) VALUES (?1, 'device', ?2, 1, ?3)
     ON CONFLICT(id) DO NOTHING`
  ).bind(deviceId, reason, new Date().toISOString()).run()
  if (request) await logSecurity(env, request, 'device_banned', reason)
}

/** فحص حظر الجهاز — يعمل على كل طلب /v1/ قبل أي شيء آخر */
async function assertDeviceAllowed(env: Env, request: Request): Promise<void> {
  const dev = deviceOf(request)
  if (!dev) return
  if (await env.QUOTA.get(`devban:${dev}`)) {
    await logSecurity(env, request, 'banned_device_hit')
    throw new HttpError(403, 'تم حظر هذا الجهاز نهائياً — تواصل مع الدعم')
  }
}

async function assertIpClean(env: Env, request: Request): Promise<void> {
  const addr = ip(request)
  if (await env.QUOTA.get(`hardban:${addr}`)) {
    await logSecurity(env, request, 'banned_ip_hit')
    throw new HttpError(403, 'تم حظر هذا العنوان — تواصل مع الدعم')
  }
  if (Number(await env.QUOTA.get(`abuse:${addr}`)) >= 20) {
    throw new HttpError(403, 'تم حظر هذا الطلب مؤقتاً')
  }
}

async function rateLimit(env: Env, request: Request, bucket: string, limit: number, window: number): Promise<void> {
  const key = `rl:${bucket}:${ip(request)}`
  const used = Number(await env.QUOTA.get(key)) || 0
  if (used >= limit) {
    await noteAbuse(env, request, `ratelimit:${bucket}`)
    throw new HttpError(429, 'طلبات كثيرة جداً — تم الحظر مؤقتاً')
  }
  await env.QUOTA.put(key, String(used + 1), { expirationTtl: window })
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
  const expected = await hmacHex(
    env.X_SIG_SECRET,
    `${deviceOf(request)}|${ts}|${request.method}|${url.pathname}${url.search}`
  )
  if (sig !== expected) {
    await noteAbuse(env, request, 'bad_signature')
    await logSecurity(env, request, 'bad_signature', `ts=${ts}`)
    throw new HttpError(403, 'توقيع غير صالح')
  }
}

/** جهاز واحد يتظاهر بعدة أجهزة من نفس IP = مزرعة حسابات */
async function trackDeviceFarm(env: Env, request: Request): Promise<void> {
  const dev = deviceOf(request)
  const addr = ip(request)
  if (!dev || addr === 'unknown') return
  const key = `devs:${addr}`
  const list = ((await env.QUOTA.get(key, 'json')) as string[] | null) ?? []
  if (list.includes(dev)) return
  list.push(dev)
  if (list.length > 30) {
    await env.QUOTA.put(`hardban:${addr}`, 'device-farm', { expirationTtl: DAY })
    await logSecurity(env, request, 'device_farm', `devices=${list.length}`)
    throw new HttpError(403, 'تم حظر هذا العنوان — تواصل مع الدعم')
  }
  await env.QUOTA.put(key, JSON.stringify(list.slice(-60)), { expirationTtl: DAY })
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

/** حصة فتح ملفات المخططات — للزائر فقط (المشتركون بلا حدود) */
async function consumeFileQuota(env: Env, ctx: ExecutionContext, caller: Caller, settings: XSettings): Promise<number> {
  if (caller.role !== 'guest') return Number.MAX_SAFE_INTEGER
  const dev = caller.uid.replace(/^guest_/, '')
  const key = `fq:${dev}:${today()}`
  const seenKey = `fqseen:${dev}:${today()}`
  const used = Number(await env.QUOTA.get(key)) || 0
  const limit = settings.guestFileQuota > 0 ? settings.guestFileQuota : 0
  if (used >= limit) {
    throw new HttpError(429, 'انتهت حصة العرض اليومية — تواصل مع المالك لإنشاء حساب بلا حدود')
  }
  ctx.waitUntil(env.QUOTA.put(key, String(used + 1), { expirationTtl: DAY }))
  ctx.waitUntil(env.QUOTA.put(seenKey, '1', { expirationTtl: DAY }))
  return limit - used - 1
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
  db: D1Database, opts: { query: string; brandFile?: string; type?: string; limit: number }
): Promise<MirrorDoc[]> {
  const clauses = ["collection = 'compatibility'"]
  const binds: (string | number)[] = []
  if (opts.brandFile) { binds.push(opts.brandFile); clauses.push(`brand_file = ?${binds.length}`) }
  if (opts.type) { binds.push(opts.type); clauses.push(`component_type = ?${binds.length}`) }
  if (opts.query) { binds.push(`%${opts.query.toLowerCase()}%`); clauses.push(`search_text LIKE ?${binds.length}`) }
  binds.push(opts.limit)
  return mrows(await db.prepare(
    `SELECT id, data FROM docs WHERE ${clauses.join(' AND ')} LIMIT ?${binds.length}`
  ).bind(...binds).all<{ id: string; data: string }>())
}

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
  // إعلانات المرآة (يديرها المالك) + إعلانات X الخاصة — دمج بترتيب order
  const mirrored = (await mirrorCollection(env.MIRROR, 'announcements'))
    .map(d => ({ id: d.id, ...d.fields }))
    .filter((a: any) => a.active === true)
  const own = (await env.XDB.prepare('SELECT id, data FROM x_announcements').all<{ id: string; data: string }>())
    .results?.map(r => ({ id: r.id, ...JSON.parse(r.data) }))
    .filter((a: any) => a.active === true) ?? []
  return [...mirrored, ...own].sort((a: any, b: any) => (b.order ?? 0) - (a.order ?? 0))
}

// ============================== Router ==============================

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url)
    const path = url.pathname

    try {
      if (!['GET', 'POST', 'PUT', 'DELETE'].includes(request.method)) throw new HttpError(405, 'method not allowed')
      if (path === '/health') return json({ ok: true, ts: Date.now() })

      if (BLOCKED_UA.test(request.headers.get('user-agent') ?? '')) throw new HttpError(403, 'forbidden')
      await assertIpClean(env, request)
      await assertDeviceAllowed(env, request)
      await trackDeviceFarm(env, request)

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
            guestFileQuota: settings.guestFileQuota,
            minVersion: settings.minVersion,
            telegramLink: settings.telegramLink,
            schematicsLocked: settings.schematicsLocked,
            compatLocked: settings.compatLocked
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
        await rateLimit(env, request, 'guest', 10, 3600)
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
          await noteAbuse(env, request, 'bad_login')
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
        return json({ brands })
      }

      if (path === '/v1/data/compatibility' && request.method === 'GET') {
        await rateLimit(env, request, 'compat', 200, 600)
        if (caller.role === 'guest' && settings.compatLocked) {
          throw new HttpError(403, 'التوافقات للمشتركين فقط — تواصل مع المالك')
        }
        const results = await mirrorSearchCompat(env.MIRROR, {
          query: url.searchParams.get('q')?.trim() ?? '',
          brandFile: url.searchParams.get('brand')?.trim() || undefined,
          type: url.searchParams.get('type')?.trim() || undefined,
          limit: Math.min(Number(url.searchParams.get('limit')) || 200, 500)
        })
        return json({ records: results.map(d => ({ id: d.id, ...d.fields })) })
      }

      if (path === '/v1/me' && request.method === 'GET') {
        const dev = caller.uid.replace(/^guest_/, '')
        const used = caller.role === 'guest' ? Number(await env.QUOTA.get(`fq:${dev}:${today()}`)) || 0 : 0
        return json({
          user: {
            id: caller.uid, role: caller.role,
            username: auth.user?.username ?? null,
            displayName: auth.user?.display_name ?? ''
          },
          quota: caller.role === 'guest'
            ? { used, limit: settings.guestFileQuota }
            : { used: 0, limit: -1 }
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
        const remaining = await consumeFileQuota(env, ctx, caller, settings)

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

      // ---------- وسائط الإعلانات (صور ترفعها اللوحة) ----------

      const mediaMatch = path.match(/^\/v1\/media\/(.+)$/)
      if (mediaMatch && request.method === 'GET') {
        const key = decodeURIComponent(mediaMatch[1])
        if (!/^[\w\-./]{3,200}$/.test(key) || key.includes('..')) throw new HttpError(400, 'bad key')
        const obj = await env.XMEDIA.get(key)
        if (!obj?.body) throw new HttpError(404, 'not found')
        const headers = new Headers()
        obj.writeHttpMetadata(headers)
        headers.set('cache-control', 'public, max-age=86400')
        return new Response(obj.body, { headers })
      }

      // ---------- لوحة المالك ----------

      if (path.startsWith('/v1/owner/')) {
        if (caller.role !== 'owner') {
          await logSecurity(env, request, 'non_owner_admin_attempt', `uid=${caller.uid}`)
          throw new HttpError(403, 'owner only')
        }

        if (path === '/v1/owner/overview' && request.method === 'GET') {
          const [installs, users, pending, secToday, guests24h] = await Promise.all([
            env.XDB.prepare('SELECT COUNT(*) c FROM x_installs').first<{ c: number }>(),
            env.XDB.prepare("SELECT COUNT(*) c FROM x_users WHERE role != 'owner'").first<{ c: number }>(),
            env.XDB.prepare("SELECT COUNT(*) c FROM x_requests WHERE status = 'pending'").first<{ c: number }>(),
            env.XDB.prepare("SELECT COUNT(*) c FROM x_security WHERE at > ?1").bind(new Date(Date.now() - DAY).toISOString()).first<{ c: number }>(),
            env.XDB.prepare("SELECT COUNT(*) c FROM x_installs WHERE last_seen > ?1").bind(new Date(Date.now() - DAY).toISOString()).first<{ c: number }>()
          ])
          const byVersion = await env.XDB.prepare(
            'SELECT app_version v, COUNT(*) c FROM x_installs GROUP BY app_version ORDER BY c DESC'
          ).all<{ v: string; c: number }>()
          return json({
            installs: installs?.c ?? 0,
            users: users?.c ?? 0,
            pendingRequests: pending?.c ?? 0,
            securityEvents24h: secToday?.c ?? 0,
            activeInstalls24h: guests24h?.c ?? 0,
            installsByVersion: byVersion.results ?? [],
            settings
          })
        }

        if (path === '/v1/owner/settings' && request.method === 'GET') {
          return json({ settings })
        }

        if (path === '/v1/owner/settings' && request.method === 'PUT') {
          const body = await request.json() as Partial<XSettings>
          const next: XSettings = {
            guestFileQuota: Math.max(0, Math.min(10000, Number(body.guestFileQuota ?? settings.guestFileQuota) || 0)),
            minVersion: Math.max(0, Number(body.minVersion ?? settings.minVersion) || 0),
            blockedVersions: Array.isArray(body.blockedVersions)
              ? body.blockedVersions.map(Number).filter(Number.isSafeInteger) : settings.blockedVersions,
            telegramLink: typeof body.telegramLink === 'string' && /^https?:\/\//.test(body.telegramLink)
              ? body.telegramLink.trim() : settings.telegramLink,
            schematicsLocked: body.schematicsLocked ?? settings.schematicsLocked,
            compatLocked: body.compatLocked ?? settings.compatLocked,
            appLocked: body.appLocked ?? settings.appLocked,
            lockMessage: typeof body.lockMessage === 'string' ? body.lockMessage.slice(0, 300) : settings.lockMessage,
            updateMessage: typeof body.updateMessage === 'string' ? body.updateMessage.slice(0, 500) : settings.updateMessage,
            updateUrl: typeof body.updateUrl === 'string' && (!body.updateUrl || /^https?:\/\//.test(body.updateUrl))
              ? body.updateUrl.trim() : settings.updateUrl,
            updateImageUrl: typeof body.updateImageUrl === 'string' ? body.updateImageUrl.slice(0, 500) : settings.updateImageUrl
          }
          await env.XDB.prepare(
            `INSERT INTO x_settings (id, data) VALUES ('main', ?1)
             ON CONFLICT(id) DO UPDATE SET data = ?1`
          ).bind(JSON.stringify(next)).run()
          return json({ ok: true, settings: next })
        }

        if (path === '/v1/owner/users' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            "SELECT id, username, display_name, role, active, device_id, expires_at, created_at FROM x_users WHERE role != 'guest' ORDER BY created_at DESC LIMIT 500"
          ).all()
          return json({ users: rows.results ?? [] })
        }

        // إنشاء حساب مفعّل مباشرة — المالك يضيف مشتركين بنفسه
        if (path === '/v1/owner/users' && request.method === 'POST') {
          const body = await request.json() as {
            username?: string; password?: string; displayName?: string; days?: number
          }
          const username = body.username?.trim() ?? ''
          if (!/^[\w.\-@]{3,60}$/.test(username)) throw new HttpError(400, 'اسم مستخدم غير صالح')
          if ((body.password ?? '').length < 6) throw new HttpError(400, 'كلمة المرور قصيرة')
          if (await xUserByName(env.XDB, username)) throw new HttpError(409, 'اسم المستخدم مستخدم')
          const days = Math.max(0, Math.min(3650, Number(body.days) || 0))
          await env.XDB.prepare(
            `INSERT INTO x_users (id, username, display_name, password_hash, role, active, device_id, expires_at, created_at)
             VALUES (?1, ?2, ?3, ?4, 'user', 1, NULL, ?5, ?6)`
          ).bind(
            `u_${uid()}`, username, body.displayName?.trim() ?? '',
            await hashPassword(body.password!),
            days > 0 ? Date.now() + days * DAY * 1000 : 0,
            new Date().toISOString()
          ).run()
          return json({ ok: true })
        }

        // حظر الأجهزة: عرض/حظر/فك
        if (path === '/v1/owner/bans' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            'SELECT * FROM x_bans ORDER BY at DESC LIMIT 300').all()
          return json({ bans: rows.results ?? [] })
        }
        if (path === '/v1/owner/bans' && request.method === 'POST') {
          const body = await request.json() as { deviceId?: string; reason?: string }
          const dev = body.deviceId?.trim() ?? ''
          if (!dev || dev.length > 100) throw new HttpError(400, 'deviceId required')
          await banDevice(env, dev, body.reason?.trim() || 'manual', request)
          return json({ ok: true })
        }
        const unban = path.match(/^\/v1\/owner\/bans\/(.+)$/)
        if (unban && request.method === 'DELETE') {
          const dev = decodeURIComponent(unban[1])
          await env.QUOTA.delete(`devban:${dev}`)
          await env.XDB.prepare('DELETE FROM x_bans WHERE id = ?1').bind(dev).run()
          return json({ ok: true })
        }

        const userAction = path.match(/^\/v1\/owner\/users\/([\w-]+)\/(activate|deactivate|reset-device|delete|extend)$/)
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
          } else if (action === 'delete') {
            await env.XDB.prepare('DELETE FROM x_users WHERE id = ?1').bind(targetId).run()
          }
          return json({ ok: true })
        }

        if (path === '/v1/owner/requests' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            "SELECT * FROM x_requests ORDER BY created_at DESC LIMIT 200"
          ).all()
          return json({ requests: rows.results ?? [] })
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
          return json({ ok: true })
        }

        if (path === '/v1/owner/security' && request.method === 'GET') {
          const rows = await env.XDB.prepare(
            'SELECT * FROM x_security ORDER BY at DESC LIMIT 200'
          ).all()
          return json({ events: rows.results ?? [] })
        }

        if (path === '/v1/owner/announcements' && request.method === 'GET') {
          const rows = await env.XDB.prepare('SELECT id, data FROM x_announcements ORDER BY id DESC LIMIT 100').all<{ id: string; data: string }>()
          return json({
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
          return json({ ok: true, id, imageUrl })
        }

        const annDelete = path.match(/^\/v1\/owner\/announcements\/([\w-]+)$/)
        if (annDelete && request.method === 'DELETE') {
          await env.XDB.prepare('DELETE FROM x_announcements WHERE id = ?1').bind(annDelete[1]).run()
          return json({ ok: true })
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
