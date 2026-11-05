import http from 'node:http';
import { readFile } from 'node:fs/promises';
const ORIGIN='https://can-you-defeat-comma.pages.dev';
const PORT=Number(process.env.PORT||10000);
const FILES=['pokemon_species_names','pokemon_form_names','move_names','item_names','ability_names','nature_names','type_names'];
let cachedScript,dict,dictExpiry=0;
function csvRow(line) {
 const a=[]; let v='', quoted=false;
 for(let i=0;i<line.length;i++) {
  const c=line[i];
  if(c==='"') {if(quoted&&line[i+1]==='"'){v+='"';i++;} else quoted=!quoted;}
  else if(c===','&&!quoted){a.push(v);v='';} else v+=c;
 }
 a.push(v); return a;
}
async function dictionary() {
 if(dict && Date.now()<dictExpiry) return dict;
 const result={};
 const all=await Promise.allSettled(FILES.map(async file=>{
  const u='https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/'+file+'.csv';
  const r=await fetch(u,{signal:AbortSignal.timeout(15000)});
  if(!r.ok) throw Error(file+': '+r.status);
  return {file,text:await r.text()};
 }));
 let count=0;
 for(const item of all){
  if(item.status!=='fulfilled') continue;
  count++; const {file,text}=item.value; const pairs=new Map();
  for(const line of text.split(/\r?\n/).slice(1)){
   if(!line) continue;
   const a=csvRow(line),lang=Number(a[1]);
   if(lang!==3&&lang!==11) continue;
   const value=file==='pokemon_form_names'?(a[3]||a[2]):a[2];
   if(!value) continue;
   const pair=pairs.get(a[0])||{};
   pair[lang]=value;pairs.set(a[0],pair);
  }
  for(const pair of pairs.values()) if(pair[3]&&pair[11]&&pair[3]!==pair[11]) result[pair[11]]=pair[3];
 }
 if(!count) throw Error('Translation dictionaries unavailable');
 dict={names:result,sources:count};dictExpiry=Date.now()+86400000;
 return dict;
}
function reply(res,status,body,type) {
 res.writeHead(status,{'content-type':type,'cache-control':'public,max-age=600','x-robots-tag':'noindex','x-content-type-options':'nosniff'});
 res.end(body);
}
const DROP=new Set(['connection','keep-alive','transfer-encoding','content-length','content-encoding','content-security-policy','content-security-policy-report-only','x-frame-options','strict-transport-security']);
http.createServer(async(req,res)=>{
 try {
  const current=new URL(req.url||'/','http://localhost');
  if(current.pathname==='/__ko__/health'){
   reply(res,200,JSON.stringify({status:'ok',upstream:ORIGIN}),'application/json;charset=utf-8');return;
  }
  if(current.pathname==='/__ko__/patch.js'){
   cachedScript||=await readFile(new URL('./patch.js',import.meta.url),'utf8');
   reply(res,200,cachedScript,'text/javascript;charset=utf-8');return;
  }
  if(current.pathname==='/__ko__/dictionary.json'){
   try{reply(res,200,JSON.stringify(await dictionary()),'application/json;charset=utf-8');}
   catch(e){reply(res,503,JSON.stringify({error:String(e)}),'application/json;charset=utf-8');}
   return;
  }
  const url=new URL(current.pathname+current.search,ORIGIN);
  const h=new Headers();
  const skip=new Set(['host','connection','content-length','content-encoding','accept-encoding','origin','referer','sec-fetch-site','sec-fetch-mode','sec-fetch-dest']);
  for(const [k,v] of Object.entries(req.headers)) if(typeof v==='string'&&!skip.has(k.toLowerCase())) h.set(k,v);
  h.set('accept-encoding','identity');
  if(req.headers.origin) h.set('origin',ORIGIN);
  if(req.headers.referer) h.set('referer',ORIGIN+'/');
  const body=['GET','HEAD'].includes(req.method)?undefined:req;
  const r=await fetch(url,{method:req.method,headers:h,body,duplex:body?'half':undefined,redirect:'manual',signal:AbortSignal.timeout(120000)});
  const headers={};
  for(const [k,v] of r.headers) if(!DROP.has(k.toLowerCase())) headers[k]=v;
  headers['x-robots-tag']='noindex';headers['x-content-type-options']='nosniff';
  if(headers.location?.startsWith(ORIGIN)) headers.location=headers.location.slice(ORIGIN.length)||'/';
  if((r.headers.get('content-type')||'').includes('text/html')){
   let html=await r.text();
   const script='<script src="/__ko__/patch.js" defer></script>';
   html=/<\/head>/i.test(html)?html.replace(/<\/head>/i,script+'</head>'):script+html;
   headers['content-type']='text/html;charset=utf-8';headers['cache-control']='no-store';
   res.writeHead(r.status,headers);res.end(html);return;
  }
  res.writeHead(r.status,headers);
  if(!r.body){res.end();return;}
  const reader=r.body.getReader();
  while(true){const {done,value}=await reader.read();if(done) break;
   if(!res.write(Buffer.from(value))) await new Promise(ok=>res.once('drain',ok));
  }
  res.end();
 }catch(e){
  if(!res.headersSent){res.writeHead(502,{'content-type':'text/plain;charset=utf-8'});res.end('COMMA 원본 사이트 연결에 실패했습니다.\n'+String(e));}
  else res.destroy(e);
 }
}).listen(PORT,'0.0.0.0',()=>console.log('COMMA Korean gateway on port '+PORT));
