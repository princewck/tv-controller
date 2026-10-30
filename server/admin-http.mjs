import {readFileSync} from 'node:fs';
import {scrypt as scryptCb,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
import {secret,hash,HttpError,dayOf} from './store.mjs';
import {validatePolicy,minuteCode} from './policy.mjs';
import {identityFor,scoped,installTenancy,passwordMatches} from './tenancy.mjs';
const scrypt=promisify(scryptCb),ADMIN_DAYS=120;
export const safeEqual=(a,b)=>typeof a==='string'&&typeof b==='string'&&Buffer.byteLength(a)===Buffer.byteLength(b)&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
const cookie=(req,key)=>(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith(key+'='))?.slice(key.length+1);
async function verifyPassword(password,file){
 if(typeof password!=='string'||password.length<1||password.length>128)return false;
 let config;try{config=JSON.parse(readFileSync(file,'utf8'));}catch{throw new HttpError(503,'Administrator not configured');}
 if(config.algorithm!=='scrypt-v1'||! /^[0-9a-f]{32}$/.test(config.salt)||! /^[0-9a-f]{128}$/.test(config.digest))throw new HttpError(503,'Invalid administrator credential configuration');
 const digest=await scrypt(password,Buffer.from(config.salt,'hex'),64,{N:16384,r:8,p:1,maxmem:64*1024*1024});
 return timingSafeEqual(digest,Buffer.from(config.digest,'hex'));
}
export function installAdmin(app,store,config,{origin,browser,csrf}){
 const file=config.adminPasswordFile||process.env.ADMIN_PASSWORD_FILE||'/etc/tv-parent-admin.json';
 const audit=(req,action,details={},tenant=req.identity?.tenant_id||'default')=>{
  store.run('INSERT INTO tenant_audit(tenant_id,actor,timestamp,action,details_json) VALUES(?,?,?,?,?)',tenant,req.identity?.username||'anonymous',store.clock(),action,JSON.stringify(details));
  // 旧审计仅保留默认家庭，供原有本地运维脚本兼容；普通家庭从不落入此表。
  if(tenant==='default')store.run('INSERT INTO admin_audit(timestamp,action,details_json) VALUES(?,?,?)',store.clock(),action,JSON.stringify(details));
 };
 const currentSession=req=>{const token=cookie(req,'__Host-tv_admin');return typeof token==='string'&&token.length<128?store.get('SELECT * FROM admin_sessions WHERE token_hash=? AND expires_ms>?',hash(token),store.clock()):null;};
 const requireAdmin=(req,res,next)=>{
  const session=currentSession(req),identity=identityFor(store,session);
  if(!identity)throw new HttpError(401,'Login required');req.admin=session;req.identity=identity;next();
 };
 const adminCsrf=(req,res,next)=>{if(!safeEqual(req.get('X-CSRF-Token'),req.admin.csrf))throw new HttpError(403,'Invalid CSRF token');next();};
 const attempts=new Map();let inFlight=0;
 app.post('/admin/login',origin,async(req,res)=>{
  const now=store.clock();let entry=attempts.get(req.ip);
  if(!entry||entry.until<=now){if(attempts.size>2048){for(const[k,v]of attempts)if(v.until<=now)attempts.delete(k);if(attempts.size>2048)throw new HttpError(503,'Busy');}entry={count:0,until:now+15*60_000};attempts.set(req.ip,entry);}
  if(entry.count>=6){res.set('Retry-After',String(Math.ceil((entry.until-now)/1000)));throw new HttpError(429,'Too many login attempts; try again later');}
  entry.count++;
  if(inFlight>=3)throw new HttpError(503,'Login busy; try again');
  let valid,user=null;const username=req.body.username??'admin';
  if(typeof username!=='string'||username.length>32)throw new HttpError(401,'Invalid username or password');
  inFlight++;try{
   if(username==='admin'||username==='')valid=await verifyPassword(req.body.password,file);
   else{
    user=store.get('SELECT u.* FROM users u JOIN tenants t USING(tenant_id) WHERE u.username=? AND u.enabled=1 AND t.enabled=1',username);
    // 未知用户也进行一次scrypt，减少通过响应耗时枚举账号的机会。
    const dummy={algorithm:'scrypt-v1',salt:'00'.repeat(16),digest:'00'.repeat(64)};
    valid=await passwordMatches(req.body.password,user?JSON.parse(user.password_json):dummy);if(!user)valid=false;
   }
  }finally{inFlight--;}
  if(!valid)throw new HttpError(401,'Invalid username or password');
  attempts.delete(req.ip);
  const token=secret(),csrf=secret(),expires=now+ADMIN_DAYS*86400_000;
  store.run('INSERT INTO admin_sessions VALUES(?,?,?,?)',hash(token),csrf,now,expires);
  res.cookie('__Host-tv_admin',token,{httpOnly:true,secure:true,sameSite:'strict',path:'/',maxAge:ADMIN_DAYS*86400_000});
  store.run('INSERT INTO admin_session_owners VALUES(?,?,?)',hash(token),user?.user_id||null,user?.tenant_id||'default');
  req.identity={role:user?'user':'superadmin',username:user?.username||'admin',tenant_id:user?.tenant_id||'default'};
  audit(req,'login_success');res.json({success:true,csrf,identity:req.identity,expires_ms:expires,server_now_ms:store.clock()});
 });
 app.get('/admin/session',requireAdmin,(req,res)=>res.json({authenticated:true,identity:req.identity,csrf:req.admin.csrf,expires_ms:req.admin.expires_ms,server_now_ms:store.clock()}));
 app.post('/admin/logout',origin,requireAdmin,adminCsrf,(req,res)=>{
  store.run('DELETE FROM admin_sessions WHERE token_hash=?',req.admin.token_hash);res.clearCookie('__Host-tv_admin',{httpOnly:true,secure:true,sameSite:'strict',path:'/'});audit(req,'logout');res.json({success:true});
 });
 // SSE只向已登录管理员推送正式设备心跳；电视端继续使用有界HTTPS请求。
 let streamCount=0;const principalStreams=new Map();
 app.get('/admin/heartbeat_stream',requireAdmin,(req,res)=>{
  const scope=scoped(store,req,{device:true}),DEVICE=scope.device;
  const principal=req.identity.user_id||'superadmin',limit=req.identity.role==='superadmin'?10:4;
  if((principalStreams.get(principal)||0)>=limit)throw new HttpError(429,'Too many live connections for this account');
  if(streamCount>=50)throw new HttpError(503,'Too many live connections');
  streamCount++;principalStreams.set(principal,(principalStreams.get(principal)||0)+1);
  res.set({'Content-Type':'text/event-stream; charset=utf-8','Cache-Control':'no-store','X-Accel-Buffering':'no'});
  res.flushHeaders();
  const send=(event,data)=>res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
  const last=store.get('SELECT last_heartbeat_ms FROM devices WHERE device_name=?',DEVICE)?.last_heartbeat_ms??null;
  send('snapshot',{device:DEVICE,received_ms:last,server_now_ms:store.clock()});
  let closed=false;
  const cleanup=()=>{if(closed)return;closed=true;streamCount--;const remaining=(principalStreams.get(principal)||1)-1;if(remaining)principalStreams.set(principal,remaining);else principalStreams.delete(principal);clearInterval(timer);store.events.off('heartbeat',onHeartbeat);store.events.off('shutdown',end);};
  const end=()=>{cleanup();res.end();};
  const onHeartbeat=data=>{if(!identityFor(store,currentSession(req))){end();return;}if(data.device===DEVICE&&!res.write(`event: heartbeat\ndata: ${JSON.stringify({...data,server_now_ms:store.clock()})}\n\n`))end();};
  const timer=setInterval(()=>{
   if(!identityFor(store,currentSession(req))){send('expired',{});end();return;}
   res.write(': keepalive\n\n');
  },15_000);timer.unref();
  store.events.on('heartbeat',onHeartbeat);store.events.on('shutdown',end);
  res.on('close',cleanup);
 });
 app.get('/admin/config',requireAdmin,(req,res)=>{const scope=scoped(store,req);res.json({policy:store.policy.configForTenant(scope.tenant),device:scope.device,tenant:scope.tenant,server_now_ms:store.clock()});});
 app.post('/admin/config',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req),policy=validatePolicy(req.body.policy);
  store.tx(()=>{
   if(scope.tenant==='default')store.run('INSERT INTO policy_settings VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET config_json=excluded.config_json,updated_ms=excluded.updated_ms',JSON.stringify(policy),store.clock());
   else store.run('INSERT INTO tenant_policies VALUES(?,?,?) ON CONFLICT(tenant_id) DO UPDATE SET config_json=excluded.config_json,updated_ms=excluded.updated_ms',scope.tenant,JSON.stringify(policy),store.clock());
   audit(req,'policy_changed',{policy},scope.tenant);
  });res.json({success:true,policy});
 });
 app.post('/admin/grant',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req,{device:true}),seconds=req.body.seconds??store.policy.config(scope.device).default_grant_seconds;
  const result=store.tx(()=>{const value=store.policy.grant(scope.device,seconds,'admin');audit(req,'temporary_grant',{device:scope.device,seconds},scope.tenant);return value;});
  res.json({...result,...store.state(scope.device)});
 });
 app.get('/admin/stats',requireAdmin,(req,res)=>{
  const scope=scoped(store,req),DEVICE=scope.device;
  const now=store.clock(),today=dayOf(now),start=Date.parse(today+'T00:00:00+08:00')/1000-29*86400;
  const daily=store.db.prepare("SELECT date(timestamp,'unixepoch','+8 hours') day,app_package,SUM(duration_seconds) seconds FROM usage_events WHERE device_name=? AND timestamp>=? GROUP BY day,app_package ORDER BY day,app_package").all(DEVICE,start);
  // 20秒以内连续同应用采样合并为一个区段；这是采样观看区段，不冒充逐帧播放日志。
  const timeline=store.db.prepare(`WITH ordered AS (
    SELECT *,LAG(timestamp+duration_seconds) OVER(ORDER BY timestamp,id) previous_end,LAG(app_package) OVER(ORDER BY timestamp,id) previous_app FROM usage_events WHERE device_name=? AND timestamp>=?
   ), flags AS (SELECT *,CASE WHEN previous_app=app_package AND timestamp-previous_end<=20 AND date(timestamp,'unixepoch','+8 hours')=date(previous_end,'unixepoch','+8 hours') THEN 0 ELSE 1 END marker FROM ordered),
   grouped AS (SELECT *,SUM(marker) OVER(ORDER BY timestamp,id) group_id FROM flags)
   SELECT app_package,MIN(timestamp) start_seconds,MAX(timestamp+duration_seconds) end_seconds,SUM(duration_seconds) watched_seconds FROM grouped GROUP BY group_id,app_package ORDER BY start_seconds DESC LIMIT 2000`).all(DEVICE,start);
  const math=store.db.prepare('SELECT * FROM math_sessions WHERE device_name=? AND opened_ms>=? ORDER BY opened_ms DESC LIMIT 300').all(DEVICE,start*1000);
  res.json({device:DEVICE,today,days:30,daily,timeline,math,state:DEVICE?store.state(DEVICE):{stage:0,remaining_seconds:0,rest_until_ms:null},server_now_ms:now,
   admin_audit:scope.tenant==='default'?store.db.prepare('SELECT timestamp,action,details_json FROM admin_audit ORDER BY timestamp DESC LIMIT 50').all():store.db.prepare('SELECT timestamp,action,details_json FROM tenant_audit WHERE tenant_id=? ORDER BY timestamp DESC LIMIT 50').all(scope.tenant)});
 });
 installTenancy(app,store,{origin,requireAdmin,adminCsrf,audit,hashWork:async fn=>{
  if(inFlight>=3)throw new HttpError(503,'Password service busy');inFlight++;try{return await fn();}finally{inFlight--;}
 }});
 app.post('/adult_verify',origin,browser,csrf,(req,res)=>{
  const session=req.session,body=req.body;
  if(!/^[0-9a-f-]{36}$/i.test(body.attempt_id||'')||typeof body.code!=='string'||!/^\d{12}$/.test(body.code))throw new HttpError(400,'Invalid adult verification');
  const result=store.tx(()=>{
   const receipt=store.get('SELECT response_json FROM answer_receipts WHERE session_hash=? AND attempt_id=?',session.token_hash,body.attempt_id);
   if(receipt){const parsed=JSON.parse(receipt.response_json);if(parsed.kind!=='adult')throw new HttpError(409,'Attempt ID reused');return {...parsed,...store.state(session.device_name),duplicate:true};}
   const fresh=store.sessionByHash(session.token_hash),now=store.clock();
   if(now-fresh.last_answer_ms<1500)throw new HttpError(429,'Verification too frequent');
   // 日期验证码是用户指定的弱确认方式，不等同于管理员身份；不返回正确验证码。
   if(!safeEqual(body.code,minuteCode(now))){
    // 错误尝试的限频需提交，因此不在事务内抛异常回滚该记录。
    store.run('UPDATE browser_sessions SET last_answer_ms=? WHERE token_hash=?',now,session.token_hash);
    store.run("UPDATE math_sessions SET answer_count=answer_count+1,wrong_count=wrong_count+1 WHERE device_name=? AND status='open'",session.device_name);
    store.audit(session.device_name,'adult_verify_failed');
    return {error:'日期时间验证码不匹配，请使用北京时间当前年月日时分',invalid:true};
   }
   if(store.state(session.device_name).lock_reason!=='restricted_time')throw new HttpError(409,'Adult verification not required');
   store.run("UPDATE math_sessions SET answer_count=answer_count+1 WHERE device_name=? AND status='open'",session.device_name);
   const seconds=store.policy.config(session.device_name).default_grant_seconds;
   const value={kind:'adult',...store.policy.grant(session.device_name,seconds,'adult'),...store.state(session.device_name)};
   store.run('INSERT INTO answer_receipts VALUES(?,?,?,?)',session.token_hash,body.attempt_id,JSON.stringify(value),now);return value;
  });
  res.status(result.invalid?403:200).json(result);
 });
}
