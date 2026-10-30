import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { randomUUID } from 'node:crypto';
import { Store } from '../server/store.mjs';
import { loadConfig } from '../server/config.mjs';
import { createApp,cspFor } from '../server/app.mjs';
import { readFileSync } from 'node:fs';
async function setup(t){
 const config={...loadConfig({}),databasePath:':memory:',dailyLimit:10};
 const store=new Store(config),token=store.addDevice('Xiaomi_HyperOS_TV');
 const logs=[],server=createApp(store,config,{logger:x=>logs.push(x)}).listen(0,'127.0.0.1');await once(server,'listening');
 t.after(async()=>{await new Promise(r=>server.close(r));store.close();});
 const base=`http://127.0.0.1:${server.address().port}`;
 const call=(url,body,headers={})=>fetch(base+url,{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json',...headers}:headers,body:body?JSON.stringify(body):undefined});
 return {config,store,token,base,call,logs};
}
test('完整HTTP链路、cookie属性、CSRF、服务端三题与幂等解锁',async t=>{
 const f=await setup(t),auth={Authorization:'Bearer '+f.token};
 const health=await f.call('/healthz');assert.equal(health.status,200);
 assert.equal((await f.call('/heartbeat',{device:'Xiaomi_HyperOS_TV',app:'com.fongmi.android.tv',is_playing:true,event_id:randomUUID()})).status,401);
 const hb=await f.call('/heartbeat',{device:'Xiaomi_HyperOS_TV',app:'com.fongmi.android.tv',is_playing:true,event_id:randomUUID()},auth);
 const state=await hb.json();assert.equal(state.status,'lock');
 const ticket=new URL(state.launch_url).hash.slice(8);
 assert.equal((await f.call('/bootstrap',{ticket},{Origin:'https://bad.invalid'})).status,403);
 const boot=await f.call('/bootstrap',{ticket},{Origin:f.config.origin});assert.equal(boot.status,200);
 const sc=boot.headers.get('set-cookie');assert.match(sc,/HttpOnly/i);assert.match(sc,/Secure/);assert.match(sc,/SameSite=Strict/);
 const Cookie=sc.split(';')[0],headers={Cookie,Origin:f.config.origin};
 let browser=await(await f.call('/lock_status',null,{Cookie})).json();
 assert.ok(browser.question);assert.equal(browser.question.expected_answer,undefined);
 assert.equal((await f.call('/unlock',{nonce:'fake'},headers)).status,403);
 assert.equal((await f.call('/unlock',{nonce:'fake'},{...headers,'X-CSRF-Token':browser.csrf})).status,403);
 let result;
 for(let i=0;i<3;i++){
  if(i)await new Promise(r=>setTimeout(r,810));
  const match=browser.question.text.match(/(\d+) ([+−]) (\d+)/),a=Number(match[1]),b=Number(match[3]);
  const response=await f.call('/answer',{question_id:browser.question.id,answer:match[2]==='+'?a+b:a-b,attempt_id:randomUUID()},{...headers,'X-CSRF-Token':browser.csrf});
  assert.equal(response.status,200);result=await response.json();browser.question=result.question;
 }
 const unlock=await f.call('/unlock',{nonce:result.ready_nonce},{...headers,'X-CSRF-Token':browser.csrf});
 assert.equal(unlock.status,200);assert.equal((await unlock.json()).credit_seconds,1200);
 const replay=await f.call('/unlock',{nonce:result.ready_nonce},{...headers,'X-CSRF-Token':browser.csrf});
 assert.equal((await replay.json()).duplicate,true);
 assert.ok(f.logs.every(x=>!x.includes(f.token)&&!x.includes(ticket)&&!x.includes(browser.csrf)));
});
test('异常JSON、Content-Type、超大包、未知路由和安全响应头',async t=>{
 const f=await setup(t);
 assert.equal((await fetch(f.base+'/heartbeat',{method:'POST',headers:{'Content-Type':'application/json'},body:'{'})).status,400);
 assert.equal((await fetch(f.base+'/heartbeat',{method:'POST',body:'wrong'})).status,415);
 assert.equal((await f.call('/heartbeat',{x:'a'.repeat(20000)})).status,413);
 assert.equal((await f.call('/nonexistent')).status,404);
 const page=await f.call('/');assert.equal(page.status,200);
 assert.equal(page.headers.get('content-security-policy'),cspFor(readFileSync(new URL('../public/math_test.html',import.meta.url),'utf8')+readFileSync(new URL('../public/admin.html',import.meta.url),'utf8')));
 assert.equal(page.headers.get('x-content-type-options'),'nosniff');
 assert.equal(page.headers.get('x-powered-by'),null);
});
