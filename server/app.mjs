import express from 'express';
import { readFileSync } from 'node:fs';
import { createHash,randomUUID,timingSafeEqual } from 'node:crypto';
import { HttpError } from './store.mjs';
import {installAdmin} from './admin-http.mjs';
export function cspFor(html){
  const hashes=tag=>[...html.matchAll(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`,'g'))]
    .map(m=>`'sha256-${createHash('sha256').update(m[1]).digest('base64')}'`).join(' ');
  return `default-src 'none'; script-src ${hashes('script')}; style-src ${hashes('style')}; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; object-src 'none'`;
}
const equal=(a,b)=>typeof a==='string'&&typeof b==='string'&&Buffer.byteLength(a)===Buffer.byteLength(b)&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
const cookieToken=req=>(req.headers.cookie||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('__Host-tv_session='))?.slice('__Host-tv_session='.length);
export function createApp(store,config,{logger=console.log,reviewer}={}){
  const app=express(),html=readFileSync(new URL('../public/math_test.html',import.meta.url),'utf8'),adminHtml=readFileSync(new URL('../public/admin.html',import.meta.url),'utf8');
  const pageCsp=cspFor(html+adminHtml);
  app.disable('x-powered-by');app.set('trust proxy','loopback');
  app.use((req,res,next)=>{
    res.set({'Cache-Control':'no-store','Content-Security-Policy':pageCsp,'Referrer-Policy':'no-referrer',
      'X-Content-Type-Options':'nosniff','X-Frame-Options':'DENY','Permissions-Policy':'camera=(), microphone=(), geolocation=()'});
    const started=Date.now(),id=randomUUID();res.set('X-Request-ID',id);
    // 不记录令牌、题目答案、Cookie、请求体、URL参数或设备播放记录。
    res.on('finish',()=>logger(JSON.stringify({id,method:req.method,path:req.path,status:res.statusCode,ms:Date.now()-started})));
    next();
  });
  // Nginx先按IP限流；应用再次限流并限制Map大小，避免匿名地址耗尽内存。
  const buckets=new Map();
  app.use((req,res,next)=>{
    const now=Date.now(),key=req.ip;
    if(buckets.size>10000){for(const[k,v]of buckets)if(v.reset<now)buckets.delete(k);}
    let b=buckets.get(key);
    if(!b||b.reset<now){if(buckets.size>=10000)return res.status(503).json({error:'Busy'});b={reset:now+60_000,count:0};buckets.set(key,b);}
    if(++b.count>180){res.set('Retry-After','60');return res.status(429).json({error:'Rate limit exceeded'});}
    next();
  });
  app.use((req,res,next)=>{if(req.method==='POST'&&!req.is('application/json'))return next(new HttpError(415,'JSON content type required'));next();});
  app.use(express.json({limit:'16kb',strict:true}));
  app.use((req,res,next)=>{if(req.method==='POST'&&(!req.body||typeof req.body!=='object'||Array.isArray(req.body)))throw new HttpError(400,'JSON object required');next();});
  app.get('/healthz',(req,res)=>{store.get('SELECT 1');res.json({status:'ok'});});
  app.get('/admin',(req,res)=>res.type('html').send(adminHtml));
  app.get(['/', '/math_test.html'],(req,res)=>res.type('html').send(html));
  const origin=(req,res,next)=>{
    if(req.get('Origin')!==config.origin)return next(new HttpError(403,'Same-origin browser request required'));
    next();
  };
  const browser=(req,res,next)=>{req.session=store.session(cookieToken(req));next();};
  const csrf=(req,res,next)=>{if(!equal(req.get('X-CSRF-Token'),req.session.csrf))throw new HttpError(403,'Invalid CSRF token');next();};
  app.post('/heartbeat',(req,res)=>{
    const auth=req.get('Authorization')||'';
    const device=store.device(auth.startsWith('Bearer ')?auth.slice(7):null);
    res.json(store.heartbeat(device,req.body));
  });
  app.post('/bootstrap',origin,(req,res)=>{
    const {token}=store.bootstrap(req.body.ticket);
    res.cookie('__Host-tv_session',token,{httpOnly:true,secure:true,sameSite:'strict',path:'/',maxAge:30*60_000});
    res.json({success:true});
  });
  app.get('/lock_status',browser,(req,res)=>res.json(store.browserState(req.session)));
  app.post('/answer',origin,browser,csrf,(req,res)=>res.json(store.answer(req.session,req.body)));
  app.post('/unlock',origin,browser,csrf,(req,res)=>res.json(store.unlock(req.session,req.body.nonce)));
  installAdmin(app,store,config,{origin,browser,csrf,reviewer});
  app.use((req,res)=>res.status(404).json({error:'Not found'}));
  app.use((err,req,res,next)=>{
    const status=err instanceof HttpError?err.status:(err.type==='entity.too.large'?413:err instanceof SyntaxError?400:500);
    if(status===500)logger(JSON.stringify({event:'internal_error',request_id:res.getHeader('X-Request-ID'),type:err.name}));
    res.status(status).json({error:status===500?'Internal server error':status===413?'Request too large':err.message});
  });
  return app;
}
