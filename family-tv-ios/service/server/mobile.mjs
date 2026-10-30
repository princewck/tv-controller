import {HttpError} from './store.mjs';
import {scoped} from './tenancy.mjs';

export function mobileControl(store,name){
 store.run('INSERT OR IGNORE INTO mobile_control(device_name) VALUES(?)',name);
 return store.get('SELECT * FROM mobile_control WHERE device_name=?',name);
}
export function bumpControl(store,name){mobileControl(store,name);store.run('UPDATE mobile_control SET revision=revision+1 WHERE device_name=?',name);}
export function mobileState(store,name,state){
 const control=mobileControl(store,name),policy=store.policy.config(name),daily=policy.daily_limit_seconds;
 let reason=state.lock_reason,remaining=state.remaining_seconds;
 if(daily!==undefined&&state.override_seconds===0){
  const available=Math.max(0,daily-state.watched_seconds);
  remaining=Math.min(remaining,available);
  if(available===0)reason='daily_limit';
 }
 if(control.paused){reason='parent_paused';remaining=0;}
 return {...state,status:reason?'lock':'allow',lock_reason:reason,remaining_seconds:remaining,
  daily_limit_seconds:daily??null,paused:!!control.paused,control_revision:control.revision,
  applied_revision:control.applied_revision,enforcement_result:control.enforcement_result,applied_ms:control.applied_ms};
}
export function acknowledgeControl(store,name,body){
 const row=mobileControl(store,name),revision=body.applied_revision;
 if(revision===undefined)return;
 if(!Number.isSafeInteger(revision)||revision<0||revision>row.revision)throw new HttpError(400,'Invalid applied revision');
 if(!['stopped','allowed','observing','failed'].includes(body.enforcement_result))throw new HttpError(400,'Invalid enforcement result');
 // An acknowledgment belongs to one issued revision; a stale response cannot
 // certify a newer rule, and failed/observation-only attempts are never success.
 if(revision>=row.applied_revision)store.run('UPDATE mobile_control SET applied_revision=?,enforcement_result=?,applied_ms=? WHERE device_name=?',revision,body.enforcement_result,store.clock(),name);
}
export function installMobile(app,store,{origin,requireAdmin,adminCsrf,audit}){
 app.get('/admin/mobile_capabilities',requireAdmin,(req,res)=>res.json({version:1,pause:true,daily_limit:true,execution_receipts:true,household_delete:false}));
 app.get('/admin/control',requireAdmin,(req,res)=>{const scope=scoped(store,req,{device:true});res.json(store.state(scope.device));});
 app.post('/admin/control',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req,{device:true}),{paused,request_id}=req.body;
  if(typeof paused!=='boolean'||typeof request_id!=='string'||!/^[0-9a-f-]{36}$/i.test(request_id))throw new HttpError(400,'Invalid control request');
  const result=store.tx(()=>{
   // Idempotency is scoped to the household and checked before mutating state.
   const previous=store.get("SELECT details_json FROM tenant_audit WHERE tenant_id=? AND actor=? AND action='mobile_control' AND json_extract(details_json,'$.request_id')=?",scope.tenant,req.identity.username,request_id);
   if(previous){const value=JSON.parse(previous.details_json);if(value.device!==scope.device||value.paused!==paused)throw new HttpError(409,'Request ID reused');return {...store.state(scope.device),duplicate:true};}
   mobileControl(store,scope.device);
   store.run('UPDATE mobile_control SET paused=?,revision=revision+1 WHERE device_name=?',paused?1:0,scope.device);
   if(!paused)store.policy.closeMath(scope.device,'admin_released');
   // Invalidate challenge sessions so stale unlocks never undo a new pause.
   store.run('DELETE FROM browser_sessions WHERE device_name=?',scope.device);
   audit(req,'mobile_control',{device:scope.device,paused,request_id},scope.tenant);
   return store.state(scope.device);
  });res.json(result);
 });
}
