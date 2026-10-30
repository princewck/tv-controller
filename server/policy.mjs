import {randomUUID} from 'node:crypto';
import {HttpError} from './store.mjs';
export const DEFAULT_POLICY={initial_seconds:1800,first_reward_seconds:1200,second_reward_seconds:300,
 repeat_seconds:120,rest_reset_seconds:18000,default_grant_seconds:1800,banned_windows:[]};
const local=ms=>new Date(ms+8*3600_000);
export function validatePolicy(value){
 if(!value||typeof value!=='object'||Array.isArray(value))throw new HttpError(400,'Invalid policy');
 const out={};
 for(const key of ['initial_seconds','first_reward_seconds','second_reward_seconds','repeat_seconds','rest_reset_seconds','default_grant_seconds']){
  if(!Number.isInteger(value[key])||value[key]<60||value[key]>86400)throw new HttpError(400,'Invalid '+key);out[key]=value[key];
 }
 if(!Array.isArray(value.banned_windows)||value.banned_windows.length>32)throw new HttpError(400,'Invalid banned windows');
 out.banned_windows=value.banned_windows.map(w=>{
  if(!w||typeof w.label!=='string'||w.label.length>64||!Array.isArray(w.days)||!w.days.length||w.days.some(d=>!Number.isInteger(d)||d<0||d>6)||typeof w.enabled!=='boolean')throw new HttpError(400,'Invalid window');
  const validTime=t=>typeof t==='string'&&/^([01]\d|2[0-3]):[0-5]\d$/.test(t);
  if(!validTime(w.start)||!validTime(w.end))throw new HttpError(400,'Invalid window time');
  return {id:typeof w.id==='string'&&/^[0-9a-f-]{36}$/i.test(w.id)?w.id:randomUUID(),label:w.label,days:[...new Set(w.days)].sort(),start:w.start,end:w.end,enabled:w.enabled};
 });return out;
}
export function bannedAt(policy,now){
 const date=local(now),day=date.getUTCDay(),minute=date.getUTCHours()*60+date.getUTCMinutes();
 const n=time=>Number(time.slice(0,2))*60+Number(time.slice(3));
 return policy.banned_windows.find(w=>{
  if(!w.enabled)return false;const start=n(w.start),end=n(w.end);
  if(start===end)return w.days.includes(day);
  if(start<end)return w.days.includes(day)&&minute>=start&&minute<end;
  return (w.days.includes(day)&&minute>=start)||(w.days.includes((day+6)%7)&&minute<end);
 })||null;
}
export const minuteCode=now=>local(now).toISOString().slice(0,16).replace(/[-T:]/g,'');
export class PolicyEngine {
 constructor(store){this.s=store;}
 configForTenant(tenant='default'){
  const row=tenant==='default'?this.s.get('SELECT config_json FROM policy_settings WHERE id=1'):this.s.get('SELECT config_json FROM tenant_policies WHERE tenant_id=?',tenant);
  return row?JSON.parse(row.config_json):{...DEFAULT_POLICY,initial_seconds:this.s.config.dailyLimit,first_reward_seconds:this.s.config.reward};
 }
 config(name){return this.configForTenant(name?this.s.tenantForDevice(name):'default');}
 cycle(name){
  this.s.run('INSERT INTO policy_cycles(device_name,started_ms) VALUES(?,?) ON CONFLICT(device_name) DO NOTHING',name,this.s.clock());
  return this.s.get('SELECT * FROM policy_cycles WHERE device_name=?',name);
 }
 maybeReset(name){
  let cycle=this.cycle(name);const now=this.s.clock(),policy=this.config(name);
  if(cycle.last_playing_ms!==null&&now-cycle.last_playing_ms>=policy.rest_reset_seconds*1000){
   this.s.run('UPDATE policy_cycles SET stage=0,stage_used_seconds=0,last_playing_ms=NULL,started_ms=? WHERE device_name=?',now,name);
   this.s.run('UPDATE time_overrides SET remaining_seconds=0 WHERE device_name=?',name);
   this.closeMath(name,'rest_reset');
   this.s.run('UPDATE browser_sessions SET streak=0,ready_nonce=NULL,question_id=NULL WHERE device_name=?',name);
   this.s.audit(name,'rest_reset',null,{rest_seconds:policy.rest_reset_seconds});cycle=this.cycle(name);
  }return cycle;
 }
 budget(stage,policy=this.config()){return stage===0?policy.initial_seconds:stage===1?policy.first_reward_seconds:stage===2?policy.second_reward_seconds:policy.repeat_seconds;}
 override(name){return this.s.get('SELECT * FROM time_overrides WHERE device_name=? AND remaining_seconds>0 AND expires_ms>? ORDER BY created_ms DESC LIMIT 1',name,this.s.clock())||null;}
 state(name){
  const policy=this.config(name),cycle=this.maybeReset(name),override=this.override(name),ban=bannedAt(policy,this.s.clock());
  const budget=this.budget(cycle.stage,policy);
  const reason=override?null:ban?'restricted_time':cycle.stage_used_seconds>=budget?'anti_addiction':null;
  return {status:reason?'lock':'allow',lock_reason:reason,stage:cycle.stage,stage_used_seconds:cycle.stage_used_seconds,
   stage_budget_seconds:budget,remaining_seconds:override?override.remaining_seconds:Math.max(0,budget-cycle.stage_used_seconds),
   next_reward_seconds:this.budget(cycle.stage+1,policy),adult_grant_seconds:policy.default_grant_seconds,rest_reset_seconds:policy.rest_reset_seconds,
   rest_until_ms:cycle.last_playing_ms===null?null:cycle.last_playing_ms+policy.rest_reset_seconds*1000,
   override_seconds:override?.remaining_seconds||0,banned_label:ban?.label||null,server_now_ms:this.s.clock()};
 }
 notePlaying(name){this.maybeReset(name);this.s.run('UPDATE policy_cycles SET last_playing_ms=? WHERE device_name=?',this.s.clock(),name);}
 consume(name,seconds){
  const override=this.override(name);let remaining=seconds;
  if(override){const used=Math.min(remaining,override.remaining_seconds);this.s.run('UPDATE time_overrides SET remaining_seconds=remaining_seconds-? WHERE id=?',used,override.id);remaining-=used;}
  if(remaining)this.s.run('UPDATE policy_cycles SET stage_used_seconds=stage_used_seconds+? WHERE device_name=?',remaining,name);
 }
 advance(name){
  const cycle=this.cycle(name),reward=this.budget(cycle.stage+1,this.config(name));
  this.s.run('UPDATE policy_cycles SET stage=stage+1,stage_used_seconds=0 WHERE device_name=?',name);
  return reward;
 }
 closeMath(name,status){const row=this.s.get("SELECT * FROM math_sessions WHERE device_name=? AND status='open'",name);
  if(row){this.s.run('UPDATE math_sessions SET status=?,completed_ms=? WHERE id=?',status,this.s.clock(),row.id);this.s.audit(name,status,row.id);}
 }
 grant(name,seconds,source){
  if(!Number.isInteger(seconds)||seconds<60||seconds>86400)throw new HttpError(400,'Grant must be 60..86400 seconds');
  if(!this.s.get('SELECT 1 FROM devices WHERE device_name=? AND enabled=1',name))throw new HttpError(404,'Device not found');
  const now=this.s.clock(),id=randomUUID();
  const cycle=this.maybeReset(name);
  // 临时放行替换当前剩余额度；结束后需再次验证，不叠加一个隐藏的初始30分钟。
  // 放行本身刷新休息锚点；后续实际播放继续刷新，必须从最新活动起连续休息5小时。
  this.s.run('UPDATE policy_cycles SET stage_used_seconds=?,last_playing_ms=? WHERE device_name=?',this.budget(cycle.stage,this.config(name)),now,name);
  // 新放行替换未用完的旧放行，避免手机重复操作导致额度叠加。最长24小时有效。
  this.s.run('UPDATE time_overrides SET remaining_seconds=0 WHERE device_name=?',name);
  this.s.run('INSERT INTO time_overrides VALUES(?,?,?,?,?,?,?)',id,name,now,now+86400_000,seconds,seconds,source);
  this.s.run("UPDATE math_sessions SET reward_seconds=? WHERE device_name=? AND status='open'",seconds,name);
  this.closeMath(name,source==='admin'?'admin_released':'adult_verified');
  this.s.run('UPDATE browser_sessions SET streak=0,ready_nonce=NULL,question_id=NULL WHERE device_name=?',name);
  this.s.audit(name,source+'_grant',null,{seconds,expires_ms:now+86400_000});
  return {success:true,granted_seconds:seconds,id};
 }
}
