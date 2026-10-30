-- 答题追溯：本地上海时间、实际完成时长、当前仍未完成时长；单位秒。
-- opened是网页通过启动票据认证/已存在合法会话请求lock_status的服务端确认时间，非物理屏幕像素证明。
SELECT id,device_name,day,
 datetime(opened_ms/1000,'unixepoch','+8 hours') AS opened_at,
 datetime(completed_ms/1000,'unixepoch','+8 hours') AS completed_at,
 status,
 CASE WHEN completed_ms IS NOT NULL THEN (completed_ms-opened_ms)/1000.0 ELSE NULL END AS duration_seconds,
 CASE WHEN completed_ms IS NULL THEN (unixepoch()*1000-opened_ms)/1000.0 ELSE NULL END AS unfinished_seconds,
 answer_count,wrong_count,reward_seconds
FROM math_sessions ORDER BY opened_ms DESC;
-- 原始状态事件：SELECT * FROM control_events ORDER BY timestamp DESC;
