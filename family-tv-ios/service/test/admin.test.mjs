import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {randomBytes,scryptSync,randomUUID} from 'node:crypto';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Store} from '../server/store.mjs';
import {createApp} from '../server/app.mjs';
import {loadConfig} from '../server/config.mjs';
import {DEFAULT_POLICY,minuteCode} from '../server/policy.mjs';
async function fixture(t){
 let now=Date.parse('2026-10-27T10:15:00+08:00');const dir=mkdtempSync(join(tmpdir(),'tv-admin-')),file=join(dir,'password.json');
 const password='test-admin-only-123',salt=randomBytes(16);writeFileSync(file,JSON.stringify({algorithm:'scrypt-v1',salt:salt.toString('hex'),digest:scryptSync(password,salt,64).toString('hex')}));
 const config={...loadConfig({}),databasePath:':memory:',adminPasswordFile:file},store=new Store(config,{clock:()=>now});const token=store.addDevice('Xiaomi_HyperOS_TV');
 const app=createApp(store,config,{logger:()=>{}}),server=app.listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 t.after(async()=>{await new Promise(r=>server.close(r));store.close();rmSync(dir,{recursive:true,force:true});});
 const call=(path,body,headers={})=>fetch(base+path,{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json',Origin:config.origin,...headers}:headers,body:body?JSON.stringify(body):undefined});
 return {store,config,password,token,call,advance:ms=>now+=ms,now:()=>now};
}
async function login(f){const r=await f.call('/admin/login',{password:f.password});assert.equal(r.status,200);return {data:await r.json(),Cookie:r.headers.get('set-cookie').split(';')[0],setCookie:r.headers.get('set-cookie')};}
test('管理员120天安全Cookie、CSRF、跨角色隔离与退出失效',async t=>{
 const f=await fixture(t);assert.equal((await f.call('/admin/stats')).status,401);
 assert.equal((await f.call('/admin/login',{password:f.password},{Origin:'https://evil.invalid'})).status,403);
 assert.equal((await f.call('/admin/login',{password:'wrong'})).status,401);
 const l=await login(f);assert.match(l.setCookie,/Max-Age=10368000/);assert.match(l.setCookie,/Secure/);assert.match(l.setCookie,/HttpOnly/);assert.match(l.setCookie,/SameSite=Strict/);
 assert.equal((await f.call('/admin/config',null,{Cookie:l.Cookie})).status,200);
 assert.equal((await f.call('/admin/grant',{seconds:1800},{Cookie:l.Cookie})).status,403);
 assert.equal((await f.call('/admin/grant',{seconds:1800},{Cookie:l.Cookie,'X-CSRF-Token':l.data.csrf})).status,200);
 assert.equal((await f.call('/lock_status',null,{Cookie:l.Cookie})).status,401);
 await f.call('/admin/logout',{}, {Cookie:l.Cookie,'X-CSRF-Token':l.data.csrf});
 assert.equal((await f.call('/admin/session',null,{Cookie:l.Cookie})).status,401);
});
test('保存禁看时段、立即成人验证、时间码补零与单次放行审计',async t=>{
 const f=await fixture(t),l=await login(f),admin={Cookie:l.Cookie,'X-CSRF-Token':l.data.csrf};
 const policy={...DEFAULT_POLICY,banned_windows:[{label:'全天限制',days:[0,1,2,3,4,5,6],start:'00:00',end:'00:00',enabled:true}]};
 assert.equal((await f.call('/admin/config',{policy},admin)).status,200);
 const heartbeat=await(await f.call('/heartbeat',{device:'Xiaomi_HyperOS_TV',app:'com.fongmi.android.tv',is_playing:false,event_id:randomUUID()},{Authorization:'Bearer '+f.token})).json();
 assert.equal(heartbeat.lock_reason,'restricted_time');
 const boot=await f.call('/bootstrap',{ticket:new URL(heartbeat.launch_url).hash.slice(8)});
 const Cookie=boot.headers.get('set-cookie').split(';')[0];const state=await(await f.call('/lock_status',null,{Cookie})).json();
 assert.equal(state.question,null);const headers={Cookie,'X-CSRF-Token':state.csrf};
 assert.equal((await f.call('/unlock',{nonce:'fake'},headers)).status,403);
 assert.equal((await f.call('/adult_verify',{code:'200001010000',attempt_id:randomUUID()},headers)).status,403);
 f.advance(1600);const body={code:minuteCode(f.now()),attempt_id:randomUUID()};
 const result=await(await f.call('/adult_verify',body,headers)).json();assert.equal(result.status,'allow');assert.equal(result.granted_seconds,1800);
 const again=await(await f.call('/adult_verify',body,headers)).json();assert.equal(again.id,result.id);
 assert.equal(f.store.get('SELECT COUNT(*) n FROM time_overrides').n,1);
 assert.equal(f.store.get('SELECT status FROM math_sessions').status,'adult_verified');
 assert.equal(f.store.policy.cycle('Xiaomi_HyperOS_TV').last_playing_ms,f.now());
});
test('管理员放行刷新最新休息时间、统计仅正式设备且包含区段',async t=>{
 const f=await fixture(t),l=await login(f),headers={Cookie:l.Cookie,'X-CSRF-Token':l.data.csrf};
 const timestamp=f.now()/1000;f.store.run('INSERT INTO usage_events(timestamp,device_name,app_package,duration_seconds) VALUES(?,?,?,?)',timestamp,'Xiaomi_HyperOS_TV','com.ktcp.video',10);
 let result=await(await f.call('/admin/grant',{seconds:1800},headers)).json();assert.equal(result.remaining_seconds,1800);const until=result.rest_until_ms;
 f.advance(3600_000);result=await(await f.call('/admin/grant',{seconds:600},headers)).json();assert.equal(result.remaining_seconds,600);assert.equal(result.rest_until_ms,until+3600_000);
 const stats=await(await f.call('/admin/stats',null,{Cookie:l.Cookie})).json();assert.equal(stats.daily[0].seconds,10);assert.equal(stats.timeline[0].watched_seconds,10);
 assert.equal(stats.admin_audit.filter(x=>x.action==='temporary_grant').length,2);
});
test('口令爆破限频、管理员会话120天到期',async t=>{
 const f=await fixture(t),l=await login(f);
 for(let i=0;i<6;i++)assert.equal((await f.call('/admin/login',{password:'wrong'})).status,401);
 assert.equal((await f.call('/admin/login',{password:f.password})).status,429);
 f.advance(120*86400_000+1);assert.equal((await f.call('/admin/session',null,{Cookie:l.Cookie})).status,401);
});
test('SSE鉴权、快照、真实心跳、重复过滤及断连清理',async t=>{
 const f=await fixture(t);assert.equal((await f.call('/admin/heartbeat_stream')).status,401);
 const l=await login(f);
 // call封装保留认证头；读取流而不是等待整个响应结束。
 const response=await f.call('/admin/heartbeat_stream',null,{Cookie:l.Cookie});
 assert.match(response.headers.get('content-type'),/text\/event-stream/);
 const reader=response.body.getReader();t.after(()=>reader.cancel().catch(()=>{}));
 const initial=new TextDecoder().decode((await reader.read()).value);
 assert.match(initial,/event: snapshot/);assert.match(initial,/"received_ms":null/);
 const id=randomUUID(),body={device:'Xiaomi_HyperOS_TV',app:'com.ktcp.video',is_playing:false,event_id:id};
 await f.call('/heartbeat',body,{Authorization:'Bearer '+f.token});
 const data=new TextDecoder().decode((await reader.read()).value);assert.match(data,/event: heartbeat/);assert.ok(data.includes(id));assert.ok(data.includes(String(f.now())));
 let emitted=0;const listener=()=>emitted++;f.store.events.on('heartbeat',listener);
 await f.call('/heartbeat',body,{Authorization:'Bearer '+f.token});assert.equal(emitted,0);
 await reader.cancel();await new Promise(r=>setTimeout(r,20));f.store.events.off('heartbeat',listener);assert.equal(f.store.events.listenerCount('heartbeat'),0);
});
