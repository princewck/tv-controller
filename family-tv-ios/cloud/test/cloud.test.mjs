import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createHandler,cleanup} from '../src/handler.mjs';
import {HTTPError} from '../src/security.mjs';
import {D1} from './d1.mjs';
function fixture(t){
 let now=Date.parse('2030-01-02T12:00:00+08:00');const db=new D1(),claims=new Map();
 const env={DB:db,PUBLIC_ORIGIN:'https://familytv.invalid',BUNDLE_ID:'wang.chengkai.familytv',PRODUCT_ID:'wang.chengkai.familytv.plus.monthly'};
 const handle=createHandler({clock:()=>now,verifyTransaction:async jws=>{if(!claims.has(jws))throw new HTTPError(403,'Apple signature verification failed');return claims.get(jws);},verifyAppTransaction:async jws=>{if(!claims.has(jws))throw new HTTPError(403,'Apple app signature verification failed');return claims.get(jws);},verifyNotification:async jws=>{if(!claims.has(jws))throw new HTTPError(403,'Invalid notification');return claims.get(jws);}});
 t.after(()=>db.close());
 const call=async(path,body,auth,extra={})=>handle(new Request(env.PUBLIC_ORIGIN+path,{method:body?'POST':'GET',headers:{Origin:env.PUBLIC_ORIGIN,...(body?{'Content-Type':'application/json'}:{}),...(auth?{Cookie:auth.cookie,'X-CSRF-Token':auth.csrf}:{}),...extra},body:body?JSON.stringify(body):undefined}),env);
 const register=async name=>{const r=await call('/admin/register',{username:name,password:'test-private-password-123'});assert.equal(r.status,201,await r.clone().text());const value=await r.json();return {...value,cookie:r.headers.get('set-cookie').split(';')[0]};};
 const install=async auth=>{const r=await call('/admin/installation_ticket',{label:'TV'},auth);assert.equal(r.status,201);const ticket=await r.json();const provision=await(await call('/installation/redeem',{code:ticket.code})).json();return {...provision,code:ticket.code};};
 const beat=async(device,body={})=>{now+=10000;return call('/heartbeat',{device:device.device,event_id:randomUUID(),app:'com.ktcp.video',is_playing:true,...body},null,{Authorization:'Bearer '+device.token});};
 const premium=async auth=>{const jws=randomUUID();claims.set(jws,{bundleId:env.BUNDLE_ID,productId:env.PRODUCT_ID,type:'Auto-Renewable Subscription',appAccountToken:auth.identity.tenant_id,originalTransactionId:randomUUID(),transactionId:randomUUID(),environment:'Sandbox',signedDate:now,expiresDate:now+86400000});const response=await call('/admin/subscription',{signed_transaction:jws},auth);assert.equal(response.status,200,await response.clone().text());return {jws,transaction:claims.get(jws)};};
 return {db,env,call,register,install,beat,premium,claims,advance:ms=>now+=ms,now:()=>now};
}
test('cloud registration/login, one-use installation and tenant boundaries',async t=>{
 const f=fixture(t),a=await f.register('family_a'),b=await f.register('family_b'),device=await f.install(a);
 assert.equal((await f.call('/admin/session',null,a)).status,200);
 assert.equal((await f.call('/admin/control?device='+device.device,null,b)).status,404);
 assert.equal((await f.call('/installation/redeem',{code:device.code})).status,410);
 assert.equal((await f.call('/heartbeat',{device:device.device,event_id:randomUUID(),app:'app',is_playing:false},null,{Authorization:'Bearer wrong-token'})).status,401);
 const response=await f.beat(device);assert.equal(response.status,200,await response.clone().text());
 const devices=await(await f.call('/admin/devices',null,a)).json();assert.equal(devices.devices[0].device_name,device.device);assert.ok(!JSON.stringify(devices).includes(device.token));
});
test('daily playback, idempotent parent pause/grant, and duplicate heartbeat',async t=>{
 const f=fixture(t),a=await f.register('family_a'),d=await f.install(a);
 const config=await(await f.call('/admin/config',null,a)).json();config.policy.daily_limit_seconds=60;
 assert.equal((await f.call('/admin/config',{policy:config.policy},a)).status,200);
 for(let i=0;i<6;i++)assert.equal((await f.beat(d)).status,200);
 let state=await(await f.call('/admin/control?device='+d.device,null,a)).json();assert.equal(state.lock_reason,'daily_limit');assert.equal(state.watched_seconds,60);
 const grant={seconds:300,request_id:randomUUID()};await f.call('/admin/grant?device='+d.device,grant,a);
 const id=randomUUID();await f.call('/admin/control?device='+d.device,{paused:true,request_id:id},a);
 state=await(await f.call('/admin/control?device='+d.device,{paused:true,request_id:id},a)).json();assert.equal(state.duplicate,true);assert.equal(state.lock_reason,'parent_paused');
 assert.equal((await f.call('/admin/control?device='+d.device,{paused:false,request_id:id},a)).status,409);
 state=await(await f.call('/admin/control?device='+d.device,{paused:false,request_id:randomUUID()},a)).json();assert.equal(state.status,'allow');
 const event=randomUUID();const first=await(await f.beat(d,{event_id:event})).json();const again=await(await f.beat(d,{event_id:event})).json();assert.equal(again.watched_seconds,first.watched_seconds);assert.equal(again.duplicate,true);
});
test('history is enforced by the server and expired/revoked subscriptions cannot unlock it',async t=>{
 const f=fixture(t),a=await f.register('family_a'),d=await f.install(a),yesterday='2030-01-01';
 f.db.db.prepare('INSERT INTO daily_usage VALUES(?,?,?,?)').run(d.device,yesterday,'com.ktcp.video',900);
 let stats=await(await f.call('/admin/stats?device='+d.device,null,a)).json();assert.equal(stats.daily.length,0);assert.equal(stats.premium,false);
 const purchase=await f.premium(a);stats=await(await f.call('/admin/stats?device='+d.device,null,a)).json();assert.equal(stats.daily[0].seconds,900);assert.equal(stats.premium,true);
 purchase.transaction.revocationDate=f.now();purchase.transaction.signedDate+=1;
 await f.call('/admin/subscription',{signed_transaction:purchase.jws},a);
 stats=await(await f.call('/admin/stats?device='+d.device,null,a)).json();assert.equal(stats.daily.length,0);
 const b=await f.register('family_b');assert.equal((await f.call('/admin/subscription',{signed_transaction:purchase.jws},b)).status,409);
 assert.equal((await f.call('/admin/subscription',{signed_transaction:'forged'},a)).status,403);
});
test('health requires actual playback evidence and ADB closure before reboot',async t=>{
 const f=fixture(t),a=await f.register('family_a'),d=await f.install(a);
 await f.beat(d,{boot_count:5,adb_enabled:1,permissions_ok:true,applied_revision:1,enforcement_result:'stopped',playback_stop_verified:true});
 await f.beat(d,{boot_count:6,adb_enabled:0,permissions_ok:true,applied_revision:1,enforcement_result:'allowed'});
 let health=await(await f.call('/admin/installation_status?device='+d.device,null,a)).json();assert.equal(health.checks.rebooted,false);assert.equal(health.complete,false);
 await f.beat(d,{boot_count:7,adb_enabled:0,permissions_ok:true,applied_revision:1,enforcement_result:'allowed'});
 health=await(await f.call('/admin/installation_status?device='+d.device,null,a)).json();assert.equal(health.complete,true);
});
test('household deletion revokes sessions/devices and removes cloud history while preserving another household',async t=>{
 const f=fixture(t),a=await f.register('family_a'),b=await f.register('family_b'),d=await f.install(a);
 await f.beat(d);await f.premium(a);
 assert.equal((await f.call('/admin/delete_household',{confirmation:'DELETE',password:'wrong'},a)).status,403);
 assert.equal((await f.call('/admin/delete_household',{confirmation:'DELETE',password:'test-private-password-123'},a)).status,200);
 assert.equal((await f.call('/admin/session',null,a)).status,401);assert.equal((await f.beat(d)).status,401);
 assert.equal((await f.call('/admin/session',null,b)).status,200);
 assert.equal(f.db.db.prepare('SELECT COUNT(*) n FROM subscriptions').get().n,0);assert.equal(f.db.db.prepare('SELECT COUNT(*) n FROM daily_usage').get().n,0);
});
test('free historical storage is purged and account recovery rotates its credential',async t=>{
 const f=fixture(t),a=await f.register('family_a'),d=await f.install(a);
 f.db.db.prepare('INSERT INTO daily_usage VALUES(?,?,?,?)').run(d.device,'2030-01-01','app',100);
 await cleanup(f.env,f.now());assert.equal(f.db.db.prepare('SELECT COUNT(*) n FROM daily_usage').get().n,0);
 const result=await f.call('/admin/recover',{username:'family_a',recovery_code:a.recovery_code,password:'new-private-password-123'});assert.equal(result.status,200);
 assert.equal((await f.call('/admin/session',null,a)).status,401);
 assert.equal((await f.call('/admin/login',{username:'family_a',password:'test-private-password-123'})).status,401);
 assert.equal((await f.call('/admin/login',{username:'family_a',password:'new-private-password-123'})).status,200);
});
test('offline usage is replayed once, charged to its own day, and consumes the matching bonus',async t=>{
 const f=fixture(t),a=await f.register('family_a'),d=await f.install(a);
 await f.call('/admin/grant?device='+d.device,{seconds:60,request_id:randomUUID()},a);
 const sample={id:randomUUID(),app:'com.ktcp.video',seconds:10,day:'2030-01-02',at_ms:f.now()+1000};
 let state=await(await f.beat(d,{usage_samples:[sample]})).json();assert.equal(state.watched_seconds,10);assert.equal(state.override_seconds,50);assert.deepEqual(state.accepted_usage_ids,[sample.id]);
 state=await(await f.beat(d,{usage_samples:[sample]})).json();assert.equal(state.watched_seconds,10);assert.equal(state.override_seconds,50);
 const previous={...sample,id:randomUUID(),day:'2030-01-01',at_ms:f.now()-86400000};
 state=await(await f.beat(d,{usage_samples:[previous]})).json();assert.equal(state.watched_seconds,10);assert.equal(state.override_seconds,50);
 assert.equal(f.db.db.prepare('SELECT seconds FROM daily_usage WHERE device_id=? AND day=?').get(d.device,'2030-01-01').seconds,10);
 assert.equal((await f.beat(d,{usage_samples:[{...sample,id:randomUUID(),seconds:999}]})).status,400);
});
test('expired unredeemed install tickets can rotate on the same device, but redeemed ones cannot',async t=>{
 const f=fixture(t),a=await f.register('family_a');
 let response=await f.call('/admin/installation_ticket',{label:'Living room'},a);const old=await response.json();f.advance(16*60000);
 response=await f.call('/admin/installation_ticket',{label:'Living room',device:old.device},a);assert.equal(response.status,201);const fresh=await response.json();assert.equal(fresh.device,old.device);assert.notEqual(fresh.code,old.code);
 assert.equal((await f.call('/installation/redeem',{code:old.code})).status,410);
 assert.equal((await f.call('/installation/redeem',{code:fresh.code})).status,200);
 assert.equal((await f.call('/admin/installation_ticket',{label:'Living room',device:old.device},a)).status,409);
 const devices=await(await f.call('/admin/devices',null,a)).json();assert.equal(devices.devices.length,1);
});

test('deleted-household restore requires matching verified Apple account and refuses a live original household',async t=>{
 const f=fixture(t),a=await f.register('family_a'),b=await f.register('family_b'),purchase=await f.premium(a);
 purchase.transaction.appTransactionId='apple-account-a';
 f.claims.set('proof',{bundleId:f.env.BUNDLE_ID,receiptType:'Sandbox',receiptCreationDate:f.now(),appTransactionId:'apple-account-a'});
 const restore=(proof='proof')=>f.call('/admin/subscription',{signed_transaction:purchase.jws,signed_app_transaction:proof},b);
 assert.equal((await restore()).status,409);
 await f.call('/admin/delete_household',{confirmation:'DELETE',password:'test-private-password-123'},a);
 assert.equal((await f.call('/admin/subscription',{signed_transaction:purchase.jws},b)).status,403);
 assert.equal((await restore('forged')).status,403);
 f.claims.set('wrong-proof',{...f.claims.get('proof'),appTransactionId:'another-apple-account'});assert.equal((await restore('wrong-proof')).status,403);
 f.claims.set('old-proof',{...f.claims.get('proof'),receiptCreationDate:f.now()-3600001});assert.equal((await restore('old-proof')).status,403);
 const response=await restore();assert.equal(response.status,200,await response.clone().text());const result=await response.json();assert.equal(result.active,true);assert.deepEqual(result.original_ids,[purchase.transaction.originalTransactionId]);
 assert.equal((await f.call('/admin/subscription',{signed_transaction:purchase.jws},b)).status,200);
 const c=await f.register('family_c');assert.equal((await f.call('/admin/subscription',{signed_transaction:purchase.jws,signed_app_transaction:'proof'},c)).status,409);
 // A renewed transaction still carries the permanently deleted family token.
 f.advance(1000);purchase.transaction.transactionId='renewal';purchase.transaction.expiresDate=f.now()+2*86400000;purchase.transaction.signedDate=f.now();
 f.claims.set('notification',{data:{signedTransactionInfo:purchase.jws}});
 assert.equal((await f.call('/apple/notifications',{signedPayload:'notification'})).status,200);
 let state=await(await f.call('/admin/subscription',null,b)).json();assert.equal(state.expires_ms,purchase.transaction.expiresDate);
 purchase.transaction.revocationDate=f.now();purchase.transaction.signedDate+=1;
 assert.equal((await f.call('/apple/notifications',{signedPayload:'notification'})).status,200);
 state=await(await f.call('/admin/subscription',null,b)).json();assert.equal(state.active,false);
});
test('restore validates proof identity/environment/expiry and concurrent households cannot both claim it',async t=>{
 const f=fixture(t),a=await f.register('family_a'),b=await f.register('family_b'),c=await f.register('family_c'),purchase=await f.premium(a);
 purchase.transaction.appTransactionId='apple-account-a';
 await f.call('/admin/delete_household',{confirmation:'DELETE',password:'test-private-password-123'},a);
 const proof={bundleId:f.env.BUNDLE_ID,receiptType:'Sandbox',receiptCreationDate:f.now(),appTransactionId:'apple-account-a'};
 for(const change of [{bundleId:'wrong.app'},{receiptType:'Production'},{appTransactionId:''},{receiptCreationDate:f.now()+300001}]){
  f.claims.set('bad-proof',{...proof,...change});assert.equal((await f.call('/admin/subscription',{signed_transaction:purchase.jws,signed_app_transaction:'bad-proof'},b)).status,403);
 }
 f.claims.set('proof',proof);
 for(const change of [{revocationDate:f.now()},{expiresDate:f.now()-1},{isUpgraded:true},{appTransactionId:undefined},{appAccountToken:undefined}]){
  f.claims.set('bad-transaction',{...purchase.transaction,...change});assert.equal((await f.call('/admin/subscription',{signed_transaction:'bad-transaction',signed_app_transaction:'proof'},b)).status,403);
 }
 const responses=await Promise.all([b,c].map(account=>f.call('/admin/subscription',{signed_transaction:purchase.jws,signed_app_transaction:'proof'},account)));
 assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);
 const states=await Promise.all([b,c].map(async account=>(await f.call('/admin/subscription',null,account)).json()));assert.equal(states.filter(value=>value.active).length,1);
});
