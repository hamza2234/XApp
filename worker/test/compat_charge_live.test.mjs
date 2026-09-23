/**
 * اختبار تشغيل حقيقي لقاعدة خصم التوافقات — ضد Worker حقيقي، بلا محاكاة.
 *
 * القاعدة المطلوبة: الخصم يقع **مرة واحدة عند دخول الشركة**، لا مع كل بحث
 * داخل الشركة. العلّة التي أُبلغ عنها أن البحث لا يخصم أصلاً؛ فالاختبار يثبت
 * أن الدخول يُخصم فعلاً، وأن البحث الثاني في الشركة نفسها لا يخصم ثانيةً،
 * وأن دخول شركة أخرى يُخصم منفصلاً.
 *
 * التشغيل:
 *   XAPP_TEST_BASE=http://127.0.0.1:8787 node --test test/compat_charge_live.test.mjs
 *
 * يستهلك هذا الاختبار منحة الجهاز اليومية، فيحتاج شريحة مرآة فيها شركتان
 * مختلفتان على الأقل.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { webcrypto as crypto } from 'node:crypto'

const BASE = process.env.XAPP_TEST_BASE ?? 'http://127.0.0.1:8787'
const BRANDS = (process.env.XAPP_TEST_BRANDS ?? 'apple.json,samsung.json').split(',')
const hex = (b) => [...b].map(x => x.toString(16).padStart(2, '0')).join('')
const sha = async (d) =>
  hex(new Uint8Array(await crypto.subtle.digest('SHA-256', d)))

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
    'x-app-ts': ts, 'x-app-nonce': nonce, 'x-app-sig': hex(new Uint8Array(sig)),
    'x-app-version': '22', 'User-Agent': 'X-App/2.0.2',
    ...(opts.body ? { 'content-type': 'application/json' } : {}),
    ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}),
  }
}

/** جلسة زائر — كما يحصل عليها أي مستخدم عند أول فتح للتطبيق. */
async function guestSession(inst) {
  const path = '/v1/auth/guest'
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST', headers: await authed(inst, 'POST', path),
  })
  const j = await res.json()
  assert.ok(j.token, `guest session failed: ${res.status} ${JSON.stringify(j)}`)
  return j.token
}

/** يدخل شركة عبر نفس نقطة الدخول التي تستدعيها شاشة التوافقات. */
async function openBrand(inst, token, brand) {
  const path = '/v1/data/compat/open'
  const body = JSON.stringify({ brand })
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST', headers: await authed(inst, 'POST', path, { body, token }), body,
  })
  const j = await res.json()
  assert.equal(res.status, 200, `open ${res.status}: ${JSON.stringify(j)}`)
  return j
}

async function searchIn(inst, token, brand, q, type = 'SCREEN') {
  const path = '/v1/data/compat/search'
  const body = JSON.stringify({ q, brand, type })
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST', headers: await authed(inst, 'POST', path, { body, token }), body,
  })
  const j = await res.json()
  assert.equal(res.status, 200, `search ${res.status}: ${JSON.stringify(j)}`)
  return j
}

test('الدخول يُخصم مرة، والبحث داخل الشركة لا يخصم ثانية', async () => {
  const inst = await makeInstall(
    `charge_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`)
  const r = await fetch(`${BASE}/v1/install/key`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-app-version': '22' },
    body: JSON.stringify({
      installId: inst.installId, publicKey: inst.publicKeyHex, appVersion: '2.0.2',
    }),
  })
  assert.equal(r.status, 200, `enroll failed ${r.status}`)
  const token = await guestSession(inst)

  const entry = await openBrand(inst, token, BRANDS[0])
  assert.equal(entry.charged, true, 'دخول الشركة لم يُخصم أصلاً')

  // بحثان مختلفان داخل الشركة نفسها: الثاني لا يخصم لأن الدخول خُصم سابقاً.
  const s1 = await searchIn(inst, token, BRANDS[0], 'iphone 11')
  const s2 = await searchIn(inst, token, BRANDS[0], 'iphone 12')
  assert.equal(s1.charged, false, 'البحث خصم رغم أن الدخول خُصم')
  assert.equal(s2.charged, false, 'البحث الثاني خصم داخل الشركة نفسها')
  assert.equal(s2.balance, s1.balance,
    'الرصيد تغيّر بين بحثين داخل الشركة نفسها')

  // دخول شركة أخرى: خصم جديد، لأن القاعدة لكل شركة لا لكل جهاز.
  if (BRANDS[1] && BRANDS[1] !== BRANDS[0]) {
    const other = await openBrand(inst, token, BRANDS[1])
    assert.equal(other.charged, true, 'دخول شركة ثانية لم يُخصم')
  }
})
