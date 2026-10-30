import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Store} from '../server/store.mjs';
import {loadConfig} from '../server/config.mjs';
import {recordInstallationHealth,installationStatus} from '../server/installation.mjs';

test('installation never passes merely because the device is online or reported stopped without playback evidence',()=>{
 let now=100000;const store=new Store({...loadConfig({}),databasePath:':memory:'},{clock:()=>now});
 try{
  store.addDevice('setup');store.state('setup');
  store.run('UPDATE devices SET last_heartbeat_ms=? WHERE device_name=?',now,'setup');
  recordInstallationHealth(store,'setup',{boot_count:5,adb_enabled:1,permissions_ok:true,applied_revision:1,enforcement_result:'stopped'});
  assert.equal(installationStatus(store,'setup').checks.connected,true);
  assert.equal(installationStatus(store,'setup').checks.playback_test,false);
  assert.equal(installationStatus(store,'setup').complete,false);
  now+=10000;recordInstallationHealth(store,'setup',{boot_count:5,adb_enabled:1,permissions_ok:true,applied_revision:1,enforcement_result:'stopped',playback_stop_verified:true});
  now+=10000;recordInstallationHealth(store,'setup',{boot_count:5,adb_enabled:0,permissions_ok:true,applied_revision:1,enforcement_result:'allowed',is_playing:true});
  assert.equal(installationStatus(store,'setup').checks.playback_test,true);
  assert.equal(installationStatus(store,'setup').checks.rebooted,false);
  now+=10000;store.run('UPDATE devices SET last_heartbeat_ms=? WHERE device_name=?',now,'setup');
  recordInstallationHealth(store,'setup',{boot_count:6,adb_enabled:0,permissions_ok:true});
  assert.equal(installationStatus(store,'setup').complete,true);
  now+=45001;assert.equal(installationStatus(store,'setup').complete,false);
 }finally{store.close();}
});

test('restart before ADB closure is not accepted as restart after closure',()=>{
 let now=100000;const store=new Store({...loadConfig({}),databasePath:':memory:'},{clock:()=>now});
 try{
  store.addDevice('order');store.state('order');
  recordInstallationHealth(store,'order',{boot_count:5,adb_enabled:1,permissions_ok:true});
  now+=10000;recordInstallationHealth(store,'order',{boot_count:6,adb_enabled:1,permissions_ok:true});
  now+=10000;recordInstallationHealth(store,'order',{boot_count:6,adb_enabled:0,permissions_ok:true});
  assert.equal(installationStatus(store,'order').checks.rebooted,false);
  now+=10000;recordInstallationHealth(store,'order',{boot_count:7,adb_enabled:0,permissions_ok:true});
  assert.equal(installationStatus(store,'order').checks.rebooted,true);
 }finally{store.close();}
});

test('installation code is authenticated to create, single-use to redeem and expires',async t=>{
 const {once}=await import('node:events');const {hash}=await import('../server/store.mjs');const {createApp}=await import('../server/app.mjs');
 let now=100000;const config={...loadConfig({}),databasePath:':memory:'},store=new Store(config,{clock:()=>now});
 store.run('INSERT INTO admin_sessions VALUES(?,?,?,?)',hash('installation-test-session-value'),'csrf',now,now+10000000);
 const server=createApp(store,config,{logger:()=>{}}).listen(0,'127.0.0.1');await once(server,'listening');
 t.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));store.close();});
 const call=(path,body,auth=true)=>fetch('http://127.0.0.1:'+server.address().port+path,{method:'POST',headers:{'Content-Type':'application/json',Origin:config.origin,...(auth?{Cookie:'__Host-tv_admin=installation-test-session-value','X-CSRF-Token':'csrf'}:{})},body:JSON.stringify(body)});
 assert.equal((await call('/admin/installation_ticket',{label:'TV'},false)).status,401);
 const ticket=await(await call('/admin/installation_ticket',{label:'TV'})).json();assert.match(ticket.code,/^[0-9A-F]{16}$/);
 const redeemed=await(await call('/installation/redeem',{code:ticket.code},false)).json();
 assert.equal(store.device(redeemed.token).device_name,ticket.device);
 assert.equal((await call('/installation/redeem',{code:ticket.code},false)).status,410);
 const next=await(await call('/admin/installation_ticket',{label:'TV2'})).json();now+=15*60000;
 assert.equal((await call('/installation/redeem',{code:next.code},false)).status,410);
 assert.equal(store.get('SELECT code_hash FROM installation_tickets WHERE device_name=?',next.device).code_hash,hash(next.code));
});
