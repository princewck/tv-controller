-- SQLite + frser-sqlite-datasource；上一完整自然周（周一00:00至本周一00:00），上海时区。
-- Grafana设置Time series，time字段为Unix秒，app为系列；条形图Stacking=Normal。
-- 原始观看流水保留，充值不抵消统计。minutes精确到所记录的秒，不代表物理播放逐秒精确。
WITH RECURSIVE
clock AS (SELECT date('now','+8 hours') AS today),
this_week AS (
 SELECT date(today,printf('-%d days',(CAST(strftime('%w',today) AS INTEGER)+6)%7)) AS monday FROM clock
),
bounds AS (SELECT date(monday,'-7 days') AS first_day,monday AS after_last FROM this_week),
days(day,n) AS (
 SELECT first_day,0 FROM bounds
 UNION ALL SELECT date(day,'+1 day'),n+1 FROM days WHERE n<6
),
apps(package,label) AS (VALUES
 ('com.ktcp.video','腾讯视频'),('com.xiaodianshi.tv.yst','哔哩哔哩'),
 ('com.gitvdemo.video','银河奇异果'),('com.newtv.cboxtv','央视频'),
 ('com.google.android.youtube.tv','YouTube'),('com.fongmi.android.tv','OK影视'),
 ('com.hunantv.license','芒果TV')
),
usage AS (
 SELECT date(timestamp,'unixepoch','+8 hours') AS day,app_package,SUM(duration_seconds) AS seconds
 FROM usage_events,bounds
 WHERE device_name='Xiaomi_HyperOS_TV' AND timestamp>=unixepoch(first_day||'T00:00:00+08:00')
   AND timestamp<unixepoch(after_last||'T00:00:00+08:00')
 GROUP BY day,app_package
)
SELECT unixepoch(days.day||'T00:00:00+08:00') AS time,
 apps.label AS app,COALESCE(usage.seconds,0)/60.0 AS minutes
FROM days CROSS JOIN apps LEFT JOIN usage ON usage.day=days.day AND usage.app_package=apps.package
ORDER BY time,app;
