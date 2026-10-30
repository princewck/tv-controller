import {randomUUID,randomBytes} from 'node:crypto';
import {HTTPError,secret,hash,passwordRecord,passwordMatches,bodyOf,rateLimit,sessionFor,requireOrigin,requireCSRF,cookie,json} from './security.mjs';
import {DEFAULT_POLICY,validatePolicy,dayOf,stateFor} from './policy.mjs';
import {subscriptionStatus,saveTransaction,subscriptionOwner} from './subscriptions.mjs';
const APPS=new Set(['com.ktcp.video','com.xiaodianshi.tv.yst','com.newtv.cboxtv','com.google.android.youtube.tv','com.fongmi.android.tv','com.gitvdemo.video','com.hunantv.license']);
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const sessionTTL=30*86400000;
const identity=s=>({username:s.username,role:'user',tenant_id:s.household_id});
function healthFor(d,now){
 const fresh=d.last_heartbeat_ms!==null&&now-d.last_heartbeat_ms>=-5000&&now-d.last_heartbeat_ms<45000;
 const checks={connected:fresh&&d.enabled===1,playback_test:d.stopped_ms!==null&&d.resumed_ms>d.stopped_ms,permissions:fresh&&d.permissions_ok===1,adb_closed:fresh&&d.adb_enabled===0,rebooted:fresh&&d.closed_at_boot!==null&&d.boot_count>d.closed_at_boot};
 return {device:d.id,checks,complete:Object.values(checks).every(Boolean),updated_ms:d.last_heartbeat_ms};
}
async function ownDevice(db,s,url){
 const id=url.searchParams.get('device');
 const row=id?await db.prepare('SELECT * FROM devices WHERE id=? AND household_id=?').bind(id,s.household_id).first():await db.prepare('SELECT * FROM devices WHERE household_id=? ORDER BY created_ms,id LIMIT 1').bind(s.household_id).first();
 if(!row)throw new HTTPError(404,'Device not found');return row;
}
async function newSession(db,household,username,now){
 const token=secret(),csrf=secret(),expires=now+sessionTTL;
 await db.prepare('INSERT INTO sessions VALUES(?,?,?,?)').bind(hash(token),household,csrf,expires).run();
 return {token,value:{csrf,identity:{username,role:'user',tenant_id:household},expires_ms:expires}};
}
async function operation(db,s,device,kind,payload,requestID,now){
 if(!UUID.test(requestID||''))throw new HTTPError(400,'Request ID required');
 const body=JSON.stringify(payload),digest=hash(body);
 const result=await db.prepare('INSERT INTO operations VALUES(?,?,?,?,?,?,?) ON CONFLICT(household_id,request_id) DO NOTHING').bind(s.household_id,requestID,kind,device.id,digest,body,now).run();
 const existing=await db.prepare('SELECT kind,device_id,body_hash FROM operations WHERE household_id=? AND request_id=?').bind(s.household_id,requestID).first();
 if(existing.kind!==kind||existing.device_id!==device.id||existing.body_hash!==digest)throw new HTTPError(409,'Request ID reused');
 return {duplicate:result.meta.changes===0,device:await db.prepare('SELECT * FROM devices WHERE id=?').bind(device.id).first()};
}
async function heartbeat(db,request,body,now,env){
 const bearer=request.headers.get('authorization');
 if(!bearer?.startsWith('Bearer ')||bearer.length>140)throw new HTTPError(401,'Device authentication required');
 const d=await db.prepare('SELECT d.*,h.policy_json FROM devices d JOIN households h ON h.id=d.household_id WHERE token_hash=? AND enabled=1').bind(hash(bearer.slice(7))).first();
 if(!d)throw new HTTPError(401,'Invalid device token');
 if(body.device!==d.id)throw new HTTPError(403,'Device mismatch');
 if(typeof body.is_playing!=='boolean'||!UUID.test(body.event_id||'')||!/^[A-Za-z0-9_.-]{1,180}$/.test(body.app||''))throw new HTTPError(400,'Invalid heartbeat');
 const duplicate=await db.prepare('SELECT 1 FROM heartbeat_receipts WHERE device_id=? AND event_id=?').bind(d.id,body.event_id).first();
 if(duplicate)return {...await stateFor(db,d,JSON.parse(d.policy_json),now),duplicate:true};
 if(d.last_heartbeat_ms!==null&&now-d.last_heartbeat_ms<8000)throw new HTTPError(429,'Heartbeat too frequent');
 const samples=body.usage_samples;
 if(samples!==undefined&&(!Array.isArray(samples)||samples.length>64))throw new HTTPError(400,'Invalid usage samples');
 for(const sample of samples??[])if(!UUID.test(sample.id||'')||!APPS.has(sample.app)||!Number.isInteger(sample.seconds)||sample.seconds<1||sample.seconds>10||!Number.isSafeInteger(sample.at_ms)||sample.at_ms>now+30000||sample.at_ms<now-2*86400000||sample.day!==dayOf(sample.at_ms)||!/^\d{4}-\d{2}-\d{2}$/.test(sample.day)||sample.day>dayOf(now)||sample.day<dayOf(now-2*86400000))throw new HTTPError(400,'Invalid usage sample');
 const seconds=samples!==undefined?0:d.last_heartbeat_ms===null?10:Math.max(0,Math.min(10,Math.floor((now-d.last_heartbeat_ms)/1000)));
 const today=dayOf(now),previous=dayOf(now-86400000),start=Date.parse(today+'T00:00:00+08:00');
 const current=Math.min(seconds,Math.max(0,Math.floor((now-start)/1000)));
 const receipt=db.prepare(`INSERT INTO heartbeat_receipts SELECT ?,?,?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM devices WHERE id=? AND (last_heartbeat_ms IS NULL OR last_heartbeat_ms<=?)) ON CONFLICT(device_id,event_id) DO NOTHING`).bind(d.id,body.event_id,now,today,previous,APPS.has(body.app)?body.app:'android',seconds,current,body.is_playing&&APPS.has(body.app)?1:0,d.id,now-8000);
 const revision=body.applied_revision;
 if(revision!==undefined&&(!Number.isSafeInteger(revision)||revision<0||revision>d.revision||!['allowed','stopped','observing','failed'].includes(body.enforcement_result)))throw new HTTPError(400,'Invalid execution receipt');
 const applied=revision!==undefined&&revision>=d.applied_revision;
 const currentRevision=revision===d.revision;
 const boot=Number.isInteger(body.boot_count)&&body.boot_count>=0?body.boot_count:null;
 const adb=[0,1].includes(body.adb_enabled)?body.adb_enabled:null;
 const permissions=typeof body.permissions_ok==='boolean'?Number(body.permissions_ok):null;
 const statements=[receipt,db.prepare(`UPDATE devices SET boot_count=?,initial_boot=COALESCE(initial_boot,?),closed_at_boot=CASE WHEN ?=1 THEN NULL WHEN ?=0 THEN COALESCE(closed_at_boot,?) ELSE closed_at_boot END,adb_enabled=?,permissions_ok=?,applied_revision=CASE WHEN ? THEN ? ELSE applied_revision END,enforcement_result=CASE WHEN ? THEN ? ELSE enforcement_result END,applied_ms=CASE WHEN ? THEN ? ELSE applied_ms END,stopped_ms=CASE WHEN ? THEN ? ELSE stopped_ms END,resumed_ms=CASE WHEN ? THEN ? ELSE resumed_ms END WHERE id=? AND last_heartbeat_ms=?`).bind(boot,boot,adb,adb,boot,adb,permissions,Number(applied),revision??0,Number(applied),body.enforcement_result??null,Number(applied),now,Number(currentRevision&&body.enforcement_result==='stopped'&&body.playback_stop_verified===true),now,Number(currentRevision&&body.enforcement_result==='allowed'&&body.is_playing&&APPS.has(body.app)),now,d.id,now)];
 for(const sample of samples??[])statements.push(db.prepare('INSERT INTO usage_samples VALUES(?,?,?,?,?,?) ON CONFLICT(device_id,event_id) DO NOTHING').bind(d.id,sample.id,sample.day,sample.app,sample.seconds,sample.at_ms));
 const results=await db.batch(statements);
 if(results[0].meta.changes===0)throw new HTTPError(429,'Heartbeat raced; retry later');
 const fresh=await db.prepare('SELECT d.*,h.policy_json FROM devices d JOIN households h ON h.id=d.household_id WHERE d.id=?').bind(d.id).first();
 const state=await stateFor(db,fresh,JSON.parse(fresh.policy_json),now);
 // New clients enforce cached policy and report actual playback; the URL also
 // supports existing WebView agents until the native offline screen is installed.
 if(state.status==='lock')state.launch_url=env.PUBLIC_ORIGIN+'/tv-rest';
 if(samples!==undefined)state.accepted_usage_ids=samples.map(x=>x.id);
 return state;
}
export function createHandler({verifyTransaction,verifyNotification,verifyAppTransaction,clock=Date.now}){
 return async function handle(request,env){
  const db=env.DB,url=new URL(request.url),path=url.pathname,now=clock();
  try{
   if(!db)throw new HTTPError(503,'Service storage unavailable');
   if(path==='/tv-rest'&&request.method==='GET')return new Response('<!doctype html><html lang=zh-CN><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1"><title>电视休息时间</title><body style="background:#123f34;color:white;font:32px system-ui;text-align:center;padding:12vh 10vw"><h1>电视休息一下</h1><p>请家长在手机上调整观看时间。</p><p>恢复后可返回视频继续观看。</p></body></html>',{headers:{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'"}});
   const post=request.method==='POST';
   if(!['GET','POST'].includes(request.method))throw new HTTPError(405,'Method not allowed');
   const ip=request.headers.get('CF-Connecting-IP')||'local';
   await rateLimit(db,'api:'+ip,180,60000,now);
   const body=post?await bodyOf(request):null;
   if(path==='/healthz'&&!post){await db.prepare('SELECT 1').first();return json({status:'ok',service:'familytv-cloud',version:1});}
   if(path==='/heartbeat'&&post)return json(await heartbeat(db,request,body,now,env));
   if(path==='/device/status'&&!post){
    const bearer=request.headers.get('authorization');if(!bearer?.startsWith('Bearer ')||bearer.length>140)throw new HTTPError(401,'Device authentication required');
    const d=await db.prepare('SELECT d.*,h.policy_json FROM devices d JOIN households h ON h.id=d.household_id WHERE token_hash=? AND enabled=1').bind(hash(bearer.slice(7))).first();if(!d)throw new HTTPError(401,'Invalid device token');
    return json({...healthFor(d,now),protocol_version:2,last_heartbeat_ms:d.last_heartbeat_ms,permissions_ok:d.permissions_ok===1,boot_count:d.boot_count,adb_enabled:d.adb_enabled,state:await stateFor(db,d,JSON.parse(d.policy_json),now)});
   }
   if(path==='/admin/register'&&post){
    requireOrigin(request,env.PUBLIC_ORIGIN);await rateLimit(db,'register:'+ip,3,3600000,now);
    const {username,password}=body;
    if(typeof username!=='string'||!/^[a-z0-9][a-z0-9_.-]{2,31}$/.test(username)||['admin','root'].includes(username))throw new HTTPError(400,'Choose a 3..32 character username');
    const credential=await passwordRecord(password),id=randomUUID(),recovery=secret();
    try{await db.prepare('INSERT INTO households VALUES(?,?,?,?,?,?)').bind(id,username,credential,hash(recovery),JSON.stringify(DEFAULT_POLICY),now).run();}
    catch(e){if(String(e).includes('UNIQUE'))throw new HTTPError(409,'Username unavailable');throw e;}
    const session=await newSession(db,id,username,now);
    return json({...session.value,recovery_code:recovery},201,{'Set-Cookie':cookie(session.token,sessionTTL/1000)});
   }
   if(path==='/admin/login'&&post){
    requireOrigin(request,env.PUBLIC_ORIGIN);await rateLimit(db,'login:'+ip,6,15*60000,now);
    const user=typeof body.username==='string'?await db.prepare('SELECT * FROM households WHERE username=?').bind(body.username).first():null;
    const valid=await passwordMatches(body.password,user?.password_json||JSON.stringify({salt:'00'.repeat(16),digest:'00'.repeat(64)}));
    if(!user||!valid)throw new HTTPError(401,'Invalid username or password');
    const session=await newSession(db,user.id,user.username,now);return json(session.value,200,{'Set-Cookie':cookie(session.token,sessionTTL/1000)});
   }
   if(path==='/admin/recover'&&post){
    requireOrigin(request,env.PUBLIC_ORIGIN);await rateLimit(db,'recover:'+ip,3,3600000,now);
    const user=await db.prepare('SELECT * FROM households WHERE username=? AND recovery_hash=?').bind(typeof body.username==='string'?body.username:'',hash(typeof body.recovery_code==='string'?body.recovery_code:'')).first();
    if(!user)throw new HTTPError(401,'Invalid recovery information');
    const credential=await passwordRecord(body.password),recovery=secret();
    const changed=await db.prepare('UPDATE households SET password_json=?,recovery_hash=? WHERE id=? AND recovery_hash=? RETURNING id').bind(credential,hash(recovery),user.id,hash(body.recovery_code)).first();
    if(!changed)throw new HTTPError(401,'Recovery code already used');
    return json({success:true,recovery_code:recovery});
   }
   if(path==='/installation/redeem'&&post){
    await rateLimit(db,'redeem:'+ip,10,60000,now);
    const code=typeof body.code==='string'?body.code.replace(/[-\s]/g,'').toUpperCase():'';
    if(!/^[0-9A-F]{16}$/.test(code))throw new HTTPError(400,'Invalid installation code');
    const token=secret();
    // Updating the token and marking the ticket share a SQLite trigger transaction. The
    // conditional UPDATE...RETURNING ensures two agents cannot both redeem it.
    const ticket=await db.prepare('UPDATE installation_tickets SET redeemed_ms=?,redeem_token_hash=? WHERE code_hash=? AND redeemed_ms IS NULL AND expires_ms>? AND EXISTS(SELECT 1 FROM devices WHERE id=device_id AND enabled=1) RETURNING device_id').bind(now,hash(token),hash(code),now).first();
    if(!ticket)throw new HTTPError(410,'Installation code expired or used');
    return json({device:ticket.device_id,token,origin:env.PUBLIC_ORIGIN});
   }
   if(path==='/apple/notifications'&&post){
    const notification=await verifyNotification(body.signedPayload,env);
    const jws=notification.data?.signedTransactionInfo;
    if(jws){const transaction=await verifyTransaction(jws,env),bound=await subscriptionOwner(db,transaction.originalTransactionId),household=bound?.household_id??transaction.appAccountToken;
     if(typeof household==='string'&&await db.prepare('SELECT 1 FROM households WHERE id=?').bind(household).first())await saveTransaction(db,transaction,household,env,now);
    }return json({success:true});
   }
   if(!path.startsWith('/admin/'))throw new HTTPError(404,'Not found');
   const s=await sessionFor(db,request,now);
   if(post){requireOrigin(request,env.PUBLIC_ORIGIN);requireCSRF(request,s);}
   if(path==='/admin/session'&&!post)return json({...identity(s),identity:identity(s),csrf:s.csrf,expires_ms:s.expires_ms});
   if(path==='/admin/logout'&&post){await db.prepare('DELETE FROM sessions WHERE token_hash=?').bind(s.token_hash).run();return json({success:true},200,{'Set-Cookie':cookie('',0)});}
   if(path==='/admin/mobile_capabilities'&&!post)return json({version:2,pause:true,daily_limit:true,execution_receipts:true,household_delete:true,staged_rules:false,registration:true,paid_history:true});
   if(path==='/admin/config'){
    if(!post)return json({policy:JSON.parse(s.policy_json)});
    const policy=validatePolicy(body.policy);
    await db.batch([db.prepare('UPDATE households SET policy_json=? WHERE id=?').bind(JSON.stringify(policy),s.household_id),db.prepare('UPDATE devices SET revision=revision+1 WHERE household_id=?').bind(s.household_id)]);
    return json({success:true,policy});
   }
   if(path==='/admin/devices'&&!post){const value=await db.prepare('SELECT id device_name,label,enabled,last_heartbeat_ms FROM devices WHERE household_id=? ORDER BY created_ms,id').bind(s.household_id).all();return json({devices:value.results,server_now_ms:now});}
   if(path==='/admin/installation_ticket'&&post){
    const label=body.label;
    if(typeof label!=='string'||!label.trim()||label.length>64)throw new HTTPError(400,'Device name required');
    const requested=body.device;
    if(requested!==undefined&&(typeof requested!=='string'||!await db.prepare('SELECT 1 FROM devices WHERE id=? AND household_id=?').bind(requested,s.household_id).first()))throw new HTTPError(404,'Device not found');
    const id=requested||'tv_'+randomUUID().replaceAll('-',''),code=randomBytes(8).toString('hex').toUpperCase(),expires=now+15*60000;
    if(requested&&await db.prepare('SELECT 1 FROM installation_tickets WHERE device_id=? AND redeemed_ms IS NOT NULL').bind(id).first())throw new HTTPError(409,'Installation code already redeemed; continue health checks');
    const result=await db.batch([
     ...(requested?[]:[db.prepare(`INSERT INTO devices(id,household_id,label,token_hash,created_ms) SELECT ?,?,?,?,? WHERE (SELECT COUNT(*) FROM devices WHERE household_id=?)<10`).bind(id,s.household_id,label.trim(),hash(secret()),now,s.household_id)]),
     db.prepare('DELETE FROM installation_tickets WHERE device_id=? AND redeemed_ms IS NULL').bind(id),
     db.prepare(`INSERT INTO installation_tickets SELECT ?,?,?,NULL,NULL WHERE EXISTS(SELECT 1 FROM devices WHERE id=?) AND NOT EXISTS(SELECT 1 FROM installation_tickets WHERE device_id=? AND redeemed_ms IS NOT NULL)`).bind(hash(code),id,expires,id,id)
    ]);
    if(!result.at(-1).meta.changes)throw new HTTPError(409,requested?'Installation already redeemed':'Maximum 10 devices');
    return json({code,device:id,label:label.trim(),origin:env.PUBLIC_ORIGIN,expires_ms:expires},201);
   }
   if(path==='/admin/subscription'){
    if(!post)return json(await subscriptionStatus(db,s.household_id,now));
    const transaction=await verifyTransaction(body.signed_transaction,env);
    const appTransaction=body.signed_app_transaction?await verifyAppTransaction(body.signed_app_transaction,env):undefined;
    return json(await saveTransaction(db,transaction,s.household_id,env,now,{appTransaction}));
   }
   if(path==='/admin/delete_household'&&post){
    await rateLimit(db,'delete:'+s.household_id,5,3600000,now);
    const user=await db.prepare('SELECT password_json FROM households WHERE id=?').bind(s.household_id).first();
    if(body.confirmation!=='DELETE'||!await passwordMatches(body.password,user.password_json))throw new HTTPError(403,'Password confirmation required');
    await db.prepare('DELETE FROM households WHERE id=?').bind(s.household_id).run();return json({success:true},200,{'Set-Cookie':cookie('',0)});
   }
   const d=await ownDevice(db,s,url),policy=JSON.parse(s.policy_json);
   if(path==='/admin/stats'&&!post){
    const premium=await subscriptionStatus(db,s.household_id,now),today=dayOf(now),start=premium.active?dayOf(now-29*86400000):today;
    const daily=await db.prepare('SELECT day,app_package,seconds FROM daily_usage WHERE device_id=? AND day>=? ORDER BY day,app_package').bind(d.id,start).all();
    return json({today,daily:daily.results,state:await stateFor(db,d,policy,now),server_now_ms:now,premium:premium.active});
   }
   if(path==='/admin/control'){
    if(!post)return json(await stateFor(db,d,policy,now));
    if(typeof body.paused!=='boolean')throw new HTTPError(400,'Boolean paused required');
    const result=await operation(db,s,d,'pause',{paused:body.paused?1:0},body.request_id,now);return json({...await stateFor(db,result.device,policy,now),duplicate:result.duplicate});
   }
   if(path==='/admin/grant'&&post){
    if(!Number.isInteger(body.seconds)||body.seconds<60||body.seconds>7200)throw new HTTPError(400,'Grant must be 1..120 minutes');
    const result=await operation(db,s,d,'grant',{seconds:body.seconds},body.request_id,now);return json({...await stateFor(db,result.device,policy,now),duplicate:result.duplicate});
   }
   if(path==='/admin/installation_status'&&!post){
    return json(healthFor(d,now));
   }
   if(path==='/admin/device_update'&&post){
    const statements=[];
    if(body.label!==undefined){if(typeof body.label!=='string'||!body.label.trim()||body.label.length>64)throw new HTTPError(400,'Invalid name');statements.push(db.prepare('UPDATE devices SET label=? WHERE id=?').bind(body.label.trim(),d.id));}
    if(body.enabled!==undefined){if(typeof body.enabled!=='boolean')throw new HTTPError(400,'Invalid enabled');statements.push(db.prepare('UPDATE devices SET enabled=?,revision=revision+1 WHERE id=?').bind(Number(body.enabled),d.id));}
    if(!statements.length)throw new HTTPError(400,'No change');await db.batch(statements);return json({success:true});
   }
   if(path==='/admin/delete_device'&&post){await db.prepare('DELETE FROM devices WHERE id=? AND household_id=?').bind(d.id,s.household_id).run();return json({success:true});}
   throw new HTTPError(404,'Not found');
  }catch(e){return json({error:e instanceof HTTPError?e.message:'Service temporarily unavailable'},e instanceof HTTPError?e.status:500);}
 };
}
export async function cleanup(env,now=Date.now()){
 await env.DB.batch([
  env.DB.prepare('DELETE FROM sessions WHERE expires_ms<=?').bind(now),
  env.DB.prepare('DELETE FROM installation_tickets WHERE expires_ms<=?').bind(now),
  env.DB.prepare('DELETE FROM usage_samples WHERE day<?').bind(dayOf(now-2*86400000)),
  env.DB.prepare('DELETE FROM heartbeat_receipts WHERE received_ms<?').bind(now-86400000),
  env.DB.prepare('DELETE FROM operations WHERE created_ms<?').bind(now-7*86400000),
  env.DB.prepare('DELETE FROM rate_limits WHERE reset_ms<=?').bind(now),
  env.DB.prepare(`DELETE FROM daily_usage WHERE day<? OR (day<? AND device_id IN(SELECT d.id FROM devices d WHERE NOT EXISTS(SELECT 1 FROM subscriptions s WHERE s.household_id=d.household_id AND s.revoked=0 AND s.expires_ms>?)))`).bind(dayOf(now-29*86400000),dayOf(now),now)
 ]);
}
