/**
 * اختبار تشغيل حقيقي ضد Worker يعمل فعلاً — لا محاكاة ولا mocks.
 *
 * يحرس الثغرة التي أُغلقت: السلطة كانت تُشتقّ من `x-device-id` الذي يرسله
 * العميل ولا يدخل في نصّ التوقيع. فمن سجّل مفتاح تثبيت لنفسه (مجاناً وبلا
 * كلمة مرور) وقّع طلباً صحيحاً ثم وضع معرّف جهاز المالك فيه، فيمرّ التوقيع
 * ويُفتح كل مقفل. الاختبار يشنّ هذا الهجوم نفسه على الخادم الحقيقي ويتوقّع
 * أن يُرفض أو ألا يمنح شيئاً.
 *
 * التشغيل: يُقرأ عنوان الخادم من XAPP_TEST_BASE (افتراضاً المنفذ المحلي).
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto as crypto } from 'node:crypto'

const BASE = process.env.XAPP_TEST_BASE ?? 'http://127.0.0.1:8787'
const hex = (b) => [...b].map(x => x.toString(16).padStart(2, '0')).join('')

async function sha256Hex(data) {
  const d = await crypto.subtle.digest('SHA-256', data)
  return hex(new Uint8Array(d))
}

/** تثبيت مستقل بمفتاح Ed25519 خاص به — كما يفعل التطبيق الحقيقي. */
async function makeInstall(installId) {
  const kp = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify'])
  const raw = await crypto.subtle.exportKey('raw', kp.publicKey)
  return { installId, privateKey: kp.privateKey, publicKeyHex: hex(new Uint8Array(raw)) }
}

/** يبني ترويسات موقّعة كما يفعل RequestSigner تماماً. */
async function signedHeaders(inst, method, pathWithQuery, opts = {}) {
  const ts = Date.now().toString()
  const nonce = hex(crypto.getRandomValues(new Uint8Array(16)))
  const bodyBytes = new TextEncoder().encode(opts.body ?? '')
  const bodyHash = bodyBytes.length ? await sha256Hex(bodyBytes) : ''
  const payload = `${inst.installId}|${ts}|${nonce}|${method}|${pathWithQuery}|${bodyHash}`
  const sig = await crypto.subtle.sign(
    'Ed25519', inst.privateKey, new TextEncoder().encode(payload))
  return {
    'x-install-id': inst.installId,
    'x-device-id': opts.deviceId ?? '',
    'x-device-fp': opts.fp ?? '',
    'x-app-ts': ts,
    'x-app-nonce': nonce,
    'x-app-sig': hex(new Uint8Array(sig)),
    'x-app-version': String(opts.version ?? 22),
    'User-Agent': 'X-App/2.0.2',
  }
}

/** تسجيل المفتاح العام — الطلب الوحيد المعفى من التوقيع. */
function enroll(inst) {
  return fetch(`${BASE}/v1/install/key`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-app-version': '22', 'User-Agent': 'X-App/2.0.2',
    },
    body: JSON.stringify({
      installId: inst.installId, publicKey: inst.publicKeyHex, appVersion: '2.0.2',
    }),
  })
}

async function authed(inst, method, path, opts = {}) {
  const h = await signedHeaders(inst, method, path, opts)
  const out = opts.body ? { ...h, 'content-type': 'application/json' } : { ...h }
  if (opts.token) out.authorization = `Bearer ${opts.token}`
  return out
}

/**
 * جلسة زائر — كما يحصل عليها أي مستخدم عند أول فتح.
 *
 * مسارات /v1/learn تتطلب توقيعاً *وجلسة*، والجلسة هنا مشروعة تماماً: أي
 * أحد يستطيع إنشاء تثبيت والحصول عليها. الاختبار لا يفترض أن الجلسة محجوبة،
 * بل أن الجلسة وحدها لا تمنح سلطة مالك ولا تفتح دورة مقفلة.
 */
async function guestSession(inst, deviceId) {
  const res = await fetch(`${BASE}/v1/auth/guest`, {
    method: 'POST',
    headers: await authed(inst, 'POST', '/v1/auth/guest', { deviceId }),
  })
  if (!res.ok) throw new Error(`guest session failed: ${res.status} ${await res.text()}`)
  const body = await res.json()
  return body.token
}

test('التسجيل يقبل مفتاحاً جديداً', async () => {
  const inst = await makeInstall(`testinstall${Date.now().toString(36)}`)
  const res = await enroll(inst)
  assert.equal(res.status, 200, await res.text())
})

test('طلب غير موقّع يُرفض', async () => {
  const res = await fetch(`${BASE}/v1/learn/courses`, {
    headers: { 'x-app-version': '22', 'User-Agent': 'X-App/2.0.2' },
  })
  assert.equal(res.status, 403, 'كل /v1/* يجب أن يتطلب توقيعاً')
})

test('انتحال المالك بمعرّف جهاز مسروق لا يمنح وصولاً', async () => {
  // المهاجم: تثبيت مستقل، مفتاحه الخاص، بلا كلمة مرور ولا وسم مالك.
  const attacker = await makeInstall(`attacker${Date.now().toString(36)}`)
  assert.equal((await enroll(attacker)).status, 200)

  // الهجوم: توقيع صحيح بمفتاح المهاجم + معرّف جهاز المالك في الترويسة.
  // هذا بالضبط ما كان يمرّ قبل الإصلاح.
  const token = await guestSession(attacker, 'ownerphone123')
  const res = await fetch(`${BASE}/v1/learn/courses`, {
    headers: await authed(attacker, 'GET', '/v1/learn/courses', {
      deviceId: 'ownerphone123', token,
    }),
  })
  assert.equal(res.status, 200, `status=${res.status}`)
  const body = await res.json()

  // وجود دورة مقفلة شرط للاختبار: قائمة فارغة تمرّ بلا أن تختبر شيئاً.
  const locked = (body.courses ?? []).filter((c) => c.locked)
  assert.ok(locked.length > 0,
    'لا دورة مقفلة في القاعدة — الاختبار لا يختبر شيئاً')

  // الدورات المقفلة يجب أن تبقى مقفلة: لا استحقاق ولا رابط بثّ.
  for (const c of locked) {
    assert.notEqual(c.unlocked, true,
      `انتحال المالك نجح على «${c.title}» — القفل مفتوح لمن انتحل المعرّف`)
    for (const v of c.videos ?? []) {
      assert.ok(!v.streamUrl,
        `رابط بثّ سُرّب لفيديو مقفل «${v.title}» عبر انتحال معرّف الجهاز`)
    }
  }
})

test('منحة الصف القديم لا تُرقّى صامتة فتُفتح', async () => {
  // المهاجم يضع معرّف جهاز مشترك له منحة في الشكل القديم (وُسمت legacy:
  // في fixture الترقية فلا تُطابق). يحرس ألا تُمنح الصفوف القديمة سلطة.
  const attacker = await makeInstall(`attacker2${Date.now().toString(36)}`)
  assert.equal((await enroll(attacker)).status, 200)

  const token = await guestSession(attacker, 'subscriberphone')
  const res = await fetch(`${BASE}/v1/learn/courses`, {
    headers: await authed(attacker, 'GET', '/v1/learn/courses', {
      deviceId: 'subscriberphone', token,
    }),
  })
  assert.equal(res.status, 200, `status=${res.status}`)
  const body = await res.json()
  const locked = (body.courses ?? []).filter((c) => c.locked)
  assert.ok(locked.length > 0,
    'لا دورة مقفلة في القاعدة — الاختبار لا يختبر شيئاً')
  for (const c of locked) {
    assert.notEqual(c.unlocked, true,
      `منحة الصف القديم رُقّيت صامتة ففتحت «${c.title}»`)
  }
})

test('بثّ فيديو مقفل بمعرّف جهاز مسروق يُرفض', async () => {
  const attacker = await makeInstall(`attacker3${Date.now().toString(36)}`)
  assert.equal((await enroll(attacker)).status, 200)

  const attackerToken = await guestSession(attacker, 'ownerphone123')
  const listRes = await fetch(`${BASE}/v1/learn/courses`, {
    headers: await authed(attacker, 'GET', '/v1/learn/courses', {
      deviceId: 'ownerphone123', token: attackerToken,
    }),
  })
  const body = await listRes.json()
  const lockedVideo = (body.courses ?? [])
    .filter((c) => c.locked)
    .flatMap((c) => c.videos ?? [])[0]
  assert.ok(lockedVideo,
    'لا فيديو في دورة مقفلة — الاختبار لا يختبر شيئاً')

  const res = await fetch(`${BASE}/v1/learn/stream/${lockedVideo.id}`, {
    headers: await authed(attacker, 'GET', `/v1/learn/stream/${lockedVideo.id}`, {
      deviceId: 'ownerphone123', token: attackerToken,
    }),
  })
  assert.ok(res.status === 403 || res.status === 404,
    `بثّ فيديو مقفل سُمح به لمن انتحل معرّف الجهاز (status=${res.status})`)
})

test('كود وهمي يُرفض ولا يفتح شيئاً', async () => {
  const inst = await makeInstall(`legit${Date.now().toString(36)}`)
  assert.equal((await enroll(inst)).status, 200)

  const payload = JSON.stringify({ code: 'AAAA-BBBB-CCCC-DDDD' })
  const token = await guestSession(inst, 'ownerphone123')
  const res = await fetch(`${BASE}/v1/learn/redeem`, {
    method: 'POST',
    headers: await authed(inst, 'POST', '/v1/learn/redeem', {
      deviceId: 'ownerphone123', body: payload, token,
    }),
    body: payload,
  })
  assert.ok([400, 404, 410].includes(res.status),
    `كود وهمي لم يُرفض (status=${res.status})`)
})


test('هوية الزائر مربوطة بالتثبيت لا بمعرّف الجهاز', async () => {
  const victim = await makeInstall(`gv${Date.now().toString(36)}`)
  assert.equal((await enroll(victim)).status, 200)
  // جلسة زائر بمعرّف جهاز معروف.
  const victimToken = await guestSession(victim, 'ownerphone123')

  // الهوية المعلنة لا يجوز أن تُشتقّ من ترويسة يملكها العميل: لو كانت
  // `guest_ownerphone123` لأمكن لأي أحد طلب جلسة بهذا المعرّف والكتابة باسم
  // صاحبه في الدردشة.
  const me = await fetch(`${BASE}/v1/me`, {
    headers: await authed(victim, 'GET', '/v1/me', { token: victimToken }),
  })
  if (me.status === 200) {
    const body = await me.json()
    const id = String(body?.user?.id ?? '')
    assert.ok(!id.includes('ownerphone123'),
      `هوية الزائر مشتقّة من معرّف الجهاز: ${id}`)
  }

  // مهاجم بتثبيت آخر يستعمل رمز الضحية بمعرّف جهاز الضحية نفسه.
  const attacker = await makeInstall(`ga${Date.now().toString(36)}`)
  assert.equal((await enroll(attacker)).status, 200)
  const replay = await fetch(`${BASE}/v1/me`, {
    headers: await authed(attacker, 'GET', '/v1/me', { token: victimToken }),
  })
  assert.equal(replay.status, 401,
    `رمز زائر قُبل من تثبيت آخر (status=${replay.status}) — الرمز انتقل بين التثبيتات`)
})
