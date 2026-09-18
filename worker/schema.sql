-- x-app-db — قاعدة بيانات تطبيق X الخاصة (معزولة تماماً عن phonex-mirror)
-- لا تُكتب أي بيانات هنا إلا من worker التطبيق x-app-api

CREATE TABLE IF NOT EXISTS x_users (
  id            TEXT PRIMARY KEY,
  username      TEXT UNIQUE NOT NULL,
  display_name  TEXT NOT NULL DEFAULT '',
  password_hash TEXT NOT NULL DEFAULT '',
  role          TEXT NOT NULL DEFAULT 'user',   -- owner | user | guest
  active        INTEGER NOT NULL DEFAULT 0,     -- الحسابات الجديدة تنتظر تفعيل المالك
  device_id     TEXT,
  expires_at    INTEGER NOT NULL DEFAULT 0,     -- 0 = بلا انتهاء
  quota_balance INTEGER NOT NULL DEFAULT 0,     -- رصيد بطاقات عرض المخططات
  quota_expires_at INTEGER NOT NULL DEFAULT 0,  -- انتهاء صلاحية البطاقات (0 = بلا انتهاء)
  created_at    TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS x_users_role ON x_users (role, active);

CREATE TABLE IF NOT EXISTS x_requests (
  id          TEXT PRIMARY KEY,
  username    TEXT NOT NULL,
  note        TEXT NOT NULL DEFAULT '',
  device_id   TEXT,
  status      TEXT NOT NULL DEFAULT 'pending',  -- pending | approved | rejected
  created_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS x_installs (
  install_id  TEXT PRIMARY KEY,
  device_id   TEXT,
  app_version TEXT NOT NULL DEFAULT 'unknown',
  first_seen  TEXT NOT NULL,
  last_seen   TEXT NOT NULL,
  last_ip     TEXT
);
CREATE INDEX IF NOT EXISTS x_installs_seen ON x_installs (last_seen);

CREATE TABLE IF NOT EXISTS x_settings (
  id   TEXT PRIMARY KEY,
  data TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS x_announcements (
  id   TEXT PRIMARY KEY,
  data TEXT NOT NULL
);

-- حظر دائم (جهاز أو IP) — مستقل عن تغيير العنوان
CREATE TABLE IF NOT EXISTS x_bans (
  id        TEXT PRIMARY KEY,   -- device_id أو ip
  kind      TEXT NOT NULL,      -- device | ip
  reason    TEXT NOT NULL DEFAULT '',
  permanent INTEGER NOT NULL DEFAULT 1,
  at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS x_security (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT,
  ip        TEXT,
  path      TEXT,
  reason    TEXT NOT NULL,
  detail    TEXT NOT NULL DEFAULT '',
  at        TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS x_security_at ON x_security (at);

-- ══════════════════════════════════════════════════════════════
-- الدردشة المجتمعية (مجموعة واحدة بأقسام) — لا رسائل خاصة بين الأفراد
-- ══════════════════════════════════════════════════════════════

-- ملفات تعريف الدردشة: كنية وصورة شخصية، منفصلة عن بيانات الحساب الرسمية
-- كي لا يغيّر المستخدم اسم حسابه من داخل الدردشة.
-- notify: كتم الإشعارات من جهة المستخدم نفسه (0 = مكتوم).
CREATE TABLE IF NOT EXISTS x_chat_profiles (
  user_id    TEXT PRIMARY KEY,
  nickname   TEXT NOT NULL DEFAULT '',
  avatar_key TEXT NOT NULL DEFAULT '',
  notify     INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL
);

-- آخر رسالة شاهدها كل مستخدم في كل قسم — أساس «من رأى الرسالة».
-- نحفظ ختماً زمنياً لا قائمة معرّفات: استعلام واحد صغير لكل قسم يكفي
-- لعرض صور المشاهدين، بدل صف لكل (مستخدم × رسالة).
CREATE TABLE IF NOT EXISTS x_chat_seen (
  user_id   TEXT NOT NULL,
  room_id   TEXT NOT NULL,
  last_at   INTEGER NOT NULL DEFAULT 0,
  seen_at   TEXT NOT NULL,
  PRIMARY KEY (user_id, room_id)
);
CREATE INDEX IF NOT EXISTS x_chat_seen_room ON x_chat_seen (room_id, last_at DESC);

-- الرسائل. room_id يفصل الأقسام، وkind يميّز النص عن الوسائط أو الرسائل
-- النظامية. الحذف ناعم (deleted) ليبقى الأثر للمالك ولا يفقد الحوار سياقه.
CREATE TABLE IF NOT EXISTS x_chat_messages (
  id         TEXT PRIMARY KEY,
  room_id    TEXT NOT NULL,
  user_id    TEXT NOT NULL,
  kind       TEXT NOT NULL DEFAULT 'text',   -- text | image | audio | video | system
  body       TEXT NOT NULL DEFAULT '',
  media_key  TEXT NOT NULL DEFAULT '',
  media_mime TEXT NOT NULL DEFAULT '',
  media_size INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  deleted    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS x_chat_room_time ON x_chat_messages (room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS x_chat_user ON x_chat_messages (user_id, created_at DESC);

-- إجراءات المالك: كتم دائم (mute) وطرد (kick). room_id فارغ = كل الأقسام.
CREATE TABLE IF NOT EXISTS x_chat_actions (
  id         TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  kind       TEXT NOT NULL,                  -- mute | kick
  room_id    TEXT NOT NULL DEFAULT '',
  reason     TEXT NOT NULL DEFAULT '',
  until      INTEGER NOT NULL DEFAULT 0,     -- 0 = بلا نهاية (للكتم)
  at         TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS x_chat_actions_user ON x_chat_actions (user_id, kind);
