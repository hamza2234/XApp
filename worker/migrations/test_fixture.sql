-- بيانات اختبار تشغيلي: دورة مقفلة بفيديو، لتثبيت أن القفل لا يُفتح
-- بمعرّف جهاز منتحَل. تُطبَّق بعد schema.sql وmigrations/0001.
INSERT OR IGNORE INTO x_courses
  (id, title, subtitle, description, cover_key, locked, sort, published,
   created_at, updated_at)
VALUES
  ('c_locked', 'دورة مقفلة', '', '', '', 1, 1, 1,
   '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z');

INSERT OR IGNORE INTO x_course_videos
  (id, course_id, title, description, object_key, mime, duration_s,
   size_bytes, mode, sort, published, created_at, thumb_key)
VALUES
  ('v_locked', 'c_locked', 'فيديو مقفل', '', 'learn/v_locked.mp4', 'video/mp4',
   120, 1024, 'locked', 1, 1, '2026-01-01T00:00:00Z', '');
