import {DatabaseSync} from 'node:sqlite';
const db=new DatabaseSync(process.env.DATABASE_PATH||'/var/lib/tv-parent-control/control.sqlite',{readOnly:true});
try{
 const device=process.argv[2]||'Xiaomi_HyperOS_TV';
 console.log(JSON.stringify({device,
  usage:db.prepare('SELECT * FROM daily_usage WHERE device_name=? ORDER BY day DESC LIMIT 7').all(device),
  math:db.prepare('SELECT * FROM math_sessions WHERE device_name=? ORDER BY opened_ms DESC LIMIT 10').all(device),
  events:db.prepare('SELECT timestamp,event_type,math_session_id,details_json FROM control_events WHERE device_name=? ORDER BY timestamp DESC LIMIT 20').all(device)
 },null,2));
}finally{db.close();}
