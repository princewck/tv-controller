import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync,mkdtempSync,writeFileSync,rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
const parser=new URL('../tv/audio-player.awk',import.meta.url).pathname;
function parse(input,uid='10038',pids=' 123 '){
 const r=spawnSync('awk',['-v','app_uid='+uid,'-v','app_pids='+pids,'-f',parser],{input,encoding:'utf8'});assert.equal(r.status,0,r.stderr);return r.stdout.trim();
}
test('音频快照只匹配当前播放器；历史started、通知、小爱与SoundPool不误计',()=>{
 const line=(pid,state,usage='MEDIA',type='AudioTrack',uid='10038')=>` AudioPlaybackConfiguration piid:1 type:android.media.${type} u/pid:${uid}/${pid}(player) state:${state} attr:AudioAttributes: usage=USAGE_${usage}`;
 assert.equal(parse('players:\n'+line(123,'started')+'\n ducked players piids:\n'),'true');
 assert.equal(parse('players:\n'+line(123,'paused')+'\n ducked players piids:\nEvents log: player\n player event:started'),'false');
 assert.equal(parse('players:\n'+line(321,'started','MEDIA','AudioTrack','1000')+'\n ducked players piids:\n'),'false');
 assert.equal(parse('players:\n'+line(123,'started','NOTIFICATION')+'\n ducked players piids:\n'),'false');
 assert.equal(parse('players:\n'+line(123,'started','MEDIA','SoundPool')+'\n ducked players piids:\n'),'false');
 assert.equal(parse('unsupported output'),'unknown');
 assert.equal(parse('players:\n'+line(123,'started','MEDIA','MediaPlayer','1000')+'\n ducked players piids:\n','1000'),'true');
});
test('上海周查询补齐7天与应用，奖励不影响原始分钟数',()=>{
 const db=new DatabaseSync(':memory:');db.exec(readFileSync(new URL('../sql/schema.sql',import.meta.url),'utf8'));
 db.prepare('INSERT INTO devices VALUES(?,?,1,NULL,?)').run('TV','hash',0);
 // 使用固定测试时钟替换SQL now，避免测试随日期变化。
 const sql=readFileSync(new URL('../sql/grafana-week.sql',import.meta.url),'utf8').replaceAll("'now'","'2026-10-27T04:00:00Z'").replaceAll("'Xiaomi_HyperOS_TV'","'TV'");
 for(const [time,pkg,secs]of [['2026-10-19T00:00:00+08:00','com.ktcp.video',10],['2026-10-25T23:59:50+08:00','com.fongmi.android.tv',10],['2026-10-26T00:00:00+08:00','com.ktcp.video',10]])db.prepare('INSERT INTO usage_events(timestamp,device_name,app_package,duration_seconds) VALUES(?,?,?,?)').run(Date.parse(time)/1000,'TV',pkg,secs);
 const rows=db.prepare(sql).all();assert.equal(rows.length,49);
 assert.equal(new Set(rows.map(x=>x.time)).size,7);
 assert.equal(rows.reduce((n,r)=>n+r.minutes,0),20/60);
 assert.equal(rows[0].time,Date.parse('2026-10-19T00:00:00+08:00')/1000);
 db.close();
});
test('部署与构建脚本语法有效',()=>{
 for(const file of ['android-webview/build.sh','deploy/install-server.sh','deploy/backup.sh','deploy/reload-nginx.sh']){
  const r=spawnSync('bash',['-n',new URL('../'+file,import.meta.url).pathname],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);
 }
});
