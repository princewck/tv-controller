import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Store,dayOf} from '../server/store.mjs';
import {loadConfig} from '../server/config.mjs';
import {DEFAULT_POLICY,bannedAt,minuteCode,validatePolicy} from '../server/policy.mjs';
const NAME='Xiaomi_HyperOS_TV',APP='com.fongmi.android.tv';
function setup(t){let now=Date.parse('2026-10-27T10:00:00+08:00');const store=new Store({...loadConfig({}),databasePath:':memory:'},{clock:()=>now});const token=store.addDevice(NAME),device=store.device(token);t.after(()=>store.close());return {store,tick:ms=>now+=ms,set:ms=>now=ms,hb:playing=>store.heartbeat(device,{device:NAME,app:APP,is_playing:playing,event_id:randomUUID()})};}
function solve(f,state){const {token}=f.store.bootstrap(new URL(state.launch_url).hash.slice(8)),session=f.store.session(token);let result;for(let i=0;i<3;i++){f.store.browserState(session);const row=f.store.sessionByHash(session.token_hash);f.tick(1000);result=f.store.answer(session,{question_id:row.question_id,answer:row.expected_answer,attempt_id:randomUUID()});}return f.store.unlock(session,result.ready_nonce);}
function watch(f,seconds){let state;for(let i=0;i<seconds/10;i++){f.tick(10000);state=f.hb(true);}return state;}
test('完整30→20→5→2→2阶段与服务端连续三题验证',t=>{
 const f=setup(t);let state=watch(f,1800);assert.equal(state.status,'lock');assert.equal(state.stage,0);
 let granted=solve(f,state);assert.equal(granted.credited_seconds,1200);assert.equal(granted.remaining_seconds,1200);
 state=watch(f,1200);assert.equal(state.status,'lock');assert.equal(state.stage,1);
 granted=solve(f,state);assert.equal(granted.credited_seconds,300);assert.equal(granted.remaining_seconds,300);
 state=watch(f,300);granted=solve(f,state);assert.equal(granted.credited_seconds,120);
 state=watch(f,120);granted=solve(f,state);assert.equal(granted.credited_seconds,120);
 assert.equal(f.store.get('SELECT SUM(duration_seconds) n FROM usage_events').n,3420);
});
test('连续停止五小时才重置；暂停期间不误更新最后观看，午夜不绕过阶段',t=>{
 const f=setup(t);f.set(Date.parse('2026-10-27T23:59:50+08:00'));f.hb(true);
 f.store.run('UPDATE policy_cycles SET stage=3,stage_used_seconds=120 WHERE device_name=?',NAME);
 f.tick(20000);assert.equal(f.hb(false).stage,3);
 f.tick(5*3600_000-20001);assert.equal(f.store.state(NAME).stage,3);
 f.tick(1);assert.equal(f.store.state(NAME).stage,0);assert.equal(f.store.state(NAME).remaining_seconds,1800);
});
test('临时放行更新休息锚点；继续观看按最新时间计算；替换而不叠加',t=>{
 const f=setup(t);f.hb(true);f.tick(4*3600_000);
 f.store.tx(()=>f.store.policy.grant(NAME,1800,'admin'));
 const first=f.store.state(NAME);assert.equal(first.override_seconds,1800);
 f.tick(2*3600_000);assert.equal(f.store.state(NAME).override_seconds,1800);
 f.hb(true);const latest=f.store.policy.cycle(NAME).last_playing_ms;
 f.tick(3600_000);f.store.tx(()=>f.store.policy.grant(NAME,600,'admin'));
 assert.equal(f.store.state(NAME).remaining_seconds,600);
 assert.ok(f.store.policy.cycle(NAME).last_playing_ms>latest);
 f.tick(5*3600_000-1);assert.equal(f.store.state(NAME).override_seconds,600);
 f.tick(1);const reset=f.store.state(NAME);assert.equal(reset.override_seconds,0);assert.equal(reset.remaining_seconds,1800);assert.equal(reset.stage,0);
});
test('放行额度消耗后必须验证，不叠加初始免费额度；禁看时段被临时放行覆盖',t=>{
 const f=setup(t);const policy={...DEFAULT_POLICY,banned_windows:[{label:'全天',days:[0,1,2,3,4,5,6],start:'00:00',end:'00:00',enabled:true}]};
 f.store.run('INSERT INTO policy_settings VALUES(1,?,?)',JSON.stringify(validatePolicy(policy)),0);
 assert.equal(f.hb(false).lock_reason,'restricted_time');f.store.tx(()=>f.store.policy.grant(NAME,60,'admin'));
 assert.equal(f.store.state(NAME).status,'allow');watch(f,60);assert.equal(f.store.state(NAME).lock_reason,'restricted_time');
});
test('跨午夜禁看按开始日判断；结束边界放行；日期密码采用北京时间且补零',()=>{
 const p={...DEFAULT_POLICY,banned_windows:[{label:'周一夜间',days:[1],start:'22:00',end:'07:00',enabled:true}]};
 assert.ok(bannedAt(p,Date.parse('2026-10-26T22:00:00+08:00')));
 assert.ok(bannedAt(p,Date.parse('2026-10-27T06:59:59+08:00')));
 assert.equal(bannedAt(p,Date.parse('2026-10-27T07:00:00+08:00')),null);
 assert.equal(bannedAt(p,Date.parse('2026-10-27T23:00:00+08:00')),null);
 assert.equal(minuteCode(Date.parse('2026-10-24T23:25:59+08:00')),'202610242325');
 assert.equal(minuteCode(Date.parse('2026-10-25T00:05:00+08:00')),'202610250005');
 assert.throws(()=>validatePolicy({...DEFAULT_POLICY,repeat_seconds:0}));
});
