// 仅供服务器管理员读取本工程SQL，不提供公网任意SQL接口。
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
if(!process.argv[2])throw new Error('需要SQL文件路径');
const db=new DatabaseSync(process.env.DATABASE_PATH||'/var/lib/tv-parent-control/control.sqlite',{readOnly:true});
try{console.log(JSON.stringify(db.prepare(readFileSync(process.argv[2],'utf8')).all(),null,2));}finally{db.close();}
