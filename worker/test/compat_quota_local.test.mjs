import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { stripTypeScriptTypes } from 'node:module'
import { DatabaseSync } from 'node:sqlite'
import vm from 'node:vm'

const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8')
const js = stripTypeScriptTypes(source, { mode: 'transform' })
const schema = readFileSync(new URL('../schema.sql', import.meta.url), 'utf8')

function database() {
  const sql = new DatabaseSync(':memory:')
  const db = {
    sql,
    prepare(text) {
      let args = []
      const run = () => {
        const stmt = sql.prepare(text.replace(/\?(\d+)/g, ':p$1'))
        const bindings = Object.fromEntries(args.map((v, i) => [`p${i + 1}`, v]))
        stmt.setAllowUnknownNamedParameters(true)
        const results = stmt.all(bindings)
        return { results, success: true, meta: { changes: sql.prepare('SELECT changes() n').get().n } }
      }
      return {
        bind(...values) { args = values; return this },
        async first() { return run().results[0] ?? null },
        async all() { return run() },
        async run() { return run() },
      }
    },
    async batch(statements) {
      sql.exec('BEGIN')
      try {
        const out = []
        for (const s of statements) out.push(await s.all())
        sql.exec('COMMIT')
        return out
      } catch (e) {
        sql.exec('ROLLBACK')
        throw e
      }
    },
  }
  return db
}

function fixture() {
  const XDB = database()
  XDB.sql.exec(schema)
  XDB.sql.exec('CREATE TABLE IF NOT EXISTS x_guest_wallets (device_id TEXT PRIMARY KEY, balance INTEGER, expires_at INTEGER, created_at TEXT, updated_at TEXT)')
  const MIRROR = database()
  MIRROR.sql.exec("CREATE TABLE docs (id TEXT, collection TEXT, brand_file TEXT, data TEXT)")
  const fields = { componentType: 'SCREEN', compatibleModels: ['iphone 11', 'remove me'], subCategory: { name: 'LCD' } }
  MIRROR.sql.prepare('INSERT INTO docs VALUES (?, ?, ?, ?)').run('row1', 'compatibility', 'apple.json', JSON.stringify(fields))
  const env = { XDB, MIRROR }
  const context = vm.createContext({ Request, Response, URL, TextEncoder, TextDecoder, crypto, console, atob, btoa })
  vm.runInContext(js.replace('export default', 'const worker ='), context)
  vm.runInContext('logSecurity = async () => {}; rateLimit = async () => {}; walletOf = async () => "wallet1"; fingerprintRotated = async () => false;', context)
  context.env = env
  context.caller = { role: 'guest', uid: 'guest1' }
  context.settings = { dailyFreeQuota: 7, dailyGiftAmount: 99, compatSearchCost: 1 }
  context.sealed = value => value
  context.path = '/v1/owner/compat/edit'
  const route = (start, end) => js.slice(js.indexOf(start), js.indexOf(end, js.indexOf(start)))
  const editCode = route("if (path === '/v1/owner/compat/edit'", "if (path === '/v1/owner/compat/brands'")
  const giftCode = route("if (path === '/v1/gift/claim'", "if (path === '/v1/owner/devices/release'")
  return {
    env, context, fields,
    async edit(payload) {
      context.path = '/v1/owner/compat/edit'
      context.request = new Request('http://localhost' + context.path, { method: 'POST', body: JSON.stringify({ brand: 'apple.json', ...payload }) })
      return vm.runInContext(`(async () => { ${editCode} })()`, context)
    },
    async claim() {
      context.path = '/v1/gift/claim'
      context.request = new Request('http://localhost' + context.path, { method: 'POST' })
      const res = await vm.runInContext(`(async () => { ${giftCode} })()`, context)
      return { status: res.status, body: await res.json() }
    },
    async search(tokens, original = []) {
      context.original = original
      context.tokens = tokens
      return vm.runInContext("mergeCompatEdits(env, 'apple.json', original, tokens, undefined, 'SCREEN', 120)", context)
    },
  }
}

test('patch returns the saved row and preserves other fields', async () => {
  const f = fixture()
  await f.edit({ op: 'patch', id: 'row1', fields: { note: 'preserve' } })
  const r = await f.edit({ op: 'patch', id: 'row1', fields: { compatibleModels: ['iphone 11', 'new model'] } })
  assert.deepEqual(Array.from(r.record.compatibleModels), ['iphone 11', 'new model'])
  assert.equal(r.record.subCategory.name, 'LCD')
  assert.equal(r.record.note, 'preserve')
  const found = await f.search(['new', 'model'])
  assert.equal(found[0].id, 'row1')
  const saved = JSON.parse(f.env.XDB.sql.prepare("SELECT data FROM x_compat_edits WHERE doc_key='row1'").get().data)
  assert.deepEqual(saved.compatibleModels, ['iphone 11', 'new model'])
})

test('removed text no longer matches the original mirror row', async () => {
  const f = fixture()
  await f.edit({ op: 'patch', id: 'row1', fields: { compatibleModels: ['iphone 11'] } })
  const found = await f.search(['remove'], [{ id: 'row1', fields: f.fields }])
  assert.equal(found.length, 0)
})

test('claim uses owner quota, rejects duplicates and survives midnight', async () => {
  const f = fixture()
  const first = await f.claim()
  assert.equal(first.status, 200)
  assert.equal(first.body.amount, 7)
  assert.equal(first.body.nextAt - f.env.XDB.sql.prepare('SELECT last_at FROM x_gift_claims').get().last_at, 86400000)
  assert.equal((await f.claim()).status, 409)
  const balance = f.env.XDB.sql.prepare('SELECT balance FROM x_guest_wallets').get().balance
  assert.equal(balance, 7)
  f.env.XDB.sql.prepare('UPDATE x_gift_claims SET last_at=?, next_at=?').run(Date.now() - 13 * 3600000, Date.now() - 1)
  assert.equal((await f.claim()).status, 409)
  f.env.XDB.sql.prepare('UPDATE x_gift_claims SET last_at=?, next_at=?').run(Date.now() - 86400001, Date.now() - 1)
  assert.equal((await f.claim()).status, 200)
  assert.equal(f.env.XDB.sql.prepare('SELECT balance FROM x_guest_wallets').get().balance, 14)
})

test('deleting the last model hides the row without touching the mirror', async () => {
  const f = fixture()
  const r = await f.edit({ op: 'delete', id: 'row1' })
  assert.equal(r.ok, true)
  assert.equal((await f.search(['iphone'], [{ id: 'row1', fields: f.fields }])).length, 0)
  assert.equal(f.env.MIRROR.sql.prepare('SELECT COUNT(*) n FROM docs').get().n, 1)
})

test('missing rows and wrong brands cannot report successful persistence', async () => {
  const f = fixture()
  await assert.rejects(f.edit({ op: 'patch', id: 'missing', fields: { compatibleModels: ['new'] } }), e => e.status === 404)
  await assert.rejects(f.edit({ op: 'patch', brand: 'samsung.json', id: 'row1', fields: { note: 'wrong' } }), e => e.status === 404)
  assert.equal(f.env.XDB.sql.prepare('SELECT COUNT(*) n FROM x_compat_edits').get().n, 0)
})

test('failed credit rolls back the claim reservation', async () => {
  const f = fixture()
  f.env.XDB.sql.exec("CREATE TRIGGER fail_credit BEFORE INSERT ON x_guest_wallets BEGIN SELECT RAISE(ABORT, 'test failure'); END")
  await assert.rejects(f.claim())
  assert.equal(f.env.XDB.sql.prepare('SELECT COUNT(*) n FROM x_gift_claims').get().n, 0)
  f.env.XDB.sql.exec('DROP TRIGGER fail_credit')
  assert.equal((await f.claim()).status, 200)
})

test('zero owner quota disables gift even if legacy gift amount is positive', async () => {
  const f = fixture()
  f.context.settings.dailyFreeQuota = 0
  assert.equal((await f.claim()).status, 403)
  const normalized = vm.runInContext('normalizeSettings({...DEFAULT_SETTINGS, dailyFreeQuota: 0, dailyGiftAmount: 99}, {dailyFreeQuota: 0})', f.context)
  assert.equal(normalized.dailyGiftAmount, 0)
})

test('registered users receive the same quota once in their own wallet', async () => {
  const f = fixture()
  f.env.XDB.sql.exec("INSERT INTO x_users (id, username, quota_balance, created_at) VALUES ('user1', 'test-user', 10, 'test')")
  f.context.caller = { role: 'user', uid: 'user1' }
  assert.equal((await f.claim()).body.balance, 17)
  assert.equal((await f.claim()).status, 409)
  assert.equal(f.env.XDB.sql.prepare("SELECT quota_balance FROM x_users WHERE id='user1'").get().quota_balance, 17)
})

test('new daily credit remains usable when the old wallet has expired', async () => {
  const f = fixture()
  f.env.XDB.sql.exec("INSERT INTO x_guest_wallets VALUES ('wallet1', 50, 1, 'test', 'test')")
  assert.equal((await f.claim()).body.balance, 7)
  const charge = await vm.runInContext("chargeOne(env, caller, 'wallet1', settings)", f.context)
  assert.equal(charge.balance, 6)
})

test('no automatic allowance before claiming', async () => {
  const f = fixture()
  await assert.rejects(vm.runInContext("chargeOne(env, caller, 'wallet1', settings)", f.context), e => e.status === 402)
  await f.claim()
  const charge = await vm.runInContext("chargeOne(env, caller, 'wallet1', settings)", f.context)
  assert.equal(charge.balance, 6)
})
