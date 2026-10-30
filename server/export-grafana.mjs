import {DatabaseSync} from 'node:sqlite';
import {mkdirSync,renameSync,unlinkSync,existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
process.umask(0o077);
const root='/var/lib/tv-parent-report';
mkdirSync(root,{recursive:true,mode:0o750});execFileSync('chown',['root:grafana',root]);
const tmp=root+'/report-'+process.pid+'.sqlite';
if(existsSync(tmp))throw new Error('临时文件已存在');
const src=new DatabaseSync(process.env.DATABASE_PATH||'/var/lib/tv-parent-control/control.sqlite',{readOnly:true});
const dst=new DatabaseSync(tmp);
try{
 src.exec('BEGIN');dst.exec('BEGIN');
 dst.exec('CREATE TABLE usage_events(id INTEGER,timestamp INTEGER,device_name TEXT,app_package TEXT,duration_seconds INTEGER); CREATE TABLE math_sessions(id TEXT,device_name TEXT,day TEXT,opened_ms INTEGER,last_seen_ms INTEGER,completed_ms INTEGER,status TEXT,answer_count INTEGER,wrong_count INTEGER,reward_seconds INTEGER); CREATE INDEX usage_time_app ON usage_events(timestamp,app_package);');
 const usage=dst.prepare('INSERT INTO usage_events VALUES(?,?,?,?,?)'),math=dst.prepare('INSERT INTO math_sessions VALUES(?,?,?,?,?,?,?,?,?,?)');
 for(const row of src.prepare('SELECT id,timestamp,device_name,app_package,duration_seconds FROM usage_events WHERE device_name=?').iterate('Xiaomi_HyperOS_TV'))usage.run(...Object.values(row));
 for(const row of src.prepare('SELECT id,device_name,day,opened_ms,last_seen_ms,completed_ms,status,answer_count,wrong_count,reward_seconds FROM math_sessions WHERE device_name=?').iterate('Xiaomi_HyperOS_TV'))math.run(...Object.values(row));
 dst.exec('COMMIT');src.exec('COMMIT');
 if(dst.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')throw new Error('统计副本校验失败');
 dst.close();src.close();
 execFileSync('chown',['root:grafana',tmp]);execFileSync('chmod',['0640',tmp]);renameSync(tmp,root+'/report.sqlite');
 console.log('已导出仅含正式设备的统计副本，不含凭证、答案或验收设备。');
}catch(e){try{src.close();}catch{}try{dst.close();}catch{}try{unlinkSync(tmp);}catch{}throw e;}
