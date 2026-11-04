import {recordInstallationHealth} from './installation.mjs';
import {mobileState,acknowledgeControl} from './mobile.mjs';
import {EventEmitter} from 'node:events';
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname } from 'node:path';
import {PolicyEngine} from './policy.mjs';
import {pickQuestion,learningForDevice} from './learning.mjs';
import {activeDisplay,displayState} from './display.mjs';
import { randomBytes, randomInt, randomUUID, createHash } from 'node:crypto';

export const hash=value=>createHash('sha256').update(value).digest('hex');
export const secret=()=>randomBytes(32).toString('base64url');
export const dayOf=ms=>new Date(ms+8*3600_000).toISOString().slice(0,10);
export class HttpError extends Error { constructor(status,message){super(message);this.status=status;} }
export class Store {
  constructor(config,{clock=Date.now}={}) {
    this.config=config;this.clock=clock;this.events=new EventEmitter();this.events.setMaxListeners(100);
    if(config.databasePath!==':memory:')mkdirSync(dirname(config.databasePath),{recursive:true,mode:0o700});
    this.db=new DatabaseSync(config.databasePath);
    const schema=readFileSync(new URL('../sql/schema.sql',import.meta.url),'utf8');
    this.db.exec(schema);
    if(!this.db.prepare('PRAGMA table_info(installation_health)').all().some(c=>c.name==='adb_closed_boot'))this.db.exec('ALTER TABLE installation_health ADD COLUMN adb_closed_boot INTEGER');
    const mathSchema=this.get("SELECT sql FROM sqlite_master WHERE type='table' AND name='math_sessions'").sql;
    if(!mathSchema.includes('admin_released')){
      this.tx(()=>{
        this.db.exec('DROP INDEX IF EXISTS one_open_math_session; ALTER TABLE math_sessions RENAME TO math_sessions_legacy;');
        this.db.exec(schema.match(/CREATE TABLE IF NOT EXISTS math_sessions \([\s\S]*?\) STRICT;/)[0]);
        this.db.exec('INSERT INTO math_sessions SELECT * FROM math_sessions_legacy; DROP TABLE math_sessions_legacy; CREATE UNIQUE INDEX one_open_math_session ON math_sessions(device_name) WHERE status=\'open\';');
      });
    }
    this.tx(()=>{
      this.run("INSERT OR IGNORE INTO tenants(tenant_id,label,created_ms) VALUES('default','Default household',?)",this.clock());
      this.run("INSERT OR IGNORE INTO device_ownership SELECT device_name,'default',device_name FROM devices");
    });
    this.policy=new PolicyEngine(this);
    this.db.exec('PRAGMA synchronous=FULL;');
  }
  get(sql,...args){return this.db.prepare(sql).get(...args);}
  run(sql,...args){return this.db.prepare(sql).run(...args);}
  // 单进程同步事务；多个同时到来的请求也不能重复领取或消耗同一题目。
  tx(fn){if(this.inTx)return fn();this.db.exec('BEGIN IMMEDIATE');this.inTx=true;try{const value=fn();this.db.exec('COMMIT');return value;}catch(e){this.db.exec('ROLLBACK');throw e;}finally{this.inTx=false;}}
  tenantForDevice(name){return this.get('SELECT tenant_id FROM device_ownership WHERE device_name=?',name)?.tenant_id||'default';}
  tenantEnabled(name){return !!this.get('SELECT 1 FROM tenants WHERE tenant_id=? AND enabled=1',this.tenantForDevice(name));}
  addDevice(name,token=secret(),tenant='default',label=name){
    if(!/^[A-Za-z0-9_-]{1,64}$/.test(name))throw new Error('设备名格式错误');
    if(!this.get('SELECT 1 FROM tenants WHERE tenant_id=? AND enabled=1',tenant))throw new HttpError(404,'Tenant not found');
    this.tx(()=>{
      this.run('INSERT INTO devices(device_name,token_hash,created_at) VALUES(?,?,?)',name,hash(token),this.clock());
      this.run('INSERT INTO device_ownership VALUES(?,?,?)',name,tenant,label);
    });return token;
  }
  device(token){
    if(typeof token!=='string'||token.length<32||token.length>128)throw new HttpError(401,'Device authentication required');
    const device=this.get('SELECT * FROM devices WHERE token_hash=? AND enabled=1',hash(token));
    if(!device||!this.tenantEnabled(device.device_name))throw new HttpError(401,'Invalid device token');return device;
  }
  state(name,now=this.clock()){
    if(!this.inTx)return this.tx(()=>this.state(name,now));
    const day=dayOf(now), row=this.get('SELECT * FROM daily_usage WHERE device_name=? AND day=?',name,day);
    const watched=row?.watched_seconds||0, credit=row?.credit_seconds||0;
    return mobileState(this,name,{day,watched_seconds:watched,credit_seconds:credit,effective_seconds:Math.max(0,watched-credit),...this.policy.state(name)});
  }
  audit(name,type,mathId=null,details={}){
    this.run('INSERT INTO control_events(timestamp,device_name,event_type,math_session_id,details_json) VALUES(?,?,?,?,?)',this.clock(),name,type,mathId,JSON.stringify(details));
  }
  activeMath(name,now=this.clock()){
    return this.get("SELECT * FROM math_sessions WHERE device_name=? AND status='open'",name)||null;
  }
  openMath(name){
    const existing=this.activeMath(name);
    if(existing)return existing;
    const id=randomUUID(),now=this.clock();
    this.run("INSERT INTO math_sessions(id,device_name,day,opened_ms,last_seen_ms,status) VALUES(?,?,?,?,?,'open')",id,name,dayOf(now),now,now);
    this.audit(name,'math_opened',id);
    return this.activeMath(name);
  }
  heartbeat(device,body){const received_ms=this.clock();const result=this.tx(()=>{
    const now=this.clock();
    if(body.device!==device.device_name)throw new HttpError(403,'Device mismatch');
    if(!/^[a-zA-Z0-9_.-]{1,180}$/.test(body.app||'')||typeof body.is_playing!=='boolean'
      ||! /^[0-9a-f-]{36}$/i.test(body.event_id||''))throw new HttpError(400,'Invalid heartbeat');
    this.policy.maybeReset(device.device_name);
    const math=this.activeMath(device.device_name,now),display=activeDisplay(this,device.device_name);
    const previousState=this.state(device.device_name,now);
    const duplicate=this.get('SELECT 1 FROM heartbeat_receipts WHERE device_name=? AND event_id=?',device.device_name,body.event_id);
    if(!duplicate){
      acknowledgeControl(this,device.device_name,body);
      recordInstallationHealth(this,device.device_name,body);
      const last=this.get('SELECT last_heartbeat_ms FROM devices WHERE device_name=?',device.device_name).last_heartbeat_ms;
      // 不接受加速上报刷时长；离线间隙不推断为观看，也不积压补传。
      if(last!==null&&now-last<8000)throw new HttpError(429,'Heartbeat too frequent');
      this.run('INSERT INTO heartbeat_receipts VALUES(?,?,?)',device.device_name,body.event_id,now);
      this.run('UPDATE devices SET last_heartbeat_ms=? WHERE device_name=?',now,device.device_name);
      this.run('INSERT INTO client_capabilities VALUES(?,?,?) ON CONFLICT(device_name) DO UPDATE SET display_supported=excluded.display_supported,received_ms=excluded.received_ms',device.device_name,body.display_supported===true?1:0,now);
      // 持久保留首次看到某启动计数的时间，区别于真正开机时间；不把心跳当观看流水。
      if(body.client_mode==='native'&&Number.isInteger(body.boot_count)&&body.boot_count>=0&&body.boot_count<=10000000){
        const previous=this.get("SELECT details_json FROM control_events WHERE device_name=? AND event_type='client_boot_seen' ORDER BY timestamp DESC,id DESC LIMIT 1",device.device_name);
        if(!previous||JSON.parse(previous.details_json).boot_count!==body.boot_count){
          this.audit(device.device_name,'client_boot_seen',null,{boot_count:body.boot_count,adb_enabled:[0,1].includes(body.adb_enabled)?body.adb_enabled:null,app:body.app});
        }
      }
      const seconds=last===null?10:Math.min(10,Math.max(0,Math.floor((now-last)/1000)));
      if(body.is_playing&&this.config.monitoredApps.has(body.app))this.policy.notePlaying(device.device_name);
      if(!math&&!display&&body.is_playing&&this.config.monitoredApps.has(body.app)&&seconds>0){
        this.policy.consume(device.device_name,seconds);
        // 将跨上海午夜的采样拆分，充值永远不会污染这份真实使用流水。
        let cursor=Math.floor(now/1000)-seconds, remaining=seconds;
        while(remaining>0){
          const day=dayOf(cursor*1000);
          const end=Date.parse(day+'T00:00:00+08:00')/1000+86400;
          const duration=Math.min(remaining,end-cursor);
          this.run('INSERT INTO usage_events(timestamp,device_name,app_package,duration_seconds) VALUES(?,?,?,?)',cursor,device.device_name,body.app,duration);
          this.run('INSERT INTO daily_usage(device_name,day,watched_seconds) VALUES(?,?,?) ON CONFLICT(device_name,day) DO UPDATE SET watched_seconds=watched_seconds+excluded.watched_seconds',device.device_name,day,duration);
          cursor+=duration;remaining-=duration;
        }
      }
    }
    const state=this.state(device.device_name,now);
    if(body.display_supported===true&&!this.get("SELECT 1 FROM control_events WHERE device_name=? AND event_type='client_display_capability'",device.device_name))this.audit(device.device_name,'client_display_capability');
    if(display&&body.display_visible===display.id&&display.visible_ms===null){this.run('UPDATE display_jobs SET visible_ms=? WHERE id=?',now,display.id);this.audit(device.device_name,'display_client_visible',null,{job_id:display.id});}
    if(state.status==='lock'){
      if(previousState.status!=='lock')this.audit(device.device_name,'lock_requested');
      state.message=state.lock_reason==='restricted_time'?'Adult verification required':'Take a break';
      // 短时单次启动票据，设备长期Bearer永远不进入URL或浏览器。
      const ticket=secret();
      this.run('INSERT INTO launch_tickets VALUES(?,?,?)',hash(ticket),device.device_name,now+90_000);
      state.launch_url=this.config.origin+'/#ticket='+ticket;
    }
    if(display&&body.display_supported===true){const ticket=secret();this.run('INSERT INTO launch_tickets VALUES(?,?,?)',hash(ticket),device.device_name,now+90000);state.display_command={id:display.id,expires_ms:display.expires_ms,launch_url:this.config.origin+'/#ticket='+ticket};}
    return {...state,duplicate:!!duplicate,math_active:!!math,usage_ignored_reason:display?'display_active':math?'math_active':null};
  });
    // 仅在事务提交后通知后台；重传、限流和失败请求不冒充新心跳。
    if(!result.duplicate)this.events.emit('heartbeat',{device:device.device_name,event_id:body.event_id,received_ms,is_playing:body.is_playing,app:body.app,client_mode:body.client_mode==='native'?'native':'shell',adb_enabled:body.client_mode==='native'&&[0,1].includes(body.adb_enabled)?body.adb_enabled:null,boot_count:Number.isInteger(body.boot_count)&&body.boot_count>=0?body.boot_count:null});
    return result;
  }
  bootstrap(ticket){return this.tx(()=>{
    if(typeof ticket!=='string'||ticket.length>128)throw new HttpError(401,'Invalid ticket');
    const row=this.get('SELECT t.* FROM launch_tickets t JOIN devices d USING(device_name) WHERE t.token_hash=? AND d.enabled=1',hash(ticket));
    if(!row||row.expires_ms<=this.clock()||!this.tenantEnabled(row.device_name))throw new HttpError(401,'Ticket expired');
    this.run('DELETE FROM launch_tickets WHERE token_hash=?',hash(ticket));
    if(!activeDisplay(this,row.device_name)&&this.state(row.device_name).status==='lock')this.openMath(row.device_name);
    // 一个设备只有一个活动答题会话，避免并行浏览器反复领取奖励。
    this.run('DELETE FROM browser_sessions WHERE device_name=?',row.device_name);
    const token=secret(),csrf=secret(),now=this.clock();
    this.run('INSERT INTO browser_sessions(token_hash,device_name,csrf,expires_ms,exam_day) VALUES(?,?,?,?,?)',hash(token),row.device_name,csrf,now+30*60_000,dayOf(now));
    return {token};
  });}
  session(token){
    const row=typeof token==='string'&&token.length<=128?this.get('SELECT s.* FROM browser_sessions s JOIN devices d USING(device_name) WHERE s.token_hash=? AND d.enabled=1',hash(token)):null;
    if(!row||row.expires_ms<=this.clock()||!this.tenantEnabled(row.device_name))throw new HttpError(401,'Browser session expired');return row;
  }
  refresh(session){
    if(session.exam_day!==dayOf(this.clock())){
      this.run('UPDATE browser_sessions SET exam_day=?,streak=0,question_id=NULL,ready_nonce=NULL WHERE token_hash=?',dayOf(this.clock()),session.token_hash);
      session=this.sessionByHash(session.token_hash);
    }
    return session;
  }
  sessionByHash(id){return this.get('SELECT * FROM browser_sessions WHERE token_hash=?',id);}
  question(session){
    if(session.ready_nonce)return null;
    if(!session.question_id||session.question_expires_ms<=this.clock()){
      const generated=pickQuestion(learningForDevice(this,session.device_name)),id=randomUUID();
      const {answer,...payload}=generated;
      this.run('UPDATE browser_sessions SET question_id=?,question_text=?,expected_answer=?,question_expires_ms=? WHERE token_hash=?',id,payload.text,answer,this.clock()+120_000,session.token_hash);
      this.run('INSERT INTO question_payloads VALUES(?,?,?)',id,JSON.stringify(payload),this.clock()+120_000);
      session=this.sessionByHash(session.token_hash);
    }
    const payload=this.get('SELECT payload_json FROM question_payloads WHERE question_id=?',session.question_id);
    return {id:session.question_id,...(payload?JSON.parse(payload.payload_json):{text:session.question_text}),expires_ms:session.question_expires_ms};
  }
  browserState(session){return this.tx(()=>{
    session=this.refresh(this.sessionByHash(session.token_hash));
    const state=this.state(session.device_name);
    const presentation=activeDisplay(this,session.device_name);
    if(presentation)return {...state,display:displayState(this,presentation),csrf:session.csrf,math_active:false};
    const math=state.status==='lock'?this.openMath(session.device_name):this.activeMath(session.device_name);
    if(math)this.run('UPDATE math_sessions SET last_seen_ms=? WHERE id=?',this.clock(),math.id);
    return {...state,math_active:!!math,csrf:session.csrf,streak:session.streak,ready_nonce:session.ready_nonce,
      question:state.status==='lock'&&state.lock_reason!=='restricted_time'?this.question(session):null};
  });}
  answer(session,body){return this.tx(()=>{
    const now=this.clock();session=this.refresh(this.sessionByHash(session.token_hash));
    if(!/^[0-9a-f-]{36}$/i.test(body.attempt_id||'')||!Number.isInteger(body.answer)||body.answer<0||body.answer>100)throw new HttpError(400,'Invalid answer');
    const receipt=this.get('SELECT response_json FROM answer_receipts WHERE session_hash=? AND attempt_id=?',session.token_hash,body.attempt_id);
    if(receipt)return JSON.parse(receipt.response_json);
    const currentState=this.state(session.device_name);
    if(['parent_paused','daily_limit'].includes(currentState.lock_reason))throw new HttpError(409,'Parent must authorize more viewing');
    if(currentState.status!=='lock')throw new HttpError(409,'Device is not locked');
    if(currentState.lock_reason==='restricted_time')throw new HttpError(403,'Adult verification required');
    if(session.ready_nonce)throw new HttpError(409,'Already qualified');
    if(!session.question_id||session.question_id!==body.question_id||session.question_expires_ms<=now)throw new HttpError(409,'Question expired');
    if(now-session.last_answer_ms<800)throw new HttpError(429,'Answer too frequent');
    const correct=body.answer===session.expected_answer;
    const math=this.openMath(session.device_name);
    this.run('UPDATE math_sessions SET answer_count=answer_count+1,wrong_count=wrong_count+?,last_seen_ms=? WHERE id=?',correct?0:1,now,math.id);
    const streak=correct?session.streak+1:0;
    const nonce=streak===3?secret():null;
    this.run('UPDATE browser_sessions SET streak=?,ready_nonce=?,question_id=NULL,last_answer_ms=? WHERE token_hash=?',streak,nonce,now,session.token_hash);
    const result={correct,streak,ready_nonce:nonce,question:nonce?null:this.question(this.sessionByHash(session.token_hash))};
    this.run('INSERT INTO answer_receipts VALUES(?,?,?,?)',session.token_hash,body.attempt_id,JSON.stringify(result),now);
    return result;
  });}
  unlock(session,nonce){return this.tx(()=>{
    if(typeof nonce!=='string'||nonce.length>128)throw new HttpError(400,'Invalid reward nonce');
    const existing=this.get('SELECT * FROM unlock_grants WHERE nonce=?',nonce);
    if(existing){if(existing.device_name!==session.device_name)throw new HttpError(403,'Device mismatch');return {success:true,duplicate:true,...this.state(session.device_name)};}
    session=this.refresh(this.sessionByHash(session.token_hash));
    if(!nonce||session.ready_nonce!==nonce||session.streak!==3)throw new HttpError(403,'Three verified answers required');
    const state=this.state(session.device_name);
    if(['parent_paused','daily_limit'].includes(state.lock_reason))throw new HttpError(409,'Parent must authorize more viewing');
    if(state.status!=='lock')throw new HttpError(409,'Device is not locked');
    if(state.lock_reason==='restricted_time')throw new HttpError(403,'Adult verification required');
    const reward=this.policy.advance(session.device_name);
    const now=this.clock();
    this.run('INSERT INTO unlock_grants VALUES(?,?,?,?,?)',nonce,session.device_name,state.day,reward,now);
    const math=this.activeMath(session.device_name,now);
    if(math){
      this.run("UPDATE math_sessions SET status='completed',completed_ms=?,last_seen_ms=?,reward_seconds=? WHERE id=?",now,now,reward,math.id);
      this.audit(session.device_name,'math_completed',math.id,{duration_ms:now-math.opened_ms,answer_count:math.answer_count,wrong_count:math.wrong_count});
    }
    this.audit(session.device_name,'reward_granted',math?.id||null,{seconds:reward});
    this.run('UPDATE daily_usage SET credit_seconds=credit_seconds+? WHERE device_name=? AND day=?',reward,session.device_name,state.day);
    this.run('UPDATE browser_sessions SET streak=0,ready_nonce=NULL,question_id=NULL WHERE token_hash=?',session.token_hash);
    return {success:true,credited_seconds:reward,...this.state(session.device_name)};
  });}
  cleanup(){const now=this.clock();this.tx(()=>{
    this.run('DELETE FROM display_jobs WHERE created_ms<?',now-7*86400000);
    this.run('DELETE FROM display_agent_tokens WHERE expires_ms<=? AND id NOT IN(SELECT agent_id FROM display_jobs WHERE agent_id IS NOT NULL)',now);
    this.run("UPDATE display_jobs SET review_status='error' WHERE review_status='pending' AND created_ms<?",now-60000);
    this.run('DELETE FROM question_payloads WHERE expires_ms<=?',now);
    this.run('DELETE FROM launch_tickets WHERE expires_ms<=?',now);
    this.run('DELETE FROM browser_sessions WHERE expires_ms<=?',now);
    this.run('DELETE FROM heartbeat_receipts WHERE received_ms<?',now-86400_000);
    this.run('DELETE FROM answer_receipts WHERE created_ms<?',now-86400_000);
    this.run('DELETE FROM admin_sessions WHERE expires_ms<=?',now);
  });}
  close(){this.events.emit('shutdown');this.db.close();}
}
