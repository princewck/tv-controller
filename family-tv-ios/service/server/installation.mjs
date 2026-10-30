import {randomBytes,randomUUID} from 'node:crypto';
import {HttpError,hash,secret} from './store.mjs';
import {scoped} from './tenancy.mjs';

export function recordInstallationHealth(store,device,body){
 const now=store.clock();
 const boot=Number.isInteger(body.boot_count)&&body.boot_count>=0?body.boot_count:null;
 const adb=[0,1].includes(body.adb_enabled)?body.adb_enabled:null;
 const permissions=typeof body.permissions_ok==='boolean'?Number(body.permissions_ok):null;
 const control=store.get('SELECT * FROM mobile_control WHERE device_name=?',device);
 const current=control&&body.applied_revision===control.revision;
 const stopped=current&&body.enforcement_result==='stopped'&&body.playback_stop_verified===true?now:null;
 const resumed=current&&body.enforcement_result==='allowed'&&body.is_playing===true?now:null;
 store.run(`INSERT INTO installation_health(device_name,initial_boot,latest_boot,adb_enabled,permissions_ok,stopped_ms,resumed_ms,received_ms,adb_closed_boot) VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(device_name) DO UPDATE SET
 initial_boot=COALESCE(installation_health.initial_boot,excluded.initial_boot),latest_boot=excluded.latest_boot,
 adb_enabled=excluded.adb_enabled,permissions_ok=excluded.permissions_ok,
 stopped_ms=COALESCE(excluded.stopped_ms,installation_health.stopped_ms),
 resumed_ms=COALESCE(excluded.resumed_ms,installation_health.resumed_ms),received_ms=excluded.received_ms,
 adb_closed_boot=CASE WHEN excluded.adb_enabled=1 THEN NULL WHEN excluded.adb_enabled=0 THEN COALESCE(installation_health.adb_closed_boot,excluded.latest_boot) ELSE installation_health.adb_closed_boot END`,device,boot,boot,adb,permissions,stopped,resumed,now,adb===0?boot:null);
}
export function installationStatus(store,device){
 const health=store.get('SELECT * FROM installation_health WHERE device_name=?',device);
 const now=store.clock(),row=store.get('SELECT last_heartbeat_ms,enabled FROM devices WHERE device_name=?',device);
 const online=!!row?.enabled&&row.last_heartbeat_ms!==null&&now-row.last_heartbeat_ms<45000;
 const fresh=!!health&&now-health.received_ms<45000;
 const checks={connected:online,playback_test:!!health?.stopped_ms&&health.resumed_ms>health.stopped_ms,
  adb_closed:fresh&&health.adb_enabled===0,
  rebooted:fresh&&health.initial_boot!==null&&health.latest_boot>health.initial_boot&&health.adb_closed_boot!==null&&health.latest_boot>health.adb_closed_boot,
  permissions:fresh&&health.permissions_ok===1};
 return {device,checks,complete:Object.values(checks).every(Boolean),server_now_ms:now,updated_ms:health?.received_ms??null};
}
export function installInstallation(app,store,{origin,requireAdmin,adminCsrf,audit}){
 app.post('/admin/installation_ticket',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req),label=req.body.label;
  if(typeof label!=='string'||!label.trim()||label.length>64)throw new HttpError(400,'Device name required');
  if(scope.devices.length>=10)throw new HttpError(409,'Device limit reached');
  const code=randomBytes(8).toString('hex').toUpperCase(),device='tv_'+randomUUID().replaceAll('-',''),expires=store.clock()+15*60_000;
  store.tx(()=>{
   store.addDevice(device,secret(),scope.tenant,label.trim());
   store.run('INSERT INTO installation_tickets VALUES(?,?,?,NULL)',hash(code),device,expires);
   audit(req,'installation_started',{device},scope.tenant);
  });
  res.status(201).json({code,device,label:label.trim(),origin:store.config.origin,expires_ms:expires});
 });
 // A one-use installation code lets the parent's chosen local agent obtain
 // device credentials without revealing the household account password.
 app.post('/installation/redeem',(req,res)=>{
  const code=typeof req.body.code==='string'?req.body.code.replaceAll('-','').replaceAll(' ','').toUpperCase():'';
  if(!/^[0-9A-F]{16}$/.test(code))throw new HttpError(400,'Invalid installation code');
  const result=store.tx(()=>{
   const ticket=store.get('SELECT * FROM installation_tickets WHERE code_hash=?',hash(code));
   if(!ticket||ticket.redeemed_ms!==null||ticket.expires_ms<=store.clock())throw new HttpError(410,'Installation code expired or used');
   const device=store.get('SELECT enabled FROM devices WHERE device_name=?',ticket.device_name);
   if(!device?.enabled||!store.tenantEnabled(ticket.device_name))throw new HttpError(410,'Device unavailable');
   const token=secret();store.run('UPDATE devices SET token_hash=? WHERE device_name=?',hash(token),ticket.device_name);
   store.run('UPDATE installation_tickets SET redeemed_ms=? WHERE code_hash=?',store.clock(),hash(code));
   return {device:ticket.device_name,token,origin:store.config.origin};
  });res.json(result);
 });
 app.get('/admin/installation_status',requireAdmin,(req,res)=>{const scope=scoped(store,req,{device:true});res.json(installationStatus(store,scope.device));});
}
