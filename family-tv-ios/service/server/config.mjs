export const ORIGIN = 'https://tv.example.com';
export const DEFAULT_APPS = ['com.ktcp.video','com.xiaodianshi.tv.yst','com.newtv.cboxtv',
  'com.google.android.youtube.tv','com.fongmi.android.tv','com.gitvdemo.video','com.hunantv.license'];
export function loadConfig(env=process.env) {
  if (env.PUBLIC_ORIGIN && env.PUBLIC_ORIGIN !== ORIGIN) throw new Error('唯一允许域名是 '+ORIGIN);
  const positive=(key,fallback,max)=>{
    const value=Number(env[key]??fallback);
    if (!Number.isInteger(value)||value<1||value>max) throw new Error('无效配置：'+key);
    return value;
  };
  const apps=(env.MONITORED_APPS||DEFAULT_APPS.join(',')).split(',');
  if (!apps.length || apps.some(x=>!/^\w+(?:\.\w+)+$/.test(x))) throw new Error('MONITORED_APPS格式错误');
  return {origin:ORIGIN, port:positive('PORT',3000,65535),
    databasePath:env.DATABASE_PATH||'runtime/control.sqlite',
    dailyLimit:positive('DAILY_LIMIT_SECONDS',1800,86400),
    reward:positive('REWARD_SECONDS',1200,86400), monitoredApps:new Set(apps)};
}
