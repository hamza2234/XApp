/**
 * اختبار تشغيل حقيقي لتعديل صفوف التوافقات — يعمل ضد Worker حقيقي، بلا محاكاة.
 *
 * يحرس العلّة التي أبلغ عنها المالك: التعديل على صفٍّ **قائم** يبدو ناجحاً ثم
 * لا يظهر، بينما الصفّ **الجديد** ينجح. السبب أن مسار `patch` كان يبحث عن
 * الأساس في تعديلات `kind='new'` وحدها؛ فصفّ المرآة (kind='patch') يُبنى كل
 * مرّة على أساس فارغ، فيضيع الحقل المحفوظ قبله. والصفّ الجديد ينجح لأن
 * أساسه `new` أصلاً.
 *
 * التشغيل:
 *   XAPP_TEST_BASE=http://127.0.0.1:8787 node --test test/compat_patch_live.test.mjs
 *
 * الشريحة المحلية المتوقّعة: سجلات في مرآة `apple.json` تحمل `iphone 11`.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto as crypto } from 'node:crypto'

const BASE = process.env.XAPP_TEST_BASE ?? 'http://127.0.0.1:8787'
const OWNER_KEY = process.env.XAPP_TEST_OWNER_KEY ?? 'test_owner_key_value'
const BRAND = 'apple.json'
const hex = (b) => [...b].map(x => x.toString(16).padStart(2, '0')).join('')

const sha = async (d) => hex(new Uint8Array(await crypto.subtle.digest('SHA-256', d)))

async function makeInstall(installId) {
  const kp = await crypto.subtle.generateKey('Ed25519', true, ['sign', 'verify'])
  const raw = await crypto.subtle.exportKey('raw', kp.publicKey)
  return { installId, privateKey: kp.privateKey, publicKeyHex: hex(new Uint8Array(raw)) }
}

async function authed(inst, method, pathWithQuery, opts = {}) {
  const ts = Date.now().toString()
  const nonce = hex(crypto.getRandomValues(new Uint8Array(16)))
  const bodyBytes = new TextEncoder().encode(opts.body ?? '')
  const bodyHash = bodyBytes.length ? await sha(bodyBytes) : ''
  const payload = `${inst.installId}|${ts}|${nonce}|${method}|${pathWithQuery}|${bodyHash}`
  const sig = await crypto.subtle.sign(
    'Ed25519', inst.privateKey, new TextEncoder().encode(payload))
  return {
    'x-install-id': inst.installId,
    'x-app-ts': ts,
    'x-app-nonce': nonce,
    'x-app-sig': hex(new Uint8Array(sig)),
    'x-app-version': String(opts.version ?? 22),
    'User-Agent': 'X-App/2.0.2',
    ...(opts.body ? { 'content-type': 'application/json' } : {}),
    ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}),
  }
}

function enroll(inst) {
  return fetch(`${BASE}/v1/install/key`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-app-version': '22' },
    body: JSON.stringify({
      installId: inst.installId, publicKey: inst.publicKeyHex, appVersion: '2.0.2',
    }),
  })
}

/** يفكّ رد لوحة المالك المشفّر — نفس اشتقاق المفتاح في الخادم. */
async function unseal(token, envelope) {
  const [n, c] = String(envelope).split('.')
  const d = (s) => Uint8Array.from(Buffer.from(
    s.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (s.length % 4)) % 4), 'base64'))
  const material = await crypto.subtle.digest(
    'SHA-256', new TextEncoder().encode(`xapp-owner-panel-v1|${token}`))
  const key = await crypto.subtle.importKey('raw', material, { name: 'AES-GCM' }, false, ['decrypt'])
  const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: d(n) }, key, d(c))
  return JSON.parse(new TextDecoder().decode(plain))
}

async function openOwner(token, json) {
  if (json && typeof json.enc === 'string') return unseal(token, json.enc)
  return json
}

// جلسة مالك واحدة للاختبار كله: الخادم يسمح بثلاثة أجهزة للمالك، فلو سجّل كل
// اختبار تثبيتاً جديداً لبلغ السقف وسقطت الاختبارات على دخول مرفوض لا على
// العلّة المقصودة.
let _owner = null

async function ownerSession() {
  if (_owner) return _owner
  const inst = await makeInstall(
    `test_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`)
  const r = await enroll(inst)
  assert.equal(r.status, 200, `enroll failed ${r.status}`)

  // الحساب قد يكون موجوداً من تشغيل سابق؛ 409 مقبول.
  {
    const path = '/v1/owner/bootstrap'
    const body = JSON.stringify({ username: 'owner', password: 'test12345' })
    await fetch(`${BASE}${path}`, {
      method: 'POST',
      headers: { ...(await authed(inst, 'POST', path, { body })), 'x-owner-key': OWNER_KEY },
      body,
    })
  }

  const path = '/v1/owner/login'
  const body = JSON.stringify({ username: 'owner', password: 'test12345' })
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST', headers: await authed(inst, 'POST', path, { body }), body,
  })
  const j = await res.json()
  assert.ok(j.token, `owner login failed: ${res.status} ${JSON.stringify(j)}`)
  _owner = { inst, token: j.token }
  return _owner
}

/** بحث المستخدم — نفس المسار الذي يستعمله المالك في شاشة التوافقات. */
async function search(q, type = 'SCREEN') {
  const { inst, token } = await ownerSession()
  const path = '/v1/data/compat/search'
  const body = JSON.stringify({ q, brand: BRAND, type })
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST', headers: await authed(inst, 'POST', path, { body, token }), body,
  })
  const j = await res.json()
  assert.equal(res.status, 200, `search ${res.status}: ${JSON.stringify(j)}`)
  return j.records ?? []
}

async function edit(payload) {
  const { inst, token } = await ownerSession()
  const path = '/v1/owner/compat/edit'
  const body = JSON.stringify(payload)
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST', headers: await authed(inst, 'POST', path, { body, token }), body,
  })
  const raw = await res.json()
  return { status: res.status, json: await openOwner(token, raw) }
}

const rowFor = (rows, q) => rows.find(r => (r.compatibleModels ?? []).some(
  m => String(m).toLowerCase().includes(q)))

const uniq = (p) => `${p}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`

test('تعديل صفّ قائم يُحفظ فعلاً ويظهر بعد إعادة البحث', async () => {
  const row = rowFor(await search('iphone 11'), 'iphone 11')
  assert.ok(row, 'لا صفّ يضمّ iphone 11 في الشريحة')

  const marker = uniq('sub')
  const r = await edit({
    op: 'patch', brand: BRAND, id: row.id, fields: { subCategory: { name: marker } },
  })
  assert.equal(r.status, 200, `patch rejected: ${JSON.stringify(r.json)}`)

  const again = (await search('iphone 11')).find(x => x.id === row.id)
  assert.ok(again, 'الصفّ اختفى بعد التعديل')
  assert.equal(again.subCategory?.name, marker, 'التعديل لم يُحفظ')
})

/**
 * العلّة الأصلية: تعديلان متتاليان على الصفّ نفسه. الثاني كان يُبنى على أساس
 * فارغ فيضيع الأول — والصفّ الجديد لا يتأثّر لأن أساسه `new`.
 */
test('تعديلان متتاليان على صفّ قائم يُحفظان معاً', async () => {
  const row = rowFor(await search('iphone 11'), 'iphone 11')
  assert.ok(row, 'لا صفّ لاختبار الدمج')

  const sub = uniq('keep')
  const note = uniq('note')
  const r1 = await edit({
    op: 'patch', brand: BRAND, id: row.id, fields: { subCategory: { name: sub } },
  })
  assert.equal(r1.status, 200, `patch1 rejected: ${JSON.stringify(r1.json)}`)
  const r2 = await edit({
    op: 'patch', brand: BRAND, id: row.id, fields: { note },
  })
  assert.equal(r2.status, 200, `patch2 rejected: ${JSON.stringify(r2.json)}`)

  const again = (await search('iphone 11')).find(x => x.id === row.id)
  assert.ok(again, 'الصفّ اختفى بعد التعديلين')
  assert.equal(again.subCategory?.name, sub, 'الحقل الأول ضاع في التعديل الثاني')
  assert.equal(again.note, note, 'الحقل الثاني لم يُحفظ')
})

/**
 * الحذف يُخفي، والاسترجاع يعيد — ولا يُفقد محتوى الصفّ بينهما.
 *
 * الحذف يأتي **بعد** تعديل على الصفّ نفسه عمداً: مسار الحذف كان يبحث عن
 * الطبقة بـ`kind='patch'` وحده، ومسار التعديل كان يقلب النوع إلى `new` بعد
 * أول تعديل. فحذف صفّ عدّله المالك مرّتين لم يجد الطبقة، فحفظ `{}` ومسح
 * ما كتبه — أي أن الحذف «ينجح» ويمحو التعديل.
 */
test('حذف صفّ سبق تعديله يخفيه ويعيده بتعديله لا بطبقة فارغة', async () => {
  const row = rowFor(await search('iphone 11'), 'iphone 11')
  assert.ok(row, 'لا صفّ لاختبار الحذف')

  const note = uniq('keepondel')
  const p1 = await edit({ op: 'patch', brand: BRAND, id: row.id, fields: { note } })
  assert.equal(p1.status, 200, `patch1 rejected: ${JSON.stringify(p1.json)}`)
  const p2 = await edit({ op: 'patch', brand: BRAND, id: row.id, fields: { note } })
  assert.equal(p2.status, 200, `patch2 rejected: ${JSON.stringify(p2.json)}`)

  const del = await edit({ op: 'delete', brand: BRAND, id: row.id })
  assert.equal(del.status, 200, `delete rejected: ${JSON.stringify(del.json)}`)
  assert.equal((await search('iphone 11')).find(x => x.id === row.id), undefined,
    'الصفّ ما زال ظاهراً بعد الحذف')

  const res = await edit({ op: 'restore', brand: BRAND, id: row.id })
  assert.equal(res.status, 200, `restore rejected: ${JSON.stringify(res.json)}`)
  const back = (await search('iphone 11')).find(x => x.id === row.id)
  assert.ok(back, 'الصفّ لم يعد بعد الاسترجاع')
  assert.equal(back.note, note, 'الاسترجاع فقد تعديل المالك السابق')
})

/**
 * نصّ يضيفه المالك إلى صفّ قائم لا وجود له في المرآة؛ فالبحث به لا يعيد الصفّ
 * من المرآة أصلاً، فلا يجد المالك ما كتبه. هذا هو أثر «أضفت موديلاً ولم يظهر».
 */
test('نصّ مُضاف إلى صفّ قائم يُبحث عنه فيظهر', async () => {
  const row = rowFor(await search('iphone 11'), 'iphone 11')
  assert.ok(row, 'لا صفّ لاختبار البحث عن النصّ المضاف')

  const token = uniq('zzmodel').toLowerCase()
  const models = [...(row.compatibleModels ?? []), token]
  const r = await edit({
    op: 'patch', brand: BRAND, id: row.id, fields: { compatibleModels: models },
  })
  assert.equal(r.status, 200, `patch rejected: ${JSON.stringify(r.json)}`)

  const found = (await search(token)).find(x => x.id === row.id)
  assert.ok(found, 'النصّ المُضاف لا يظهر في البحث')
  assert.ok((found.compatibleModels ?? []).some(m => String(m).includes(token)),
    'الصفّ ظهر لكن بلا النصّ المُضاف')
})

/**
 * المعرّف كان يُقصّ إلى 64 حرفاً في التعديل والحذف، فيُخزَّن تحت مفتاح غير
 * المفتاح الذي يُقرأ به الصفّ: نجاح بلا أثر. أطوال معرّفات المرآة الحالية
 * قصيرة، لكن القصّ يجعل الفشل صامتاً متى وُجد معرّف أطول.
 */
test('معرّف أطول من 64 حرفاً لا يُقصّ فيُضيع التعديل', async () => {
  const LONG = 'new_' + '0'.repeat(70)
  const r = await edit({
    op: 'patch', brand: BRAND, id: LONG, fields: { note: 'zz_long' },
  })
  assert.equal(r.status, 200, `patch rejected: ${JSON.stringify(r.json)}`)
  assert.equal(r.json?.id, LONG, `المعرّف قُصّ إلى: ${r.json?.id}`)
})
