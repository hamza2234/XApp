#!/usr/bin/env bash
# تهيئة قاعدة اختبار محلية نظيفة ثم تشغيل الخادم واختبار الهوية.
#
# الخطوات مرتّبة عمداً: حذف الحالة القديمة، ثم المخطط، ثم الترقية، ثم بيانات
# الاختبار. تشغيلها بترتيب آخر يترك القاعدة بلا دورة مقفلة، فيمرّ الاختبار
# على قائمة فارغة ويبدو ناجحاً وهو لا يختبر شيئاً.
set -uo pipefail
cd "$(dirname "$0")/.."

PORT="${XAPP_TEST_PORT:-8787}"
BASE="http://127.0.0.1:$PORT"
CFG=wrangler.test.toml
DB=x-app-db

echo "== إيقاف أي خادم سابق =="
pkill -f "wrangler dev" 2>/dev/null
sleep 2

echo "== قاعدة نظيفة =="
# كل الحالة لا D1 وحدها: حدود المعدّل في KV، ولو بقيت لعدّت تشغيلات
# سابقة ورَدّت 429 فبدت الاختبارات فاشلة وهي لم تُنفَّذ أصلاً.
rm -rf .wrangler/state

echo "== المخطط =="
npx wrangler d1 execute "$DB" --local --config "$CFG" --file schema.sql >/dev/null 2>&1 \
  || { echo "فشل تطبيق المخطط"; exit 1; }

echo "== ترقية الهوية =="
npx wrangler d1 execute "$DB" --local --config "$CFG" \
  --file migrations/0001_install_identity.sql >/dev/null 2>&1 \
  || { echo "فشل تطبيق الترقية"; exit 1; }

echo "== بيانات الاختبار =="
npx wrangler d1 execute "$DB" --local --config "$CFG" \
  --file migrations/test_fixture.sql >/dev/null 2>&1 \
  || { echo "فشل إدراج بيانات الاختبار"; exit 1; }

echo "== التحقق من أن الدورة المقفلة موجودة فعلاً =="
COUNT=$(npx wrangler d1 execute "$DB" --local --config "$CFG" \
  --command "SELECT COUNT(*) c FROM x_courses WHERE locked = 1" 2>/dev/null \
  | grep -oE '"c": *[0-9]+' | grep -oE '[0-9]+' | head -1)
if [ "${COUNT:-0}" -lt 1 ]; then
  echo "لا دورة مقفلة في القاعدة — الاختبار سيمرّ بلا أن يختبر شيئاً. توقّف."
  exit 1
fi
echo "دورات مقفلة: $COUNT"

echo "== تشغيل الخادم =="
npx wrangler dev --local --port "$PORT" --config "$CFG" > /tmp/worker.log 2>&1 &
for i in $(seq 1 40); do
  if grep -q "Ready on" /tmp/worker.log 2>/dev/null; then break; fi
  sleep 1
done
grep -q "Ready on" /tmp/worker.log || { echo "الخادم لم يبدأ"; tail -20 /tmp/worker.log; exit 1; }
echo "الخادم جاهز على $BASE"

echo "== اختبار الهوية =="
XAPP_TEST_BASE="$BASE" node --test test/identity_live.test.mjs
RC=$?

echo "== إيقاف الخادم =="
pkill -f "wrangler dev" 2>/dev/null
exit $RC
