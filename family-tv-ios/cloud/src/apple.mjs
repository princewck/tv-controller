import root from '../certs/AppleRootCA-G3.cer';
import {HTTPError} from './security.mjs';
const cache=new Map();
async function verifier(env,environment){
 const {SignedDataVerifier,Environment}=await import('@apple/app-store-server-library');
 if(![Environment.PRODUCTION,Environment.SANDBOX].includes(environment))throw new HTTPError(403,'Unsupported Apple environment');
 if(environment===Environment.PRODUCTION&&!/^[0-9]+$/.test(env.APP_APPLE_ID||''))throw new HTTPError(503,'Production purchase verification is not configured');
 const key=[env.BUNDLE_ID,env.APP_APPLE_ID,environment].join(':');
 if(!cache.has(key))cache.set(key,new SignedDataVerifier([Buffer.from(root)],true,environment,env.BUNDLE_ID,environment===Environment.PRODUCTION?Number(env.APP_APPLE_ID):undefined));
 return cache.get(key);
}
// The decoded environment is only a verifier selection hint. Every payload
// is subsequently verified against Apple's chain, app identity and environment.
function environmentHint(jws,notification=false){
 try {const data=JSON.parse(Buffer.from(jws.split('.')[1],'base64url').toString());return notification?data.data?.environment:data.environment;}
 catch {throw new HTTPError(403,'Invalid Apple transaction');}
}
export async function verifyTransaction(jws,env){
 if(typeof jws!=='string'||jws.length>24000)throw new HTTPError(400,'Invalid transaction');
 try{return await (await verifier(env,environmentHint(jws))).verifyAndDecodeTransaction(jws);}
 catch(e){if(e instanceof HTTPError)throw e;throw new HTTPError(403,'Apple signature verification failed');}
}
export async function verifyNotification(jws,env){
 try{return await (await verifier(env,environmentHint(jws,true))).verifyAndDecodeNotification(jws);}
 catch(e){if(e instanceof HTTPError)throw e;throw new HTTPError(403,'Apple notification verification failed');}
}

export async function verifyAppTransaction(jws,env){
 if(typeof jws!=='string'||jws.length>24000)throw new HTTPError(400,'Invalid app transaction');
 try{
  const data=JSON.parse(Buffer.from(jws.split('.')[1],'base64url').toString());
  return await (await verifier(env,data.receiptType)).verifyAndDecodeAppTransaction(jws);
 }catch(e){if(e instanceof HTTPError)throw e;throw new HTTPError(403,'Apple app signature verification failed');}
}
