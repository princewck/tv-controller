import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { Store,hash,dayOf,HttpError } from '../server/store.mjs';
import { loadConfig,ORIGIN } from '../server/config.mjs';
const NAME='Xiaomi_HyperOS_TV',APP='com.fongmi.android.tv';
function fixture(t,overrides={}){
  let now=Date.parse('2026-10-27T12:00:00+08:00');
  const config={...loadConfig({}),databasePath:':memory:',...overrides};
  const store=new Store(config,{clock:()=>now});t.after(()=>store.close());
  const token=store.addDevice(NAME),device=store.device(token);
  const hb=(extra={})=>store.heartbeat(device,{device:NAME,app:APP,is_playing:true,event_id:randomUUID(),...extra});
  return {store,device,config,token,hb,advance:ms=>now+=ms,set:ms=>now=ms};
}
function lockedSession(f){
  const state=f.hb();assert.equal(state.status,'lock');
  const ticket=new URL(state.launch_url).hash.slice('#ticket='.length);
  const {token}=f.store.bootstrap(ticket);return f.store.session(token);
}
function answerCorrect(f,session){
  const state=f.store.browserState(session),row=f.store.sessionByHash(session.token_hash);f.advance(1000);
  return f.store.answer(session,{question_id:state.question.id,answer:row.expected_answer,attempt_id:randomUUID()});
}
test('唯一域名严格校验',()=>{
  assert.equal(loadConfig({}).origin,ORIGIN);
  assert.throws(()=>loadConfig({PUBLIC_ORIGIN:'https://other.invalid'}));
});
test('10秒采样、阈值锁定、重复请求不重复计时',t=>{
 const f=fixture(t,{dailyLimit:20});const id=randomUUID();
 assert.equal(f.hb({event_id:id}).watched_seconds,10);
 const second=f.hb({event_id:id});assert.equal(second.duplicate,true);assert.equal(second.watched_seconds,10);
 assert.throws(()=>f.hb(),e=>e.status===429);
 f.advance(10000);assert.equal(f.hb().status,'lock');
});
test('暂停、未知应用、浏览器均不计时；离线不补记',t=>{
 const f=fixture(t);assert.equal(f.hb({is_playing:false}).watched_seconds,0);
 f.advance(10000);assert.equal(f.hb({app:'com.android.browser'}).watched_seconds,0);
 f.advance(3600_000);assert.equal(f.hb().watched_seconds,10);
});
test('设备鉴权和负载验证',t=>{
 const f=fixture(t);assert.throws(()=>f.store.device('x'.repeat(43)),e=>e.status===401);
 assert.throws(()=>f.hb({device:'another'}),e=>e.status===403);
 assert.throws(()=>f.hb({is_playing:'true'}),e=>e.status===400);
 assert.throws(()=>f.hb({event_id:'bad'}),e=>e.status===400);
 assert.throws(()=>f.hb({app:'x; am start'}),e=>e.status===400);
});
test('跨上海午夜按各日拆分；午夜重置不重置总流水',t=>{
 const f=fixture(t);f.set(Date.parse('2026-10-28T00:00:05+08:00'));f.hb();
 assert.equal(f.store.get('SELECT watched_seconds FROM daily_usage WHERE day=?','2026-10-27').watched_seconds,5);
 assert.equal(f.store.get('SELECT watched_seconds FROM daily_usage WHERE day=?','2026-10-28').watched_seconds,5);
 assert.equal(f.store.get('SELECT SUM(duration_seconds) AS n FROM usage_events').n,10);
});
test('短时单次票据不能重放、过期或替代长期令牌',t=>{
 const f=fixture(t,{dailyLimit:10});const state=f.hb(),ticket=new URL(state.launch_url).hash.slice(8);
 f.store.bootstrap(ticket);assert.throws(()=>f.store.bootstrap(ticket),e=>e.status===401);
 assert.throws(()=>f.store.device(ticket),e=>e.status===401);
 f.advance(10000);const expired=new URL(f.hb().launch_url).hash.slice(8);f.advance(91000);
 assert.throws(()=>f.store.bootstrap(expired),e=>e.status===401);
});
test('答案只能服务端验证；错题归零；旧题不可重放',t=>{
 const f=fixture(t,{dailyLimit:10}),session=lockedSession(f);
 assert.throws(()=>f.store.unlock(session,'fake'),e=>e.status===403);
 assert.equal(answerCorrect(f,session).streak,1);
 const state=f.store.browserState(session);const row=f.store.sessionByHash(session.token_hash);
 f.advance(1000);
 const wrong={question_id:state.question.id,answer:(row.expected_answer+1)%101,attempt_id:randomUUID()};
 assert.equal(f.store.answer(session,wrong).streak,0);
 assert.throws(()=>f.store.answer(session,{...wrong,attempt_id:randomUUID()}),e=>e.status===409);
});
test('三题奖励幂等；观看流水不被充值删除或扣减',t=>{
 const f=fixture(t,{dailyLimit:10}),session=lockedSession(f);
 answerCorrect(f,session);answerCorrect(f,session);
 const result=answerCorrect(f,session);assert.equal(result.streak,3);assert.ok(result.ready_nonce);
 const granted=f.store.unlock(session,result.ready_nonce);assert.equal(granted.status,'allow');assert.equal(granted.credit_seconds,1200);
 const again=f.store.unlock(session,result.ready_nonce);assert.equal(again.duplicate,true);assert.equal(again.credit_seconds,1200);
 assert.equal(f.store.get('SELECT SUM(duration_seconds) n FROM usage_events').n,10);
 assert.equal(f.store.get('SELECT COUNT(*) n FROM unlock_grants').n,1);
});
test('答题网络重试幂等，不能同一题累加三次',t=>{
 const f=fixture(t,{dailyLimit:10}),session=lockedSession(f);f.store.browserState(session);
 const row=f.store.sessionByHash(session.token_hash);f.advance(1000);
 const body={question_id:row.question_id,answer:row.expected_answer,attempt_id:randomUUID()};
 assert.deepEqual(f.store.answer(session,body),f.store.answer(session,body));
 assert.equal(f.store.sessionByHash(session.token_hash).streak,1);
});
test('午夜前答题资格不能在次日重复领取',t=>{
 const f=fixture(t,{dailyLimit:10}),session=lockedSession(f);
 answerCorrect(f,session);answerCorrect(f,session);const third=answerCorrect(f,session);
 f.set(Date.parse('2026-10-28T00:00:01+08:00'));
 assert.throws(()=>f.store.unlock(session,third.ready_nonce),e=>e.status===403);
 assert.equal(f.store.state(NAME).credit_seconds,0);
});
test('过期题目不可作答，撤销设备后会话与设备令牌都失效',t=>{
 const f=fixture(t,{dailyLimit:10}),session=lockedSession(f);f.store.browserState(session);
 const row=f.store.sessionByHash(session.token_hash);f.advance(120001);
 assert.throws(()=>f.store.answer(session,{question_id:row.question_id,answer:row.expected_answer,attempt_id:randomUUID()}),e=>e.status===409);
 f.store.run('UPDATE devices SET enabled=0 WHERE device_name=?',NAME);
 assert.throws(()=>f.store.device(f.token),e=>e.status===401);
});
test('答题期间心跳误报播放也不累计；记录开始、完成、耗时与错题',t=>{
 const f=fixture(t,{dailyLimit:10}),session=lockedSession(f);
 const opened=f.store.activeMath(NAME);assert.ok(opened);
 f.advance(10000);
 const hb=f.hb();assert.equal(hb.math_active,true);assert.equal(hb.usage_ignored_reason,'math_active');assert.equal(hb.watched_seconds,10);
 const state=f.store.browserState(session),r=f.store.sessionByHash(session.token_hash);f.advance(1000);
 f.store.answer(session,{question_id:state.question.id,answer:(r.expected_answer+1)%101,attempt_id:randomUUID()});
 answerCorrect(f,session);answerCorrect(f,session);const third=answerCorrect(f,session);
 f.store.unlock(session,third.ready_nonce);
 const math=f.store.get('SELECT * FROM math_sessions WHERE id=?',opened.id);
 assert.equal(math.status,'completed');assert.equal(math.completed_ms-math.opened_ms,14000);
 assert.equal(math.answer_count,4);assert.equal(math.wrong_count,1);assert.equal(math.reward_seconds,1200);
 assert.equal(f.store.get("SELECT COUNT(*) n FROM control_events WHERE event_type='math_opened'").n,1);
 assert.equal(f.store.get("SELECT COUNT(*) n FROM control_events WHERE event_type='math_completed'").n,1);
 f.store.unlock(session,third.ready_nonce);
 assert.equal(f.store.get("SELECT COUNT(*) n FROM control_events WHERE event_type='math_completed'").n,1);
 f.advance(10000);assert.equal(f.hb().watched_seconds,20);
});
test('重复进入网页不重置最初答题开始时间；连续休息五小时后关闭旧会话',t=>{
 const f=fixture(t,{dailyLimit:10}),session=lockedSession(f);
 const original=f.store.activeMath(NAME);f.advance(10000);f.store.browserState(session);
 assert.equal(f.store.activeMath(NAME).id,original.id);
 f.set(Date.parse('2026-10-28T00:00:01+08:00'));f.hb({is_playing:false});
 assert.equal(f.store.get('SELECT status FROM math_sessions WHERE id=?',original.id).status,'rest_reset');
 assert.equal(f.store.activeMath(NAME),null);
});
test('原生启动计数持久审计：去重、不冒充观看、不接受无效编号',t=>{
 const f=fixture(t);const id=randomUUID();
 f.hb({client_mode:'native',boot_count:131,adb_enabled:0,is_playing:false,event_id:id});
 f.hb({client_mode:'native',boot_count:131,adb_enabled:0,is_playing:false,event_id:id});
 f.advance(10000);f.hb({client_mode:'native',boot_count:131,is_playing:false});
 assert.equal(f.store.get("SELECT COUNT(*) n FROM control_events WHERE event_type='client_boot_seen'").n,1);
 f.advance(10000);f.hb({client_mode:'native',boot_count:132,is_playing:false});
 assert.equal(f.store.get("SELECT COUNT(*) n FROM control_events WHERE event_type='client_boot_seen'").n,2);
 for(const boot_count of [-1,1.5,10000001,'133']){f.advance(10000);f.hb({client_mode:'native',boot_count,is_playing:false});}
 assert.equal(f.store.get("SELECT COUNT(*) n FROM control_events WHERE event_type='client_boot_seen'").n,2);
 assert.equal(f.store.get('SELECT COUNT(*) n FROM usage_events').n,0);
});
