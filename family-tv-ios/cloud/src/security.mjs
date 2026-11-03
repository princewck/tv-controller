import {randomBytes,createHash,scrypt as scryptCb,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
const scrypt=promisify(scryptCb);
export class HTTPError extends Error {constructor(status,message){super(message);this.status=status;}}
export const secret=()=>randomBytes(32).toString('base64url');
export const hash=value=>createHash('sha256').update(value).digest('hex');
export const equal=(a,b)=>typeof a==='string'&&typeof b==='string'&&Buffer.byteLength(a)===Buffer.byteLength(b)&&timingSafeEqual(Buffer.from(a),Buffer.from(b));
export async function passwordRecord(password){
 if(typeof password!=='string'||password.length<8||password.length>128)throw new HTTPError(400,'Password must be 8..128 characters');
 const salt=randomBytes(16);const digest=await scrypt(password,salt,64,{N:16384,r:8,p:1,maxmem:64*1024*1024});
 return JSON.stringify({salt:salt.toString('hex'),digest:digest.toString('hex')});
}
export async function passwordMatches(password,record){
 if(typeof password!=='string'||password.length>128)return false;
 const value=JSON.parse(record);const digest=await scrypt(password,Buffer.from(value.salt,'hex'),64,{N:16384,r:8,p:1,maxmem:64*1024*1024});
 return timingSafeEqual(digest,Buffer.from(value.digest,'hex'));
}
export async function bodyOf(request){
 if(!request.headers.get('content-type')?.startsWith('application/json'))throw new HTTPError(415,'JSON required');
 const reader=request.body?.getReader();let size=0;const chunks=[];
 if(!reader)return {};
 for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>32768){await reader.cancel();throw new HTTPError(413,'Request too large');}chunks.push(value);}
 const bytes=new Uint8Array(size);let pos=0;for(const value of chunks){bytes.set(value,pos);pos+=value.length;}
 try {const data=JSON.parse(new TextDecoder().decode(bytes));if(!data||typeof data!=='object'||Array.isArray(data))throw 0;return data;}
 catch {throw new HTTPError(400,'Invalid JSON');}
}
export async function rateLimit(db,key,limit,window,now){
 const row=await db.prepare(`INSERT INTO rate_limits VALUES(?,1,?) ON CONFLICT(key) DO UPDATE SET count=CASE WHEN reset_ms<=? THEN 1 ELSE count+1 END,reset_ms=CASE WHEN reset_ms<=? THEN excluded.reset_ms ELSE reset_ms END RETURNING count,reset_ms`).bind(hash(key),now+window,now,now).first();
 if(row.count>limit)throw new HTTPError(429,'Too many attempts; try later');
}
export async function sessionFor(db,request,now){
 const token=(request.headers.get('cookie')||'').split(';').map(x=>x.trim()).find(x=>x.startsWith('__Host-tv_admin='))?.slice(16);
 if(!token||token.length>128)throw new HTTPError(401,'Login required');
 const row=await db.prepare('SELECT s.*,h.username,h.policy_json FROM sessions s JOIN households h ON h.id=s.household_id WHERE s.token_hash=? AND s.expires_ms>?').bind(hash(token),now).first();
 if(!row)throw new HTTPError(401,'Login required');return row;
}
export function requireOrigin(request,origin){if(request.headers.get('origin')!==origin)throw new HTTPError(403,'Invalid origin');}
export function requireCSRF(request,session){if(!equal(request.headers.get('x-csrf-token'),session.csrf))throw new HTTPError(403,'Invalid CSRF token');}
export const cookie=(token,maxAge)=>`__Host-tv_admin=${token}; Path=/; Max-Age=${maxAge}; Secure; HttpOnly; SameSite=Strict`;
export function json(value,status=200,headers={}){return new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',...headers}});}
