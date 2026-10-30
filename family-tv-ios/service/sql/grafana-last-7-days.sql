-- 最近7个上海自然日（包含今天），不强行按周一重新排序，保留时间顺序。
SELECT unixepoch(date(timestamp,'unixepoch','+8 hours')||'T00:00:00+08:00') AS time,
       app_package AS app,SUM(duration_seconds)/60.0 AS minutes
FROM usage_events
WHERE device_name='Xiaomi_HyperOS_TV' AND timestamp>=unixepoch(date('now','+8 hours','-6 days')||'T00:00:00+08:00')
  AND timestamp<unixepoch(date('now','+8 hours','+1 day')||'T00:00:00+08:00')
GROUP BY time,app_package
ORDER BY time,app;
