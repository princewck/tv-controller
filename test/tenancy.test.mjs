import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {randomUUID,scryptSync,randomBytes} from 'node:crypto';
import {mkdtempSync,writeFileSync,rmSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {Store,hash} from '../server/store.mjs';
import {loadConfig} from '../server/config.mjs';
import {createApp} from '../server/app.mjs';
import {DEFAULT_POLICY} from '../server/policy.mjs';
async function fixture(t){
 let now=Date.parse('2030-01-02T12:00:00+08:00');const dir=mkdtempSync(join(tmpdir(),'tv-tenancy-')),file=join(dir,'password.json'),password='isolated-root-test-123',salt=randomBytes(16);
 writeFileSync(file,JSON.stringify({algorithm:'scrypt-v1',salt:salt.toString('hex'),digest:scryptSync(password,salt,64).toString('hex')}));
 const config={...loadConfig({}),databasePath:':memory:',adminPasswordFile:file},store=new Store(config,{clock:()=>now});store.addDevice('Xiaomi_HyperOS_TV');
 const server=createApp(store,config,{logger:()=>{}}).listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 t.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));store.close();rmSync(dir,{recursive:true,force:true});});
 const call=(path,body,auth={})=>fetch(base+path,{method:body?'POST':'GET',headers:{...auth,...(body?{'Content-Type':'application/json',Origin:config.origin}:{})},body:body?JSON.stringify(body):undefined});
 const login=async(username,password)=>{const response=await call('/admin/login',{username,password});assert.equal(response.status,200);const value=await response.json();return {identity:value.identity,Cookie:response.headers.get('set-cookie').split(';')[0],'X-CSRF-Token':value.csrf};};
 const root=await login('admin',password);
 const makeUser=async username=>{const response=await call('/admin/users',{username,password:'isolated-user-test-123',label:username+' family',role:'superadmin'},root);assert.equal(response.status,201);const {user}=await response.json();return {user,auth:await login(username,'isolated-user-test-123')};};
 const makeDevice=async auth=>{const response=await call('/admin/devices',{label:'Living room'},auth);assert.equal(response.status,201);return response.json();};
 return {store,config,call,login,root,makeUser,makeDevice,advance:ms=>now+=ms,now:()=>now};
}
test('普通用户独立家庭：相同电视名不冲突，角色不能自提权，不泄露令牌',async t=>{
 const f=await fixture(t),a=await f.makeUser('family_a'),b=await f.makeUser('family_b');
 assert.equal(a.auth.identity.role,'user');assert.notEqual(a.user.tenant_id,b.user.tenant_id);
 const da=await f.makeDevice(a.auth),db=await f.makeDevice(b.auth);assert.notEqual(da.device,db.device);assert.notEqual(da.token,db.token);
 const devices=await(await f.call('/admin/devices',null,a.auth)).json();assert.equal(devices.devices.length,1);assert.equal(devices.devices[0].device_name,da.device);assert.ok(!JSON.stringify(devices).includes(da.token));
 assert.equal(f.store.get('SELECT token_hash FROM devices WHERE device_name=?',da.device).token_hash,hash(da.token));
 assert.ok(!JSON.stringify(f.store.db.prepare('SELECT * FROM tenant_audit').all()).includes(da.token));
 assert.equal((await f.call('/admin/users',null,a.auth)).status,403);
 assert.equal((await f.call('/admin/users',{username:'evil_user',password:'test-evil-user-123',label:'bad'},a.auth)).status,403);
 assert.equal((await f.call('/admin/user_update',{user_id:b.user.user_id,enabled:false},a.auth)).status,403);
 assert.equal((await f.call('/admin/devices?tenant='+b.user.tenant_id,{label:'intruder'},a.auth)).status,403);
 assert.equal((await f.call('/admin/users',{username:'family_a',password:'other-pass-123',label:'duplicate'},f.root)).status,409);
});
test('跨租户配置/统计/放行/设备更新/SSE均拒绝，自己家庭规则独立生效',async t=>{
 const f=await fixture(t),a=await f.makeUser('family_a'),b=await f.makeUser('family_b'),da=await f.makeDevice(a.auth),db=await f.makeDevice(b.auth);
 for(const path of ['/admin/config','/admin/stats','/admin/devices','/admin/heartbeat_stream']){
  assert.equal((await f.call(path+'?tenant='+b.user.tenant_id,null,a.auth)).status,403,path);
  assert.equal((await f.call(path+'?device='+db.device,null,a.auth)).status,404,path);
 }
 assert.equal((await f.call('/admin/grant?device='+db.device,{seconds:600},a.auth)).status,404);
 assert.equal((await f.call('/admin/device_update?device='+db.device,{rotate_token:true},a.auth)).status,404);
 const policy={...DEFAULT_POLICY,initial_seconds:60,default_grant_seconds:120};assert.equal((await f.call('/admin/config',{policy},a.auth)).status,200);
 assert.equal(f.store.policy.config(da.device).initial_seconds,60);assert.equal(f.store.policy.config(db.device).initial_seconds,1800);assert.equal(f.store.policy.config('Xiaomi_HyperOS_TV').initial_seconds,1800);
 const beat=async(device,token,name=device)=>f.call('/heartbeat',{device:name,app:'com.ktcp.video',is_playing:true,event_id:randomUUID()},{Authorization:'Bearer '+token});
 assert.equal((await beat(da.device,da.token,db.device)).status,403);
 for(let i=0;i<6;i++){f.advance(10000);assert.equal((await beat(da.device,da.token)).status,200);}
 assert.equal(f.store.state(da.device).status,'lock');assert.equal(f.store.state(db.device).status,'allow');
 const sa=await(await f.call('/admin/stats',null,a.auth)).json(),sb=await(await f.call('/admin/stats',null,b.auth)).json();assert.equal(sa.daily[0].seconds,60);assert.equal(sb.daily.length,0);
 assert.equal((await f.call('/admin/grant',{},a.auth)).status,200);assert.equal(f.store.state(da.device).remaining_seconds,120);assert.equal(f.store.state(db.device).override_seconds,0);
 const rootScope=await(await f.call('/admin/stats?tenant='+a.user.tenant_id+'&device='+da.device,null,f.root)).json();assert.equal(rootScope.device,da.device);
});
test('停用账户及重置密码立即撤销会话；停用家庭后设备/答题票据失效',async t=>{
 const f=await fixture(t),a=await f.makeUser('family_a'),da=await f.makeDevice(a.auth);
 const policy={...DEFAULT_POLICY,banned_windows:[{label:'all day',days:[0,1,2,3,4,5,6],start:'00:00',end:'00:00',enabled:true}]};await f.call('/admin/config',{policy},a.auth);
 const body={device:da.device,app:'com.ktcp.video',is_playing:false,event_id:randomUUID()},headers={Authorization:'Bearer '+da.token};
 const heartbeat=await(await f.call('/heartbeat',body,headers)).json(),ticket=new URL(heartbeat.launch_url).hash.slice(8);
 assert.equal((await f.call('/admin/user_update',{user_id:a.user.user_id,enabled:false},f.root)).status,200);
 assert.equal((await f.call('/admin/session',null,a.auth)).status,401);assert.equal((await f.call('/heartbeat',body,headers)).status,401);assert.equal((await f.call('/bootstrap',{ticket})).status,401);
 assert.equal((await f.call('/admin/login',{username:'family_a',password:'isolated-user-test-123'})).status,401);
 await f.call('/admin/user_update',{user_id:a.user.user_id,enabled:true},f.root);const again=await f.login('family_a','isolated-user-test-123');
 await f.call('/admin/user_update',{user_id:a.user.user_id,password:'new-isolated-password-123'},f.root);assert.equal((await f.call('/admin/session',null,again)).status,401);
 assert.equal((await f.call('/admin/login',{username:'family_a',password:'isolated-user-test-123'})).status,401);assert.equal((await f.login('family_a','new-isolated-password-123')).identity.role,'user');
});
test('SSE只推送所选家庭设备，不推送别的租户，停用后关闭',async t=>{
 const f=await fixture(t),a=await f.makeUser('family_a'),b=await f.makeUser('family_b'),da=await f.makeDevice(a.auth),db=await f.makeDevice(b.auth);
 const response=await f.call('/admin/heartbeat_stream',null,a.auth),reader=response.body.getReader();t.after(()=>reader.cancel().catch(()=>{}));
 assert.ok(new TextDecoder().decode((await reader.read()).value).includes(da.device));
 f.store.events.emit('heartbeat',{device:db.device,event_id:'forbidden',received_ms:f.now()});f.store.events.emit('heartbeat',{device:da.device,event_id:'allowed',received_ms:f.now()});
 const text=new TextDecoder().decode((await reader.read()).value);assert.ok(text.includes('allowed'));assert.ok(!text.includes('forbidden'));assert.ok(!text.includes(db.device));
 await f.call('/admin/user_update',{user_id:a.user.user_id,enabled:false},f.root);f.store.events.emit('heartbeat',{device:da.device,event_id:'after-disable',received_ms:f.now()});
 const ended=await reader.read();assert.equal(ended.done,true);assert.equal(f.store.events.listenerCount('heartbeat'),0);
});
test('设备轮换撤销旧令牌、普通用户不能更新别人的设备，空家庭统计可读取',async t=>{
 const f=await fixture(t),a=await f.makeUser('family_a');const empty=await(await f.call('/admin/stats',null,a.auth)).json();assert.equal(empty.device,null);assert.equal(empty.daily.length,0);
 assert.equal((await f.call('/admin/grant',{seconds:600},a.auth)).status,404);
 const da=await f.makeDevice(a.auth);const rotated=await(await f.call('/admin/device_update?device='+da.device,{rotate_token:true},a.auth)).json();assert.ok(rotated.token);assert.notEqual(rotated.token,da.token);
 assert.throws(()=>f.store.device(da.token),/Invalid device token/);assert.equal(f.store.device(rotated.token).device_name,da.device);
 await f.call('/admin/device_update?device='+da.device,{enabled:false},a.auth);assert.throws(()=>f.store.device(rotated.token),/Invalid device token/);
});
test('v3数据库迁移保留设备令牌/观看/管理员Cookie/自定义规则，重启迁移幂等',()=>{
 const dir=mkdtempSync(join(tmpdir(),'tv-v3-migration-')),file=join(dir,'old.sqlite');
 try{
  const old=new DatabaseSync(file),schema=readFileSync(new URL('../sql/schema.sql',import.meta.url),'utf8').split('-- v4：')[0];old.exec(schema);
  old.prepare('INSERT INTO devices VALUES(?,?,1,NULL,?)').run('Xiaomi_HyperOS_TV',hash('test-existing-device-token-value-123'),1);
  old.prepare('INSERT INTO usage_events(timestamp,device_name,app_package,duration_seconds) VALUES(?,?,?,?)').run(1,'Xiaomi_HyperOS_TV','com.ktcp.video',10);
  old.prepare('INSERT INTO policy_settings VALUES(1,?,?)').run(JSON.stringify({...DEFAULT_POLICY,initial_seconds:600}),1);
  old.prepare('INSERT INTO admin_sessions VALUES(?,?,?,?)').run(hash('test-old-admin-cookie-value-123'),'csrf',1,9999999999999);old.close();
  for(let i=0;i<2;i++){
   const store=new Store({...loadConfig({}),databasePath:file});assert.equal(store.tenantForDevice('Xiaomi_HyperOS_TV'),'default');assert.equal(store.device('test-existing-device-token-value-123').device_name,'Xiaomi_HyperOS_TV');
   assert.equal(store.get('SELECT count(*) n FROM usage_events').n,1);assert.equal(store.policy.config('Xiaomi_HyperOS_TV').initial_seconds,600);assert.equal(store.get('PRAGMA user_version').user_version,6);assert.equal(store.get('SELECT count(*) n FROM admin_sessions').n,1);store.close();
  }
 }finally{rmSync(dir,{recursive:true,force:true});}
});
