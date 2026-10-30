// 外部代理只能提交声明式内容，不能提交JS/HTML/URL。审核与家长发布均在服务端强制校验。
import {randomUUID} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {HttpError,hash,secret} from './store.mjs';
import {scoped} from './tenancy.mjs';
import {learningForDevice} from './learning.mjs';
function keys(value,allowed){if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).some(k=>!allowed.includes(k)))throw new HttpError(400,'Unexpected content fields');}
function text(value,max){if(typeof value!=='string'||!value.trim()||value.length>max||/[\u0000-\u0008\u000b-\u001f\u007f<>]/.test(value)||/(?:https?:|javascript:|data:|file:|content:|www\.)/i.test(value))throw new HttpError(400,'Only bounded plain text is accepted');return value.trim();}
export function validatePresentation(value){
 keys(value,['title','pages']);const title=text(value.title,80);
 if(!Array.isArray(value.pages)||value.pages.length<1||value.pages.length>10)throw new HttpError(400,'Presentation must contain 1..10 pages');
 const pages=value.pages.map(page=>{keys(page,['heading','body','bullets']);const result={heading:text(page.heading,100),body:text(page.body,1000)};
  if(page.bullets!==undefined){if(!Array.isArray(page.bullets)||page.bullets.length>6)throw new HttpError(400,'Too many bullets');result.bullets=page.bullets.map(v=>text(v,160));}return result;});
 const result={title,pages};if(Buffer.byteLength(JSON.stringify(result))>12000)throw new HttpError(400,'Presentation too large');return result;
}
export const audienceDigest=(store,device)=>hash(JSON.stringify(learningForDevice(store,device)));
// 网关由部署者配置，禁止代理在请求中指定审核地址、提供审核结论或替换内容摘要。
export async function reviewPresentation(input,{endpoint=process.env.CONTENT_REVIEW_ENDPOINT,keyFile=process.env.CONTENT_REVIEW_SECRET_FILE}={}){
 if(!endpoint||!keyFile)throw new Error('Content review service not configured');
 const url=new URL(endpoint);if(url.protocol!=='https:'||url.username||url.password||url.hash)throw new Error('Invalid review endpoint');
 const token=readFileSync(keyFile,'utf8').trim();if(!token||token.length>4096)throw new Error('Invalid review credential');
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),5000);
 try{
  const response=await fetch(url,{method:'POST',redirect:'error',signal:controller.signal,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify({purpose:'child_tv_display',...input})});
  if(response.status!==200)throw new Error('Review unavailable');let bytes=0,data='';
  for await(const part of response.body){bytes+=part.length;if(bytes>16384)throw new Error('Review response too large');data+=Buffer.from(part).toString('utf8');}
  const result=JSON.parse(data);
  if(!['allow','deny'].includes(result.decision)||result.digest!==input.digest||result.context_digest!==input.context_digest||typeof result.policy_version!=='string'||! /^[A-Za-z0-9_.-]{1,80}$/.test(result.policy_version))throw new Error('Invalid review decision');
  return result;
 }finally{clearTimeout(timer);}
}
export function activeDisplay(store,device){
 if(!store.tenantEnabled(device))return null;
 const capability=store.get('SELECT 1 FROM client_capabilities WHERE device_name=? AND display_supported=1 AND received_ms>?',device,store.clock()-35000);if(!capability)return null;
 const row=store.get("SELECT * FROM display_jobs WHERE device_name=? AND state='published' AND review_status='allow' AND expires_ms>? ORDER BY created_ms DESC LIMIT 1",device,store.clock());
 if(row&&row.context_digest!==audienceDigest(store,device)){
  store.run("UPDATE display_jobs SET state='cancelled' WHERE id=?",row.id);store.audit(device,'display_cancelled',null,{job_id:row.id,reason:'audience_changed'});return null;
 }return row||null;
}
export function displayState(store,row){
 if(row.opened_ms===null){store.run('UPDATE display_jobs SET opened_ms=? WHERE id=? AND opened_ms IS NULL',store.clock(),row.id);store.audit(row.device_name,'display_page_connected',null,{job_id:row.id});}
 return {id:row.id,...JSON.parse(row.document_json),expires_ms:row.expires_ms};
}
export function installDisplay(app,store,{origin,requireAdmin,adminCsrf,audit,reviewer=reviewPresentation}){
 let reviewing=0;
 async function submit(scope,body,agent=null){
  keys(body,['request_id','intent','document']);if(! /^[0-9a-f-]{36}$/i.test(body.request_id||''))throw new HttpError(400,'Request UUID required');
  const intent=text(body.intent,600),document=validatePresentation(body.document),digest=hash(JSON.stringify({intent,document})),context_digest=audienceDigest(store,scope.device);
  const existing=store.get('SELECT * FROM display_jobs WHERE device_name=? AND request_id=?',scope.device,body.request_id);
  if(existing){if(existing.digest!==digest||existing.context_digest!==context_digest)throw new HttpError(409,'Request ID reused');return {id:existing.id,review_status:existing.review_status,duplicate:true};}
  if(store.get('SELECT count(*) n FROM display_jobs').n>=5000||store.get('SELECT count(*) n FROM display_jobs WHERE device_name=?',scope.device).n>=200)throw new HttpError(409,'Presentation storage limit reached');
  if(reviewing>=3)throw new HttpError(503,'Review queue busy');
  if(store.get('SELECT count(*) n FROM display_jobs WHERE device_name=? AND created_ms>?',scope.device,store.clock()-3600000).n>=20)throw new HttpError(429,'Maximum 20 submissions per device per hour');
  const id=randomUUID();store.run('INSERT INTO display_jobs(id,tenant_id,device_name,agent_id,request_id,intent,document_json,digest,context_digest,review_status,created_ms) VALUES(?,?,?,?,?,?,?,?,?,?,?)',id,scope.tenant,scope.device,agent,body.request_id,intent,JSON.stringify(document),digest,context_digest,'pending',store.clock());
  reviewing++;let result;
  try{result=await reviewer({intent,document,digest,context_digest,audience:learningForDevice(store,scope.device)});if(!result||!['allow','deny'].includes(result.decision)||result.digest!==digest||result.context_digest!==context_digest||typeof result.policy_version!=='string')throw new Error('Invalid review');store.run('UPDATE display_jobs SET review_status=?,review_policy=? WHERE id=?',result.decision,result.policy_version,id);}
  catch{store.run("UPDATE display_jobs SET review_status='error' WHERE id=?",id);}
  finally{reviewing--;}
  store.audit(scope.device,'display_submitted',null,{job_id:id,review_status:store.get('SELECT review_status FROM display_jobs WHERE id=?',id).review_status});
  return {id,review_status:store.get('SELECT review_status FROM display_jobs WHERE id=?',id).review_status};
 }
 app.get('/admin/displays',requireAdmin,(req,res)=>{const scope=scoped(store,req,{device:true});const jobs=store.db.prepare('SELECT id,intent,document_json,review_status,review_policy,state,created_ms,expires_ms,opened_ms,visible_ms FROM display_jobs WHERE device_name=? ORDER BY created_ms DESC LIMIT 30').all(scope.device).map(({document_json,...r})=>({...r,document:JSON.parse(document_json)}));const tokens=store.db.prepare('SELECT id,expires_ms,enabled FROM display_agent_tokens WHERE device_name=? ORDER BY created_ms DESC').all(scope.device);res.json({jobs,tokens});});
 app.post('/admin/display_submit',origin,requireAdmin,adminCsrf,async(req,res)=>{const scope=scoped(store,req,{device:true});res.status(201).json(await submit(scope,req.body));});
 app.post('/admin/display_publish',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req,{device:true});if(typeof req.body.id!=='string'||! /^[0-9a-f-]{36}$/i.test(req.body.id))throw new HttpError(400,'Draft UUID required');const row=store.get('SELECT * FROM display_jobs WHERE id=? AND device_name=? AND tenant_id=?',req.body.id,scope.device,scope.tenant);
  if(!row)throw new HttpError(404,'Draft not found');if(req.body.confirm!==true)throw new HttpError(400,'Explicit parent confirmation required');
  const seconds=req.body.seconds??600;if(!Number.isInteger(seconds)||seconds<30||seconds>1800)throw new HttpError(400,'Display duration must be 30..1800 seconds');
  if(hash(JSON.stringify({intent:row.intent,document:JSON.parse(row.document_json)}))!==row.digest)throw new HttpError(409,'Reviewed content digest mismatch');
  if(store.clock()-row.created_ms>86400000||row.review_status!=='allow'||row.context_digest!==audienceDigest(store,scope.device))throw new HttpError(409,'Content and current audience must pass review');
  const capability=store.get('SELECT 1 FROM client_capabilities WHERE device_name=? AND display_supported=1 AND received_ms>?',scope.device,store.clock()-35000);
  if(!capability)throw new HttpError(409,'TV client must be upgraded and report display support');
  store.tx(()=>{store.run("UPDATE display_jobs SET state='cancelled' WHERE device_name=? AND state='published'",scope.device);store.run("UPDATE display_jobs SET state='published',expires_ms=? WHERE id=?",store.clock()+seconds*1000,row.id);audit(req,'display_published',{job_id:row.id,device:scope.device,seconds},scope.tenant);});res.json({success:true});
 });
 app.post('/admin/display_cancel',origin,requireAdmin,adminCsrf,(req,res)=>{const scope=scoped(store,req,{device:true});store.tx(()=>{store.run("UPDATE display_jobs SET state='cancelled' WHERE device_name=? AND state='published'",scope.device);audit(req,'display_cancelled',{device:scope.device},scope.tenant);});res.json({success:true});});
 app.post('/admin/display_agent_token',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req,{device:true});if(req.body.revoke_id){if(typeof req.body.revoke_id!=='string'||! /^[0-9a-f-]{36}$/i.test(req.body.revoke_id))throw new HttpError(400,'Token UUID required');store.run('UPDATE display_agent_tokens SET enabled=0 WHERE id=? AND tenant_id=? AND device_name=?',req.body.revoke_id,scope.tenant,scope.device);audit(req,'display_agent_revoked',{},scope.tenant);return res.json({success:true});}
  if(store.get('SELECT count(*) n FROM display_agent_tokens WHERE device_name=? AND enabled=1 AND expires_ms>?',scope.device,store.clock()).n>=5)throw new HttpError(409,'Maximum 5 active agent credentials per device');
  const token=secret(),id=randomUUID(),expires=store.clock()+86400000;store.run('INSERT INTO display_agent_tokens VALUES(?,?,?,?,?,1,?)',id,scope.tenant,scope.device,hash(token),expires,store.clock());audit(req,'display_agent_issued',{token_id:id},scope.tenant);res.status(201).json({id,token,device:scope.device,expires_ms:expires,scope:'display:submit'});
 });
 app.post('/agent/displays',async(req,res)=>{
  const header=req.get('Authorization')||'',token=header.startsWith('Bearer ')?header.slice(7):'';
  const row=token.length>=32&&token.length<=128?store.get('SELECT * FROM display_agent_tokens WHERE token_hash=? AND enabled=1 AND expires_ms>?',hash(token),store.clock()):null;
  if(!row||!store.tenantEnabled(row.device_name)||!store.get('SELECT 1 FROM devices WHERE device_name=? AND enabled=1',row.device_name))throw new HttpError(401,'Invalid display agent credential');
  res.status(201).json(await submit({tenant:row.tenant_id,device:row.device_name},req.body,row.id));
 });
}
