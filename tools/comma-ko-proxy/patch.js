(() => {
'use strict';
const names=new Map(Object.entries({
 '難易度':'난이도','ノーマル':'보통','ハード':'어려움','読み込み中':'불러오는 중',
 '対戦エンジンと COMMA を準備しています…':'대전 엔진과 COMMA를 준비하는 중…',
 '続ける':'계속','やめる':'그만두기',
 'ポケモン対戦システム COMMA に挑戦しよう':'포켓몬 대전 AI COMMA에 도전하자!',
 'ポケモンチャンピオンズ M-C シングルの対戦練習':'포켓몬 챔피언스 M-C 싱글 대전 연습',
 'ルール':'규칙','シングルバトル':'싱글배틀',
 '1回だけ':'1회 대전','5連勝チャレンジ':'5연승 도전','10連勝チャレンジ':'10연승 도전',
 'ランダムなパーティで対戦':'랜덤 파티로 대전','登録済みパーティ':'등록한 파티',
 'COMMA 同士の対戦を観戦':'COMMA끼리 대전 관전','進め方':'진행 방식',
 '自動で進める':'자동 진행','1ターンずつ':'1턴씩 진행',
 '2P の構築':'2P의 파티','1P の構築':'1P의 파티',
 '全部見せる':'모두 공개','分かった分だけ':'알려진 것만 공개',
 '観戦する':'관전하기','ポケソルテキストを登録':'포케솔 텍스트 등록',
 'パーティ名':'파티 이름','パーティを登録':'파티 등록',
 'ポケソルテキスト':'포케솔 텍스트','例：壁エース構築':'예: 벽 전개 파티',
 '性格・実数値・努力値・技を読み取ります':'성격·실능력치·노력치·기술을 읽습니다',
 '選出':'선출','あなた':'나','対戦ログを保存':'대전 로그 저장',
 '構築を選び直す':'파티 다시 선택','場の状態':'필드 상태','行動を選ぶ':'행동 선택',
 '対戦の流れ':'대전 진행','対戦はブラウザ内で進みます':'대전은 브라우저 안에서 진행됩니다',
 '相手':'상대','自分':'자신','持ち物':'지닌물건','特性':'특성','性格':'성격',
 '努力値':'노력치','交代':'교체','攻撃':'공격','降参':'항복','残り':'남음',
 '勝利':'승리','敗北':'패배','ターン':'턴','天候':'날씨','素早さ':'스피드',
 '体力':'체력','ポケモン':'포켓몬','チャンピオンズ':'챔피언스',
 'ガブリアス':'한카리아스','カイリュー':'망나뇽','バンギラス':'마기라스',
 'リザードン':'리자몽','メタグロス':'메타그로스','ゲンガー':'팬텀',
 'じしん':'지진','りゅうせいぐん':'용성군','きあいのタスキ':'기합의띠',
 'こだわりスカーフ':'구애스카프','いのちのたま':'생명의구슬',
 'メガガブリアスＺ':'메가한카리아스Z','メガルカリオＺ':'메가루카리오Z'
}));
let pattern;
function compile(){
 const escape=s=>s.replace(/[|\\{}()[\]^$+*?.]/g,'\\$&');
 pattern=new RegExp([...names.keys()].sort((a,b)=>b.length-a.length).map(escape).join('|'),'g');
}
compile();
function translate(s){
 if(!s||!/[\u3040-\u30ff\u3400-\u9fff]/.test(s)) return s;
 return s.replace(pattern,m=>names.get(m)||m);
}
function translateText(node){
 const parent=node.parentElement;
 if(!parent||parent.closest('script,style,textarea,code,pre,[contenteditable="true"]')) return;
 const value=translate(node.nodeValue);
 if(value!==node.nodeValue) node.nodeValue=value;
}
function translateAttributes(el){
 if(!el?.getAttribute) return;
 for(const key of ['title','placeholder','aria-label']){
  const old=el.getAttribute(key);if(!old) continue;
  const value=translate(old);if(value!==old)el.setAttribute(key,value);
 }
}
function scan(root){
 if(root.nodeType===Node.TEXT_NODE){translateText(root);return;}
 if(root.nodeType!==Node.ELEMENT_NODE&&root.nodeType!==Node.DOCUMENT_NODE) return;
 translateAttributes(root);
 const tree=document.createTreeWalker(root,NodeFilter.SHOW_ELEMENT|NodeFilter.SHOW_TEXT);
 let node;
 while((node=tree.nextNode())){
  if(node.nodeType===Node.TEXT_NODE)translateText(node);
  else translateAttributes(node);
 }
}
function start(){
 document.documentElement.lang='ko';document.title='COMMA 한국어 대전 (비공식)';
 scan(document.body);
 const obs=new MutationObserver(records=>{
  for(const r of records){
   if(r.type==='characterData')translateText(r.target);
   else if(r.type==='attributes')translateAttributes(r.target);
   else for(const n of r.addedNodes)scan(n);
  }
 });
 obs.observe(document.body,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['title','placeholder','aria-label']});
 const notice=document.createElement('div');
 notice.textContent='비공식 한국어 · 원본 제작: fufufukakaka';
 Object.assign(notice.style,{position:'fixed',bottom:'5px',right:'5px',zIndex:'2147483647',font:'11px/1.3 sans-serif',color:'#fff',background:'#000b',padding:'4px 7px',borderRadius:'5px',opacity:'.75',pointerEvents:'none'});
 document.body.append(notice);
 fetch('/__ko__/dictionary.json').then(r=>{if(!r.ok)throw Error('dictionary HTTP '+r.status);return r.json();})
 .then(data=>{
  for(const [ja,ko] of Object.entries(data.names||{}))if(ja&&ko&&!names.has(ja))names.set(ja,ko);
  compile();scan(document.body);
  console.info('[COMMA KO] 명칭 적용: '+names.size+'개');
 }).catch(e=>console.warn('[COMMA KO] 기본 번역만 활성화:',e));
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});
else start();
})();