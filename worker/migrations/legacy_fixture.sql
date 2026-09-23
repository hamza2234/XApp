-- قاعدة بالشكل القديم (قبل الترقية): المفتاح device_id، ووسم مالك قائم.
-- تُستعمل للتأكد أن الترقية لا تُبقي وسم المالك مربوطاً بمعرّف يرسله العميل.
CREATE TABLE x_course_grants (
  device_id  TEXT NOT NULL,
  course_id  TEXT NOT NULL,
  key_id     TEXT NOT NULL DEFAULT '',
  user_id    TEXT NOT NULL DEFAULT '',
  at         INTEGER NOT NULL,
  PRIMARY KEY (device_id, course_id)
);

CREATE TABLE x_devices (
  device_id    TEXT PRIMARY KEY,
  owner_marked INTEGER NOT NULL DEFAULT 0,
  owner_bound  INTEGER NOT NULL DEFAULT 0,
  first_seen   TEXT NOT NULL,
  last_seen    TEXT NOT NULL
);

-- جهاز مالك موثّق فعلاً قبل الترقية (وسم صحيح من دخول لوحة سابق).
INSERT INTO x_devices VALUES
  ('ownerphone123', 1, 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');

-- منحة مشتركة قائمة على معرّف جهاز.
INSERT INTO x_course_grants VALUES
  ('subscriberphone', 'c_locked', 'k_1', 'u_1', 1700000000000);
