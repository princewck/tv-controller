import { DatabaseSync,backup } from 'node:sqlite';
import { mkdirSync,existsSync,readFileSync,writeFileSync } from 'node:fs';
import { join } from 'node:path';
import {createHash} from 'node:crypto';
process.umask(0o077);
const source=process.env.DATABASE_PATH||'/var/lib/tv-parent-control/control.sqlite';
const out=process.env.BACKUP_DIR||'/var/backups/tv-parent-control';mkdirSync(out,{recursive:true,mode:0o700});
const file=join(out,'control-'+new Date().toISOString().replace(/[:.]/g,'-')+'.sqlite');
if(existsSync(file))throw new Error('拒绝覆盖现有备份');
const db=new DatabaseSync(source,{readOnly:true});
try{await backup(db,file);}finally{db.close();}
const check=new DatabaseSync(file,{readOnly:true});
try{if(check.prepare('PRAGMA integrity_check').get().integrity_check!=='ok')throw new Error('备份完整性失败');}finally{check.close();}
const sha=createHash('sha256').update(readFileSync(file)).digest('hex');writeFileSync(file+'.sha256',sha+'  '+file+'\n',{mode:0o600});
console.log(file);
