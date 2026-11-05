(() => {
'use strict';
const names=new Map(Object.entries({
 'COMMAのサーバーに接続できませんでした':'이 주소에서는 COMMA AI 서버에 연결할 수 없습니다. 원본 사이트에서 대전해 주세요.',
 'COMMAのサーバーが応答できませんでした':'COMMA AI 서버가 응답하지 않았습니다',
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
/* 한국어 UI 안내 문구·설명 전체 문장 우선 매칭: 2026-11-06 */
for (const [ja,ko] of [
 [
  "ポケモンチャンピオンズ レギュレーション M-C・シングルバトル（6匹から3匹を選出）",
  "포켓몬 챔피언스 레귤레이션 M-C · 싱글배틀 (6마리 중 3마리 선출)"
 ],
 [
  "レギュレーション M-C・シングルバトル（6匹から3匹を選出）",
  "레귤레이션 M-C · 싱글배틀 (6마리 중 3마리 선출)"
 ],
 [
  "COMMA は自己対戦で鍛えたポケモンチャンピオンズの対戦 AI です。COMMA の構築は同じレギュレーションの構築プールから毎回ランダムに選ばれます。あなたの構築を選んだら、そのままブラウザで対戦できます。",
  "COMMA는 자가 대전을 통해 학습한 포켓몬 챔피언스 대전 AI입니다. COMMA의 파티는 같은 레귤레이션에 속한 파티 목록에서 매번 무작위로 선택됩니다. 내 파티를 선택하면 브라우저에서 바로 대전할 수 있습니다."
 ],
 [
  "COMMA が戦うのはこのページの中の対戦だけです。ゲーム本体やランクマッチにはつながらず、実際の対戦で次の手を教える使い方もできません。",
  "COMMA는 이 웹페이지 안에서만 대전합니다. 실제 게임이나 랭크배틀과 연결되지 않으며, 실제 대전 중 다음 행동을 추천받는 용도로도 사용할 수 없습니다."
 ],
 [
  "画面上部の「難易度」を「ハード」にすると、COMMA が強くなります（1 手に数秒かかります）。",
  "화면 위쪽에서 난이도를 '어려움'으로 바꾸면 COMMA가 더 강해집니다. (한 번 행동을 결정하는 데 몇 초가 걸립니다.)"
 ],
 [
  "登録した構築はこのブラウザのCookieに保存されます。Cookieを削除すると登録内容も消えます。",
  "등록한 파티는 이 브라우저의 쿠키에 저장됩니다. 쿠키를 삭제하면 등록한 파티도 사라집니다."
 ],
 [
  "両方の席を COMMA が操作する対戦を眺めます。それぞれの構築は、登録済みパーティか、ランダムな構築（同じレギュレーションの構築プールから）を選べます。難易度はノーマルです。",
  "COMMA끼리 대전하는 모습을 관전합니다. 양쪽 모두 등록한 파티 또는 무작위 파티(같은 레귤레이션의 파티 목록)를 선택할 수 있습니다. 난이도는 보통으로 고정됩니다."
 ],
 [
  "観戦に使えるのは、登録してから90秒たったパーティです（対戦にはすぐ使えます）。実際のランクマッチの選出中に相手のパーティを登録して、COMMA に自分の選出を決めさせる使い方を防ぐためです。",
  "관전 모드에서는 등록 후 90초가 지난 파티만 사용할 수 있습니다. (일반 대전에서는 등록 직후 사용할 수 있습니다.) 실제 랭크배틀 선출 중에 상대 파티를 등록하고 COMMA에게 내 선출을 결정하게 하는 악용을 막기 위한 제한입니다."
 ],
 [
  "レギュレーション M-C の6匹分のテキストを貼り付けてください。対応している構築か対戦エンジンで確認してから保存します。",
  "레귤레이션 M-C의 포켓몬 6마리 정보가 들어 있는 텍스트를 붙여 넣으세요. 대전 엔진에서 사용할 수 있는 파티인지 확인한 뒤 저장합니다."
 ],
 [
  "性格・実数値・努力値・技を読み取ります",
  "성격·실능력치·노력치·기술을 인식합니다"
 ],
 [
  "アプリでは COMMA を利用したより高度な分析が可能です:",
  "앱에서는 COMMA를 활용해 더 자세한 분석을 할 수 있습니다:"
 ],
 [
  "個人による非公式のファン作品です。株式会社ポケモン・任天堂・テレビ東京とは関係ありません。",
  "개인이 제작한 비공식 팬 작품으로, 주식회사 포켓몬·닌텐도·TV 도쿄와는 관계가 없습니다."
 ],
 [
  "ポケモン対戦システム COMMA に挑戦しよう",
  "포켓몬 대전 AI COMMA에 도전하자!"
 ],
 [
  "COMMA のトレーナー",
  "COMMA 트레이너"
 ],
 [
  "作者",
  "제작자"
 ],
 [
  "保存した構築",
  "저장한 파티"
 ],
 [
  "保存済みの構築",
  "저장된 파티"
 ],
 [
  "ランダムな構築",
  "무작위 파티"
 ],
 [
  "構築を登録する",
  "파티 등록"
 ],
 [
  "パーティを選択",
  "파티 선택"
 ],
 [
  "パーティを選ぶ",
  "파티 고르기"
 ],
 [
  "登録したパーティ",
  "등록한 파티"
 ],
 [
  "試合を開始",
  "대전 시작"
 ],
 [
  "対戦を開始",
  "대전 시작"
 ],
 [
  "もう一度対戦",
  "다시 대전"
 ],
 [
  "次の対戦へ",
  "다음 대전"
 ],
 [
  "対戦を終了",
  "대전 종료"
 ],
 [
  "対戦結果",
  "대전 결과"
 ],
 [
  "対戦を振り返る",
  "대전 복기"
 ],
 [
  "勝敗",
  "승패"
 ],
 [
  "相手の選出",
  "상대 선출"
 ],
 [
  "自分の選出",
  "내 선출"
 ],
 [
  "選出を決定",
  "선출 확정"
 ],
 [
  "選出を確定",
  "선출 확정"
 ],
 [
  "選出してください",
  "선출해 주세요"
 ],
 [
  "6匹から3匹を選出",
  "6마리 중 3마리 선출"
 ],
 [
  "技を選ぶ",
  "기술 선택"
 ],
 [
  "技を選択",
  "기술 선택"
 ],
 [
  "交代先を選ぶ",
  "교체할 포켓몬 선택"
 ],
 [
  "降参しますか？",
  "항복하시겠습니까?"
 ],
 [
  "次のターン",
  "다음 턴"
 ],
 [
  "前のターン",
  "이전 턴"
 ],
 [
  "相手のポケモン",
  "상대 포켓몬"
 ],
 [
  "あなたのポケモン",
  "내 포켓몬"
 ],
 [
  "相手の構築",
  "상대 파티"
 ],
 [
  "自分の構築",
  "내 파티"
 ],
 [
  "能力変化",
  "능력 변화"
 ],
 [
  "状態異常",
  "상태이상"
 ],
 [
  "場の状態",
  "필드 상태"
 ],
 [
  "天候",
  "날씨"
 ],
 [
  "フィールド",
  "필드"
 ],
 [
  "残りのポケモン",
  "남은 포켓몬"
 ],
 [
  "対戦ログ",
  "대전 로그"
 ],
 [
  "読み込みに失敗しました",
  "불러오기에 실패했습니다"
 ],
 [
  "エラーが発生しました",
  "오류가 발생했습니다"
 ],
 [
  "登録に失敗しました",
  "등록에 실패했습니다"
 ],
 [
  "保存しました",
  "저장했습니다"
 ],
 [
  "登録しました",
  "등록했습니다"
 ],
 [
  "戻る",
  "돌아가기"
 ],
 [
  "閉じる",
  "닫기"
 ],
 [
  "確認",
  "확인"
 ],
 [
  "キャンセル",
  "취소"
 ],
 [
  "削除",
  "삭제"
 ],
 [
  "保存",
  "저장"
 ],
 [
  "設定",
  "설정"
 ],
 [
  "情報",
  "정보"
 ],
 [
  "再試行",
  "다시 시도"
 ],
 [
  "お待ちください",
  "잠시만요"
 ],
 [
  "しばらくお待ちください",
  "잠시만 기다려 주세요"
 ],
 [
  "選択してください",
  "선택해 주세요"
 ],
 [
  "読み込み中",
  "불러오는 중"
 ],
 [
  "対戦中",
  "대전 중"
 ],
 [
  "パーティ登録",
  "파티 등록"
 ]
]) names.set(ja,ko);
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