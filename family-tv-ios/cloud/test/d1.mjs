import {DatabaseSync} from 'node:sqlite';
import {readFileSync,readdirSync} from 'node:fs';
export class D1 {
 constructor(){this.db=new DatabaseSync(':memory:');for(const name of readdirSync(new URL('../migrations/',import.meta.url)).filter(x=>x.endsWith('.sql')).sort())this.db.exec(readFileSync(new URL('../migrations/'+name,import.meta.url),'utf8'));}
 prepare(sql){const db=this.db;let values=[];return {bind(...args){values=args;return this;},async first(column){const row=db.prepare(sql).get(...values);return row?(column?row[column]:row):null;},async all(){return {results:db.prepare(sql).all(...values)};},async run(){const r=db.prepare(sql).run(...values);return {success:true,meta:{changes:Number(r.changes)}};}};}
 async batch(statements){this.db.exec('BEGIN');try{const rows=[];for(const statement of statements)rows.push(await statement.run());this.db.exec('COMMIT');return rows;}catch(e){this.db.exec('ROLLBACK');throw e;}}
 close(){this.db.close();}
}
