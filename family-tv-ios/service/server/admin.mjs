// 仅能在服务器本地使用的运维入口；没有公开“管理员充值”HTTP接口。
import { writeFileSync,chmodSync } from 'node:fs';
import { Store,hash } from './store.mjs';
import { loadConfig } from './config.mjs';
process.umask(0o077);
const [action,name,arg]=process.argv.slice(2);
if(!['create-device','revoke-device','rotate-token'].includes(action)||!name){
  console.error('用法：node --env-file=.env server/admin.mjs create-device 设备名 /安全路径/token\n或 revoke-device 设备名 / rotate-token 设备名 /安全路径/token');process.exit(1);
}
const store=new Store(loadConfig());
try{
  if(action==='revoke-device'){
    const result=store.run('UPDATE devices SET enabled=0 WHERE device_name=?',name);
    if(!result.changes)throw new Error('设备不存在');
    store.run('DELETE FROM browser_sessions WHERE device_name=?',name);
    console.log('设备已撤销；按当前fail-open策略，此设备将不再拦截。');
  }else{
    if(!arg)throw new Error('需要指定令牌输出文件；不会将令牌打印到终端或日志。');
    // 先独占创建文件，防止误覆盖既有令牌。写盘成功但事务失败则保留文件供运维核对。
    const {secret}=await import('./store.mjs');const token=secret();
    writeFileSync(arg,token+'\n',{mode:0o600,flag:'wx'});chmodSync(arg,0o600);
    store.tx(()=>{
      if(action==='create-device')store.addDevice(name,token);
      else{
        const result=store.run('UPDATE devices SET token_hash=?,enabled=1 WHERE device_name=?',hash(token),name);
        if(!result.changes)throw new Error('设备不存在');
        store.run('DELETE FROM browser_sessions WHERE device_name=?',name);
        store.run('DELETE FROM launch_tickets WHERE device_name=?',name);
      }
    });
    console.log('令牌已写入指定文件。通过受信任的初始配置流程交付电视，勿提交Git。');
  }
}finally{store.close();}
