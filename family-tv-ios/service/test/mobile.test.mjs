import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {randomUUID} from 'node:crypto';
import {Store,hash} from '../server/store.mjs';
import {loadConfig} from '../server/config.mjs';
import {createApp} from '../server/app.mjs';
import {DEFAULT_POLICY,validatePolicy} from '../server/policy.mjs';
import {bumpControl} from '../server/mobile.mjs';
async function fixture(t){
 let now=Date.parse('2030-01-02T12:00:00+08:00');
 const config={...loadConfig({}),databasePath:':memory:'},store=new Store(config,{clock:()=>now});
 const token=store.addDevice('tv_a');store.addDevice('tv_b');
 const session='mobile-test-parent-session-value-123';
 store.run('INSERT INTO admin_sessions VALUES(?,?,?,?)',hash(session),'csrf-test',now,now+100000000);
 const app=createApp(store,config,{logger:()=>{}}),server=app.listen(0,'127.0.0.1');await once(server,'listening');
 t.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));store.close();});
 const call=(path,body,headers={})=>fetch('http://127.0.0.1:'+server.address().port+path,{method:body?'POST':'GET',headers:{Cookie:'__Host-tv_admin='+session,Origin:config.origin,'X-CSRF-Token':'csrf-test',...(body?{'Content-Type':'application/json'}:{}),...headers},body:body?JSON.stringify(body):undefined});
 const beat=body=>{now+=10000;return store.heartbeat(store.device(token),{device:'tv_a',app:'com.ktcp.video',is_playing:true,event_id:randomUUID(),...body});};
 return {store,call,beat,advance:ms=>now+=ms,now:()=>now};
}
test('pause is device scoped, idempotent, and grant cannot override explicit parent pause',async t=>{
 const {store,call}=await fixture(t),id=randomUUID();
 const body={paused:true,request_id:id};
 const first=await(await call('/admin/control?device=tv_a',body)).json();
 assert.equal(first.status,'lock');assert.equal(first.lock_reason,'parent_paused');assert.equal(store.state('tv_b').status,'allow');
 const duplicate=await(await call('/admin/control?device=tv_a',body)).json();assert.equal(duplicate.duplicate,true);assert.equal(first.control_revision,duplicate.control_revision);
 assert.equal((await call('/admin/control?device=tv_a',{paused:false,request_id:id})).status,409);
 store.openMath('tv_a');
 await call('/admin/grant?device=tv_a',{seconds:900});assert.equal(store.state('tv_a').status,'lock');
 store.openMath('tv_a');
 const resumed=await(await call('/admin/control?device=tv_a',{paused:false,request_id:randomUUID()})).json();assert.equal(resumed.status,'allow');assert.equal(resumed.override_seconds,900);assert.equal(store.activeMath('tv_a'),null);
});
test('daily limit locks at quota, permits explicit temporary grant and resets at Beijing midnight',async t=>{
 const f=await fixture(t),policy={...DEFAULT_POLICY,initial_seconds:86400,daily_limit_seconds:60};
 assert.equal((await f.call('/admin/config',{policy})).status,200);
 for(let i=0;i<6;i++)f.beat({});
 const locked=f.store.state('tv_a');assert.equal(locked.watched_seconds,60);assert.equal(locked.status,'lock');assert.equal(locked.lock_reason,'daily_limit');
 await f.call('/admin/grant?device=tv_a',{seconds:120});assert.equal(f.store.state('tv_a').status,'allow');
 f.advance(13*3600*1000);const next=f.store.state('tv_a');assert.equal(next.watched_seconds,0);assert.equal(next.daily_limit_seconds,60);assert.equal(next.status,'allow');
 assert.throws(()=>validatePolicy({...policy,daily_limit_seconds:0}),/Invalid daily limit/);
});
test('acknowledgments reject future revisions and report observation/failure separately from execution',async t=>{
 const f=await fixture(t);const revision=f.store.state('tv_a').control_revision;
 f.beat({applied_revision:revision,enforcement_result:'observing'});
 assert.equal(f.store.state('tv_a').enforcement_result,'observing');
 assert.throws(()=>f.beat({applied_revision:revision+1,enforcement_result:'stopped'}),/Invalid applied revision/);
 assert.equal(f.store.state('tv_a').enforcement_result,'observing');
 bumpControl(f.store,'tv_a');
 f.beat({applied_revision:revision,enforcement_result:'stopped'});
 const stale=f.store.state('tv_a');assert.ok(stale.applied_revision<stale.control_revision);
 f.beat({applied_revision:stale.control_revision,enforcement_result:'failed'});
 assert.equal(f.store.state('tv_a').enforcement_result,'failed');
});
test('control endpoints enforce authentication, CSRF, origin and device ownership',async t=>{
 const f=await fixture(t),body={paused:true,request_id:randomUUID()};
 assert.equal((await f.call('/admin/control?device=tv_a',body,{Cookie:''})).status,401);
 assert.equal((await f.call('/admin/control?device=tv_a',body,{'X-CSRF-Token':'wrong'})).status,403);
 assert.equal((await f.call('/admin/control?device=tv_a',body,{Origin:'https://evil.example'})).status,403);
 assert.equal((await f.call('/admin/control?device=missing',body)).status,404);
 f.store.run("INSERT INTO tenants VALUES('other','other',1,?)",f.now());
 f.store.run("INSERT INTO users VALUES('u','other_user','other',?,1,?)",JSON.stringify({}),f.now());
 f.store.run('INSERT INTO admin_sessions VALUES(?,?,?,?)',hash('other-session-test-value'),'other-csrf',f.now(),f.now()+10000);
 f.store.run("INSERT INTO admin_session_owners VALUES(?,'u','other')",hash('other-session-test-value'));
 assert.equal((await f.call('/admin/control?device=tv_a',body,{Cookie:'__Host-tv_admin=other-session-test-value','X-CSRF-Token':'other-csrf'})).status,404);
});
