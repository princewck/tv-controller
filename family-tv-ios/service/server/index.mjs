import { loadConfig } from './config.mjs';
import { Store } from './store.mjs';
import { createApp } from './app.mjs';
process.umask(0o077);
const config=loadConfig(),store=new Store(config);
const app=createApp(store,config);
const server=app.listen(config.port,'127.0.0.1',()=>console.log(JSON.stringify({event:'ready',port:config.port,origin:config.origin})));
server.requestTimeout=10_000;server.headersTimeout=12_000;server.keepAliveTimeout=5_000;
const gc=setInterval(()=>{try{store.cleanup();}catch(e){console.error(JSON.stringify({event:'cleanup_failed',type:e.name}));}},60_000);gc.unref();
let stopping=false;
function stop(){if(stopping)return;stopping=true;clearInterval(gc);store.events.emit('shutdown');server.close(()=>{store.close();process.exit(0);});setTimeout(()=>process.exit(1),10_000).unref();}
process.on('SIGTERM',stop);process.on('SIGINT',stop);
