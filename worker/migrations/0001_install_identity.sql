-- ==============================================================
-- ترقية أمنية: نسبة السلطة إلى التثبيت الموثّق بدل ترويسة العميل
-- ==============================================================
-- الثغرة التي تُغلقها هذه الترقية:
--   `x-device-id` يرسله العميل، ولا يدخل في نصّ التوقيع
--   (`installId|ts|nonce|method|path|bodyHash`). فمن سجّل مفتاح تثبيت لنفسه
--   — وهو مجاني ولا يحتاج كلمة مرور — يستطيع توقيع طلب صحيح ثم وضع معرّف
--   جهاز المالك فيه. التوقيع يمرّ، وكان `ownerDevice()` يقرأ معرّف الجهاز
--   فيعيد true: كل دورة مقفلة تُفتح، وكل فيديو يُبثّ، بلا كلمة مرور.
--   وبالمثل: من قرأ معرّف جهاز مشترك (يظهر في الدردشة وفي تصدير اللوحة)
--   فتح دوراته بلا كود، لأن المنح كانت مفتاحها معرّف الجهاز نفسه.
--
-- الإصلاح: المفتاح صار `install_id` — القيمة الوحيدة التي يثبتها التوقيع
-- بمفتاح خاص لا يغادر الجهاز.
--
-- ملاحظة تشغيلية مهمة (مقصودة، لا سهو):
--   الصفوف القديمة لا تُنسب إلى أي تثبيت، ولا تُرقّى إليه. الترقية الصامتة
--   كانت ستُعيد إدخال الثغرة نفسها: لا سبيل لإثبات أن من يرسل معرّف الجهاز
--   القديم هو الجهاز الذي أنشأ الصف. لذلك تُحفظ الصفوف القديمة بوسم
--   `legacy:` للعرض والسجل، ولا تُطابق أي طلب حقيقي.
--   الأثر: من كان وصوله مبنياً على معرّف الجهاز يفقد الوصول حتى يُمنح كوداً
--   جديداً؛ والمالك يعيد وسم تثبيته بدخول واحد إلى اللوحة. هذا هو الثمن
--   الوحيد المقبول لإغلاق الانتحال، وهو مرئي في اللوحة لا صامت.

-- ── 1) x_course_grants: إعادة بناء بالمفتاح الصحيح ──
-- إعادة بناء لا ALTER: المفتاح الأساسي نفسه يجب أن يتغيّر، وSQLite لا
-- يسمح بتغيير المفتاح الأساسي في مكانه. الصفوف تُنسخ أولاً فلا يُفقد سجل.
CREATE TABLE IF NOT EXISTS x_course_grants_new (
  install_id TEXT NOT NULL DEFAULT '',
  device_id  TEXT NOT NULL DEFAULT '',
  course_id  TEXT NOT NULL,
  key_id     TEXT NOT NULL DEFAULT '',
  user_id    TEXT NOT NULL DEFAULT '',
  at         INTEGER NOT NULL,
  PRIMARY KEY (install_id, course_id)
);
INSERT OR IGNORE INTO x_course_grants_new
  (install_id, device_id, course_id, key_id, user_id, at)
SELECT 'legacy:' || device_id, device_id, course_id, key_id, user_id, at
  FROM x_course_grants;
DROP TABLE x_course_grants;
ALTER TABLE x_course_grants_new RENAME TO x_course_grants;
CREATE INDEX IF NOT EXISTS x_course_grants_course ON x_course_grants (course_id);

-- ── 2) x_devices: إعادة بناء بالمفتاح الصحيح ──
CREATE TABLE IF NOT EXISTS x_devices_new (
  install_id   TEXT PRIMARY KEY,
  device_id    TEXT NOT NULL DEFAULT '',
  owner_marked INTEGER NOT NULL DEFAULT 0,
  owner_bound  INTEGER NOT NULL DEFAULT 0,
  first_seen   TEXT NOT NULL,
  last_seen    TEXT NOT NULL
);
-- الوسم القديم لا يُنقل: منحه كان يحتاج مفتاح المالك أصلاً، لكن ربطه
-- بمعرّف جهاز يجعل ادّعاءه ممكناً لمن يعرف المعرّف. يُصفَّر فيُعاد اكتسابه
-- بدخول واحد إلى اللوحة، ولا يُحتسب في سقف الأجهزة.
INSERT OR IGNORE INTO x_devices_new
  (install_id, device_id, owner_marked, owner_bound, first_seen, last_seen)
SELECT 'legacy:' || device_id, device_id, 0, 0, first_seen, last_seen
  FROM x_devices;
DROP TABLE x_devices;
ALTER TABLE x_devices_new RENAME TO x_devices;
CREATE INDEX IF NOT EXISTS x_devices_owner ON x_devices (owner_marked);
CREATE INDEX IF NOT EXISTS x_devices_install ON x_devices (install_id, owner_marked);

-- ── 3) ربط محفظة الزائر بالتثبيت الموثّق ──
-- محفظة الزائر كانت مفتاحها `x-device-fp` المُرسَل من العميل، وهو ليس سراً.
-- الربط يُخزَّن هنا مرة واحدة، وبعدها المفتاح يُقرأ من الجدول لا من الطلب.
-- البصمة المملوكة لتثبيت آخر لا تُتبنّى (فريد)، فلا تُسرق محفظة قائمة.
CREATE TABLE IF NOT EXISTS x_wallet_bindings (
  install_id TEXT PRIMARY KEY,
  wallet_key TEXT NOT NULL,
  bound_at   TEXT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS x_wallet_bindings_key ON x_wallet_bindings (wallet_key);
