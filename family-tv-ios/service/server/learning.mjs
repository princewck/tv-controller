// 年龄分组仅作家长可修改的默认题库选择，不收集生日，不代替课程评估。
import {randomInt} from 'node:crypto';
import {HttpError} from './store.mjs';
import {scoped} from './tenancy.mjs';
export const AGE_BANDS=['4-6','7-9','10-12','13+'];
export const SUBJECTS=['math','chinese','english'];
export function validateLearning(input){
 if(!input||!AGE_BANDS.includes(input.age_band)||!Array.isArray(input.subjects)||!input.subjects.length||input.subjects.length>3||input.subjects.some(s=>!SUBJECTS.includes(s)))throw new HttpError(400,'Invalid learning profile');
 return {age_band:input.age_band,subjects:[...new Set(input.subjects)]};
}
export function learningForTenant(store,tenant='default'){
 const row=store.get('SELECT config_json FROM tenant_learning WHERE tenant_id=?',tenant);
 return row?JSON.parse(row.config_json):{age_band:'7-9',subjects:['math']};
}
export function learningForDevice(store,name){return learningForTenant(store,store.tenantForDevice(name));}
const CHINESE=[
 [['太阳从哪个方向升起？',['东','西','南','北'],1],['“上”的反义词是？',['大','下','左','多'],2]],
 [['“亡羊补牢”告诉我们什么？',['犯错后及时补救','永远不再尝试','只看眼前利益','忽略问题'],1],['“静夜思”的作者是谁？',['杜甫','白居易','李白','王维'],3]],
 [['“举头望明月”下一句是？',['低头思故乡','春风吹又生','更上一层楼','处处闻啼鸟'],1],['下列哪个词语表示专心？',['心不在焉','全神贯注','三心二意','东张西望'],2]],
 [['“温故而知新”强调什么？',['只学新知识','复习旧知识获得新理解','忽略过去','单纯背诵'],2],['“海内存知己”下一句是？',['天涯若比邻','长河落日圆','春风又绿江南岸','一览众山小'],1]]
];
const ENGLISH=[
 [['Which word means 苹果?',['apple','cat','sun','book'],1],['Which word is a color?',['dog','red','desk','bird'],2]],
 [['Choose: She ___ a book.',['have','has','having','had have'],2],['Which word means 星期一?',['Sunday','Friday','Monday','Saturday'],3]],
 [['Choose: We ___ TV yesterday.',['watch','watches','watched','watching'],3],['The opposite of early is:',['late','fast','near','small'],1]],
 [['Choose: If it rains, we ___ at home.',['will stay','stayed','staying','has stayed'],1],['Choose: This book is ___ than that one.',['interesting','more interesting','most interesting','interest'],2]]
];
export function pickQuestion(profile){
 const level=AGE_BANDS.indexOf(profile.age_band),subject=profile.subjects[randomInt(profile.subjects.length)];
 if(subject!=='math'){
  const bank=(subject==='chinese'?CHINESE:ENGLISH)[level],item=bank[randomInt(bank.length)];
  return {text:item[0],choices:item[1],answer:item[2],subject,age_band:profile.age_band};
 }
 if(level>=2){const a=randomInt(2,11),b=randomInt(2,11);return {text:`${a} × ${b} = ?`,answer:a*b,subject,age_band:profile.age_band};}
 const max=level===0?10:100,a=randomInt(max+1),plus=randomInt(2)===1,b=plus?randomInt(max-a+1):randomInt(a+1);
 return {text:`${a} ${plus?'+':'−'} ${b} = ?`,answer:plus?a+b:a-b,subject,age_band:profile.age_band};
}
export function installLearning(app,store,{origin,requireAdmin,adminCsrf,audit}){
 app.get('/admin/learning',requireAdmin,(req,res)=>{const scope=scoped(store,req);res.json({profile:learningForTenant(store,scope.tenant),age_bands:AGE_BANDS,subjects:SUBJECTS});});
 app.post('/admin/learning',origin,requireAdmin,adminCsrf,(req,res)=>{
  const scope=scoped(store,req),profile=validateLearning(req.body.profile);
  store.tx(()=>{store.run('INSERT INTO tenant_learning VALUES(?,?,?) ON CONFLICT(tenant_id) DO UPDATE SET config_json=excluded.config_json,updated_ms=excluded.updated_ms',scope.tenant,JSON.stringify(profile),store.clock());audit(req,'learning_changed',{profile},scope.tenant);});
  res.json({success:true,profile});
 });
}
