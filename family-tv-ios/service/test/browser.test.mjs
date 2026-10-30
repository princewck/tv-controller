import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { existsSync } from 'node:fs';
import { chromium } from '@playwright/test';
import { Store } from '../server/store.mjs';
import { loadConfig } from '../server/config.mjs';
import { createApp } from '../server/app.mjs';
import { randomUUID } from 'node:crypto';
const exe=process.env.BROWSER_EXECUTABLE||'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
test('真实浏览器：安全Cookie、方向键、服务端判题、解锁与答题不计时', {skip:!existsSync(exe)},async t=>{
 let now=Date.parse('2026-10-27T12:00:00+08:00');
 const config={...loadConfig({}),databasePath:':memory:',dailyLimit:10},store=new Store(config,{clock:()=>now});
 const token=store.addDevice('Xiaomi_HyperOS_TV'),device=store.device(token);
 const beat=()=>store.heartbeat(device,{device:device.device_name,app:'com.fongmi.android.tv',is_playing:true,event_id:randomUUID()});
 const first=beat(),server=createApp(store,config,{logger:()=>{}}).listen(0,'127.0.0.1');await once(server,'listening');
 const base='http://127.0.0.1:'+server.address().port;
 const browser=await chromium.launch({executablePath:exe,headless:true});
 t.after(async()=>{await browser.close();await new Promise(r=>server.close(r));store.close();});
 const page=await browser.newPage({viewport:{width:1920,height:1080}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 // 测试域名保持真实origin，仅在测试浏览器内部路由到隔离的内存数据库，不改系统DNS或正式服务。
 await page.route(config.origin+'/**',async route=>{
  const url=new URL(route.request().url());
  const response=await route.fetch({url:base+url.pathname+url.search});await route.fulfill({response});
 });
 await page.goto(first.launch_url);
 await page.locator('#question').filter({hasText:/\d+ [+−] \d+ =/}).waitFor();
 assert.equal(await page.locator('button:focus').innerText(),'5');
 await page.keyboard.press('ArrowDown');assert.equal(await page.locator('button:focus').innerText(),'8');
 await page.keyboard.press('ArrowRight');assert.equal(await page.locator('button:focus').innerText(),'9');
 await page.keyboard.press('ArrowRight');assert.equal(await page.locator('button:focus').innerText(),'9');
 now+=10000;assert.equal(beat().watched_seconds,10);
 await page.screenshot({path:new URL('../docs/shots/02-math-browser-1920.png',import.meta.url).pathname});
 await page.setViewportSize({width:960,height:540});
 const bounds=await page.locator('#retry').boundingBox();assert.ok(bounds.y+bounds.height<=540,'电视CSS视口下底部按钮不能裁切');
 assert.ok((await page.locator('#question').boundingBox()).y>=0);
 await page.setViewportSize({width:1920,height:1080});
 for(let i=0;i<3;i++){
  now+=1000;
  const text=await page.locator('#question').innerText(),m=text.match(/(\d+) ([+−]) (\d+)/);
  assert.ok(m,text);const result=m[2]==='+'?Number(m[1])+Number(m[3]):Number(m[1])-Number(m[3]);
  for(const digit of String(result))await page.getByRole('button',{name:digit,exact:true}).click();
  await page.getByRole('button',{name:'确认',exact:true}).click();
  if(i<2)await page.locator('#progress').filter({has:page.locator('.done')}).waitFor();
  await page.waitForTimeout(100);
 }
 await page.locator('#heading').filter({hasText:'可以继续观看了'}).waitFor();
 assert.equal(store.state(device.device_name).credit_seconds,1200);
 assert.equal(store.get('SELECT status FROM math_sessions').status,'completed');
 assert.deepEqual(errors,[]);
});
