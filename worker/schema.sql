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
