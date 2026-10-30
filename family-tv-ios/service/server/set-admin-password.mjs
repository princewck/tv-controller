// 从标准输入读取口令，绝不打印或写入命令行参数；输出仅含随机盐和scrypt哈希。
import {scryptSync,randomBytes} from 'node:crypto';
import {readFileSync,writeFileSync,chmodSync} from 'node:fs';
const out=process.argv[2];if(!out)throw new Error('需要凭证输出路径');
const password=readFileSync(0,'utf8').replace(/\r?\n$/,'');
if(password.length<10||password.length>128)throw new Error('口令必须10至128字符');
const salt=randomBytes(16),digest=scryptSync(password,salt,64,{N:16384,r:8,p:1,maxmem:64*1024*1024});
writeFileSync(out,JSON.stringify({algorithm:'scrypt-v1',salt:salt.toString('hex'),digest:digest.toString('hex')})+'\n',{mode:0o600,flag:'wx'});chmodSync(out,0o600);
console.log('管理员口令哈希已写入指定文件，未输出明文。');
