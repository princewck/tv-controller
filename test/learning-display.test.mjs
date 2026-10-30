import test from 'node:test';
import assert from 'node:assert/strict';
import {once} from 'node:events';
import {randomUUID,randomBytes,scryptSync} from 'node:crypto';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Store} from '../server/store.mjs';
import {createApp} from '../server/app.mjs';
import {loadConfig} from '../server/config.mjs';
import {pickQuestion,validateLearning} from '../server/learning.mjs';
import {validatePresentation,reviewPresentation} from '../server/display.mjs';
const document={title:'自然小课堂',pages:[{heading:'认识太阳',body:'观察自然，保护眼睛。',bullets:['白天有阳光','不要直视太阳']},{heading:'课后休息',body:'看看远方，活动一下。'}]};
async function setup(t,{reviewer=async value=>({decision:'allow',digest:value.digest,context_digest:value.context_digest,policy_version:'test_v1'})}={}){
 let now=Date.parse('2030-01-02T12:00:00+08:00');const dir=mkdtempSync(join(tmpdir(),'tv-display-')),file=join(dir,'admin.json'),password='isolated-feature-admin-123',salt=randomBytes(16);
 writeFileSync(file,JSON.stringify({algorithm:'scrypt-v1',salt:salt.toString('hex'),digest:scryptSync(password,salt,64).toString('hex')}));
 const config={...loadConfig({}),databasePath:':memory:',adminPasswordFile:file},store=new Store(config,{clock:()=>now}),token=store.addDevice('Xiaomi_HyperOS_TV');
 const server=createApp(store,config,{logger:()=>{},reviewer}).listen(0,'127.0.0.1');await once(server,'listening');const base='http://127.0.0.1:'+server.address().port;
 t.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));store.close();rmSync(dir,{recursive:true,force:true});});
 const call=(path,body,headers={})=>fetch(base+path,{method:body?'POST':'GET',headers:{...headers,...(body?{'Content-Type':'application/json',Origin:config.origin}:{})},body:body?JSON.stringify(body):undefined});
 const login=await call('/admin/login',{password}),identity=await login.json(),admin={Cookie:login.headers.get('set-cookie').split(';')[0],'X-CSRF-Token':identity.csrf};
 const submit=async(d=document)=>{const r=await call('/admin/display_submit',{request_id:randomUUID(),intent:'家长安排自然常识学习',document:d},admin);assert.equal(r.status,201);return r.json();};
 const heartbeat=async(extra={})=>call('/heartbeat',{device:'Xiaomi_HyperOS_TV',app:'com.android.launcher',is_playing:false,event_id:randomUUID(),...extra},{Authorization:'Bearer '+token});
 return {store,config,call,admin,submit,heartbeat,advance:ms=>now+=ms,now:()=>now};
}
test('年龄/科目题库：数学答案范围、语文英语选择题、非法配置拒绝',()=>{
 assert.throws(()=>validateLearning({age_band:'unknown',subjects:['math']}));assert.throws(()=>validateLearning({age_band:'7-9',subjects:[]}));
 for(const age_band of ['4-6','7-9','10-12','13+'])for(const subject of ['math','chinese','english'])for(let i=0;i<12;i++){
  const q=pickQuestion({age_band,subjects:[subject]});assert.equal(q.subject,subject);assert.ok(Number.isInteger(q.answer));assert.ok(q.answer>=0&&q.answer<=100);
  if(subject!=='math'){assert.equal(q.choices.length,4);assert.ok(q.answer>=1&&q.answer<=4);}
 }
});
test('声明式页面拒绝脚本/HTML/链接/未知字段；未配置审核服务失败关闭',async()=>{
 assert.deepEqual(validatePresentation(document),document);
 for(const value of [{...document,html:'injected'}, {...document,pages:[{heading:'x',body:'https://example.com'}]},{...document,pages:[{heading:'x',body:'<script>1</script>'}]},{...document,pages:[]}])assert.throws(()=>validatePresentation(value));
 await assert.rejects(()=>reviewPresentation({},{endpoint:'',keyFile:''}),/not configured/);
});
test('审核错误/拒绝/摘要不匹配均不可发布，父母确认不可跳过',async t=>{
 for(const mode of ['error','deny','wrong_digest']){
  await t.test(mode,async sub=>{const f=await setup(sub,{reviewer:async v=>{if(mode==='error')throw new Error('offline');return {decision:mode==='deny'?'deny':'allow',digest:mode==='wrong_digest'?'wrong':v.digest,context_digest:v.context_digest,policy_version:'v1'};}}),draft=await f.submit();
   assert.ok(draft.review_status!=='allow');assert.equal((await f.call('/admin/display_publish',{id:draft.id,confirm:true},f.admin)).status,409);
   f.advance(10000);const beat=await(await f.heartbeat({display_supported:true})).json();assert.equal(beat.display_command,undefined);
  });
 }
 const f=await setup(t),draft=await f.submit();assert.equal((await f.call('/admin/display_publish',{id:draft.id},f.admin)).status,400);
 assert.equal((await f.call('/admin/display_publish',{id:draft.id,confirm:true},f.admin)).status,409,'旧客户端不得被假定支持展示');
});
test('不播放也收到展示指令；页面连接/可见分别审计，不冒充观看或答题；撤回立即失效',async t=>{
 const f=await setup(t);await f.heartbeat({display_supported:true});const draft=await f.submit();assert.equal(draft.review_status,'allow');
 assert.equal((await f.call('/admin/display_publish',{id:draft.id,confirm:true,seconds:600},f.admin)).status,200);
 f.advance(10000);const beat=await(await f.heartbeat({display_supported:true})).json();assert.equal(beat.status,'allow');assert.equal(beat.display_command.id,draft.id);
 const bootstrap=await f.call('/bootstrap',{ticket:new URL(beat.display_command.launch_url).hash.slice(8)}),Cookie=bootstrap.headers.get('set-cookie').split(';')[0];
 const state=await(await f.call('/lock_status',null,{Cookie})).json();assert.equal(state.display.title,document.title);assert.equal(f.store.activeMath('Xiaomi_HyperOS_TV'),null);
 f.advance(10000);await f.heartbeat({display_supported:true,display_visible:draft.id,app:'com.ktcp.video',is_playing:true});assert.equal(f.store.get('SELECT count(*) n FROM usage_events').n,0);
 assert.ok(f.store.get('SELECT opened_ms,visible_ms FROM display_jobs WHERE id=?',draft.id).visible_ms);
 assert.equal((await f.call('/admin/display_cancel',{},f.admin)).status,200);assert.equal((await(await f.call('/lock_status',null,{Cookie})).json()).display,undefined);
});
test('代理凭证仅提交草稿，不能发布、不能用作电视或管理员凭证；撤销后拒绝',async t=>{
 const f=await setup(t),issued=await(await f.call('/admin/display_agent_token',{},f.admin)).json(),auth={Authorization:'Bearer '+issued.token};
 const body={request_id:randomUUID(),intent:'家长安排科学学习',document};const r=await f.call('/agent/displays',body,auth);assert.equal(r.status,201);const draft=await r.json();
 assert.equal((await f.call('/agent/displays',body,auth)).status,201);assert.equal((await f.call('/agent/displays',{...body,intent:'另一个用途'},auth)).status,409);
 assert.equal((await f.call('/admin/display_publish',{id:draft.id,confirm:true},auth)).status,401);
 assert.equal((await f.call('/heartbeat',{device:'Xiaomi_HyperOS_TV',app:'com.ktcp.video',is_playing:false,event_id:randomUUID()},auth)).status,401);
 assert.equal((await f.call('/agent/displays',{...body,device:'other'},auth)).status,400);
 await f.call('/admin/display_agent_token',{revoke_id:issued.id},f.admin);assert.equal((await f.call('/agent/displays',{...body,request_id:randomUUID()},auth)).status,401);
});
test('年龄配置变化使已审稿件失效；过期任务和停用家庭都不展示',async t=>{
 const f=await setup(t);await f.heartbeat({display_supported:true});const draft=await f.submit();await f.call('/admin/learning',{profile:{age_band:'4-6',subjects:['math']}},f.admin);
 assert.equal((await f.call('/admin/display_publish',{id:draft.id,confirm:true},f.admin)).status,409);
 const fresh=await f.submit();await f.call('/admin/display_publish',{id:fresh.id,confirm:true,seconds:30},f.admin);f.advance(31000);assert.equal((await(await f.heartbeat({display_supported:true})).json()).display_command,undefined);
});
test('学习/展示所有路由都校验家庭和设备边界',async t=>{
 const f=await setup(t);const response=await f.call('/admin/users',{username:'other_family',password:'other-isolated-user-123',label:'another household'},f.admin),user=(await response.json()).user;
 const login=await f.call('/admin/login',{username:'other_family',password:'other-isolated-user-123'}),session=await login.json(),other={Cookie:login.headers.get('set-cookie').split(';')[0],'X-CSRF-Token':session.csrf};
 for(const path of ['/admin/learning','/admin/displays'])assert.equal((await f.call(path+'?tenant=default',null,other)).status,403);
 for(const path of ['/admin/display_submit','/admin/display_publish','/admin/display_cancel','/admin/display_agent_token'])assert.equal((await f.call(path+'?device=Xiaomi_HyperOS_TV',{},other)).status,404);
 assert.equal((await f.call('/admin/learning?tenant='+user.tenant_id,{profile:{age_band:'13+',subjects:['english']}},f.admin)).status,200);
 assert.deepEqual((await(await f.call('/admin/learning',null,f.admin)).json()).profile,{age_band:'7-9',subjects:['math']});
});

test('审核网关协议：缺摘要、拒绝、非200、超大响应和重定向均不放行',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'tv-review-')),key=join(dir,'gateway.token'),original=globalThis.fetch;
 writeFileSync(key,'isolated-test-review-token',{mode:0o600});const input={digest:'a'.repeat(64),context_digest:'b'.repeat(64),intent:'教学',document};
 try{
  let options;
  globalThis.fetch=async(url,opts)=>{options=opts;return new Response(JSON.stringify({decision:'allow',digest:input.digest,context_digest:input.context_digest,policy_version:'v1'}));};
  assert.equal((await reviewPresentation(input,{endpoint:'https://review.example.com/check',keyFile:key})).decision,'allow');assert.equal(options.redirect,'error');
  for(const response of [new Response('{}'),new Response('offline',{status:503}),new Response('x'.repeat(20000))]){
   globalThis.fetch=async()=>response;await assert.rejects(()=>reviewPresentation(input,{endpoint:'https://review.example.com/check',keyFile:key}));
  }
  globalThis.fetch=async()=>{throw new Error('Redirect denied');};await assert.rejects(()=>reviewPresentation(input,{endpoint:'https://review.example.com/check',keyFile:key}));
 }finally{globalThis.fetch=original;rmSync(dir,{recursive:true,force:true});}
});

test('已审核内容不可替换；待审超时和七天清理保留观看流水',async t=>{
 const f=await setup(t);await f.heartbeat({display_supported:true});const draft=await f.submit();
 f.store.run('UPDATE display_jobs SET document_json=? WHERE id=?',JSON.stringify({...document,title:'changed after review'}),draft.id);
 assert.equal((await f.call('/admin/display_publish',{id:draft.id,confirm:true},f.admin)).status,409);
 f.store.run("UPDATE display_jobs SET review_status='pending' WHERE id=?",draft.id);f.advance(61000);f.store.cleanup();assert.equal(f.store.get('SELECT review_status FROM display_jobs WHERE id=?',draft.id).review_status,'error');
 f.store.run('INSERT INTO usage_events(timestamp,device_name,app_package,duration_seconds) VALUES(?,?,?,?)',f.now()/1000,'Xiaomi_HyperOS_TV','com.ktcp.video',10);
 f.advance(8*86400000);f.store.cleanup();assert.equal(f.store.get('SELECT count(*) n FROM display_jobs').n,0);assert.equal(f.store.get('SELECT count(*) n FROM usage_events').n,1);
});
