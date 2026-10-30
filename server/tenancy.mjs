// 租户边界由服务端会话和设备所有权决定，绝不信任客户端自报的租户/角色。
import {randomUUID,randomBytes,scrypt as scryptCb,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
import {HttpError,secret,hash} from './store.mjs';
const scrypt=promisify(scryptCb);
export async function passwordRecord(password){
 if(typeof password!=='string'||password.length<10||password.length>128)throw new HttpError(400,'Password must be 10..128 characters');
 const salt=randomBytes(16),digest=await scrypt(password,salt,64,{N:16384,r:8,p:1,maxmem:64*1024*1024});
 return {algorithm:'scrypt-v1',salt:salt.toString('hex'),digest:digest.toString('hex')};
}
export async function passwordMatches(password,record){
 if(typeof password!=='string'||password.length<1||password.length>128)return false;
 if(!record||record.algorithm!=='scrypt-v1'||! /^[0-9a-f]{32}$/.test(record.salt)||! /^[0-9a-f]{128}$/.test(record.digest))return false;
 const digest=await scrypt(password,Buffer.from(record.salt,'hex'),64,{N:16384,r:8,p:1,maxmem:64*1024*1024});
 return timingSafeEqual(digest,Buffer.from(record.digest,'hex'));
}
export function identityFor(store,session){
 if(!session)return null;
 const owner=store.get('SELECT * FROM admin_session_owners WHERE token_hash=?',session.token_hash);
 // v3的已有Cookie都来自文件口令管理员；保留身份，不把普通用户降级成管理员。
 if(!owner||owner.user_id===null)return {role:'superadmin',username:'admin',user_id:null,tenant_id:'default'};
 const user=store.get('SELECT u.* FROM users u JOIN tenants t USING(tenant_id) WHERE u.user_id=? AND u.enabled=1 AND t.enabled=1',owner.user_id);
 return user&&user.tenant_id===owner.tenant_id?{role:'user',username:user.username,user_id:user.user_id,tenant_id:user.tenant_id}:null;
}
export function scoped(store,req,{device=false}={}){
 const identity=req.identity;let tenant=req.query.tenant??identity.tenant_id;
 if(typeof tenant!=='string'||tenant.length>64)throw new HttpError(400,'Invalid tenant');
 if(identity.role!=='superadmin'&&tenant!==identity.tenant_id)throw new HttpError(403,'Tenant access denied');
 if(!store.get('SELECT 1 FROM tenants WHERE tenant_id=? AND enabled=1',tenant))throw new HttpError(404,'Tenant not found');
 const devices=store.db.prepare('SELECT d.device_name,o.label,d.enabled,d.created_at,d.last_heartbeat_ms FROM device_ownership o JOIN devices d USING(device_name) WHERE o.tenant_id=? ORDER BY d.created_at,d.device_name').all(tenant);
 const requested=req.query.device;
 if(requested!==undefined&&typeof requested!=='string')throw new HttpError(400,'Invalid device');
 const chosen=requested===undefined?devices[0]:devices.find(d=>d.device_name===requested);
 if((requested!==undefined||device)&&!chosen)throw new HttpError(404,'Device not found');
 return {tenant,devices,device:chosen?.device_name||null};
}
export function installTenancy(app,store,{origin,requireAdmin,adminCsrf,audit,hashWork}){
 const root=(req,res,next)=>{if(req.identity.role!=='superadmin')throw new HttpError(403,'Superadministrator required');next();};
 app.get('/admin/users',requireAdmin,root,(req,res)=>{
  const users=store.db.prepare('SELECT u.user_id,u.username,u.tenant_id,u.enabled,u.created_ms,t.label,(SELECT count(*) FROM device_ownership o WHERE o.tenant_id=u.tenant_id) device_count FROM users u JOIN tenants t USING(tenant_id) ORDER BY u.created_ms').all();
  res.json({users,server_now_ms:store.clock()});
 });
 app.post('/admin/users',origin,requireAdmin,adminCsrf,root,async(req,res)=>{
  const {username,password,label}=req.body;
  if(typeof username!=='string'||! /^[a-z0-9][a-z0-9_.-]{2,31}$/.test(username)||['admin','root'].includes(username))throw new HttpError(400,'Username must be 3..32 lowercase letters, numbers, dot, dash or underscore');
  if(typeof label!=='string'||!label.trim()||label.length>64)throw new HttpError(400,'Household label required (1..64 characters)');
  if(store.get('SELECT 1 FROM users WHERE username=?',username))throw new HttpError(409,'Username already exists');
  if(store.get('SELECT count(*) n FROM users').n>=1000)throw new HttpError(409,'Account limit reached');
  const record=await hashWork(()=>passwordRecord(password)),tenant=randomUUID(),id=randomUUID();
  store.tx(()=>{
   if(store.get('SELECT count(*) n FROM users').n>=1000)throw new HttpError(409,'Account limit reached');
   if(store.get('SELECT 1 FROM users WHERE username=?',username))throw new HttpError(409,'Username already exists');
   store.run('INSERT INTO tenants(tenant_id,label,created_ms) VALUES(?,?,?)',tenant,label.trim(),store.clock());
   store.run('INSERT INTO users(user_id,username,tenant_id,password_json,created_ms) VALUES(?,?,?,?,?)',id,username,tenant,JSON.stringify(record),store.clock());
   audit(req,'user_created',{user_id:id,username},tenant);
  });res.status(201).json({user:{user_id:id,username,tenant_id:tenant,enabled:1,label:label.trim()}});
 });
 app.post('/admin/user_update',origin,requireAdmin,adminCsrf,root,async(req,res)=>{
  const user=store.get('SELECT * FROM users WHERE user_id=?',typeof req.body.user_id==='string'?req.body.user_id:'');
  if(!user)throw new HttpError(404,'User not found');
  const {enabled,password}=req.body;
  if(enabled!==undefined&&typeof enabled!=='boolean')throw new HttpError(400,'Invalid enabled');
  if(enabled===undefined&&password===undefined)throw new HttpError(400,'No update supplied');
  const record=password===undefined?null:await hashWork(()=>passwordRecord(password));
  store.tx(()=>{
   if(enabled!==undefined){store.run('UPDATE users SET enabled=? WHERE user_id=?',enabled?1:0,user.user_id);store.run('UPDATE tenants SET enabled=? WHERE tenant_id=?',enabled?1:0,user.tenant_id);}
   if(record)store.run('UPDATE users SET password_json=? WHERE user_id=?',JSON.stringify(record),user.user_id);
   store.run('DELETE FROM admin_sessions WHERE token_hash IN(SELECT token_hash FROM admin_session_owners WHERE user_id=?)',user.user_id);
   if(enabled===false){
    store.run('DELETE FROM browser_sessions WHERE device_name IN(SELECT device_name FROM device_ownership WHERE tenant_id=?)',user.tenant_id);
    store.run('DELETE FROM launch_tickets WHERE device_name IN(SELECT device_name FROM device_ownership WHERE tenant_id=?)',user.tenant_id);
   }
   audit(req,record?'user_password_reset':'user_status_changed',{user_id:user.user_id,enabled:enabled??!!user.enabled},user.tenant_id);
  });res.json({success:true});
 });
 app.get('/admin/devices',requireAdmin,(req,res)=>{
  const scope=scoped(store,req);res.json({...scope,server_now_ms:store.clock()});
 });
 app.post('/admin/devices',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req),label=req.body.label;
  if(typeof label!=='string'||!label.trim()||label.length>64)throw new HttpError(400,'Device label required (1..64 characters)');
  const name='tv_'+randomUUID().replaceAll('-',''),token=secret();
  store.tx(()=>{
   if(scope.devices.length>=10)throw new HttpError(409,'Maximum 10 devices per household');
   store.addDevice(name,token,scope.tenant,label.trim());audit(req,'device_created',{device:name,label:label.trim()},scope.tenant);
  });
  // 明文仅在首次创建的已认证响应返回，不写审计，不提供后续查询接口。
  res.status(201).json({device:name,token,label:label.trim(),origin:store.config.origin,token_shown_once:true});
 });
 app.post('/admin/device_update',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req,{device:true}),enabled=req.body.enabled,rotate=req.body.rotate_token===true;
  if(enabled!==undefined&&typeof enabled!=='boolean')throw new HttpError(400,'Invalid enabled');
  if(enabled===undefined&&!rotate)throw new HttpError(400,'No update supplied');
  const token=rotate?secret():null;
  store.tx(()=>{
   if(enabled!==undefined)store.run('UPDATE devices SET enabled=? WHERE device_name=?',enabled?1:0,scope.device);
   if(token)store.run('UPDATE devices SET token_hash=? WHERE device_name=?',hash(token),scope.device);
   store.run('DELETE FROM browser_sessions WHERE device_name=?',scope.device);store.run('DELETE FROM launch_tickets WHERE device_name=?',scope.device);
   audit(req,rotate?'device_token_rotated':'device_status_changed',{device:scope.device,enabled},scope.tenant);
  });res.json({success:true,device:scope.device,...(token?{token,token_shown_once:true}:{})});
 });
}
