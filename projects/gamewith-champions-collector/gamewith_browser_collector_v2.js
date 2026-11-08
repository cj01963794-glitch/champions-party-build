/*
 GameWith Pokemon Champions DOM collector (Chrome DevTools Console / Snippets)
 - Run ONLY on a normally accessible GameWith article tab.
 - Does not bypass restrictions, login, or access controls.
 - Stops when no identifiable next-page button remains; stop reason is recorded.
 - Field XPaths were supplied by the user; live site structure may differ.
 - Progress is retained in window.__gamewithData for inspection/recovery.
*/
(async () => {
  'use strict';
  if (window.__gamewithRunning) {
    console.warn('GameWith 수집기가 이미 실행 중입니다.');
    return;
  }
  const config = {
    clickDelayMs: 650,        // 상세정보를 펼친 뒤 안정화 대기
    pageDelayMs: 900,         // 페이지 전환 후 안정화 대기
    detailTimeoutMs: 3500,
    pageTimeoutMs: 12000,
    maxPages: 1000,           // 안전 상한. 파티나 실제 페이지 수를 가정하지 않음
    checkpointEvery: 0       // 0=마지막에 한 번 다운로드, 10=10페이지마다 중간 파일도 다운로드
  };
  const app = document.getElementById('PokeChampionsBuildApp');
  if (!app) {
    console.error('PokeChampionsBuildApp이 없습니다. 정상적인 파티 페이지인지 확인하세요.');
    return;
  }
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const xp = (path, root=document) => document.evaluate(path, root, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
  const rel = (base, path) => base ? xp('.' + path, base) : null;
  const txt = node => (node?.innerText ?? node?.textContent ?? '').trim().replace(/\s+/g, ' ');
  const read = (base, path) => txt(rel(base, path));
  const visible = el => !!(el && el.getClientRects().length && getComputedStyle(el).visibility !== 'hidden');
  const partyList = () => xp('//*[@id="PokeChampionsBuildApp"]/div/div[6]');
  const pager = () => xp('//*[@id="PokeChampionsBuildApp"]/div/div[7]/div[1]');
  const itemIcon = (party, slot) => rel(party, `/div[2]/div[2]/div[${slot}]`);
  const partyMeta = (party, page, index) => {
    const pokemon = [];
    for (let slot = 1; slot <= 6; slot++) {
      const element = itemIcon(party, slot);
      pokemon.push({slot, pokemon: element ? read(element, '/div[2]') : '',
        has_detail: !!element?.classList.contains('_has-detail')});
    }
    const articleLink = [...party.querySelectorAll('a[href]')].find(a => /構築|記事|상세|자세히/.test(txt(a)));
    const points = (txt(party).match(/\d[\d,.]*\s*pt\b/i) || [''])[0].trim();
    return {
      page_number: page,
      party_index: index,
      season: read(party,'/div[1]/div[2]'),
      rank: read(party,'/div[1]/div[3]'),
      player: read(party,'/div[2]/div[1]/div[1]/span'),
      points,
      article_url: articleLink?.href || '',
      pokemon
    };
  };
  const getParties = () => {
    const list = partyList();
    if (!list) return [];
    const result = [];
    // 사용자 확인 XPath의 div[P]를 순차 탐색. 현재 존재하는 마지막 요소까지.
    for (let p = 1; p <= list.children.length; p++) {
      const element = xp(`//*[@id="PokeChampionsBuildApp"]/div/div[6]/div[${p}]`);
      if (!element) break;
      if (element.querySelector('.w-champions-builds-pokemon')) result.push({index:p, element});
    }
    return result;
  };
  const signature = () => JSON.stringify(getParties().map(({index, element}) => {
    const m=partyMeta(element,0,index);
    return [index,m.season,m.rank,m.player,m.pokemon.map(x => x.pokemon)];
  }));
  const waitFor = async (getter, timeoutMs) => {
    const deadline = Date.now()+timeoutMs;
    while(Date.now()<deadline) {
      const value = getter();
      if(value) return value;
      await sleep(100);
    }
    return null;
  };
  // 상세정보 첫 번째 div가 폼 선택 탭이면, 실제 정보 영역은 한 칸씩 뒤로 밀린다.
  // 일반 포켓몬의 div[1]/div[2]는 특성 영역이므로, 경로의 존재만으로 판단하지 않는다.
  const layoutOffset = panel => {
    const tabs = panel.querySelector(':scope > div._form-tabs');
    if (!tabs) return 0;
    if (panel.firstElementChild !== tabs) throw Error('FORM_TABS_NOT_FIRST_CHILD');
    return 1;
  };
  const detailInfo = panel => {
    const offset = layoutOffset(panel);
    const itemPath = `/div[${1 + offset}]/div[1]/span[2]`;
    const abilityPath = `/div[${1 + offset}]/div[2]/span[2]`;
    // 예상과 다른 구조에서는 엉뚱한 텍스트를 기술/특성으로 저장하지 않는다.
    const hasInfoFields = !!rel(panel, itemPath+'/card') && !!rel(panel, abilityPath+'/card');
    if (!hasInfoFields) throw Error('UNEXPECTED_DETAIL_LAYOUT');
    const moves = [1,2,3,4].map(i => read(panel,`/div[${2 + offset}]/div[${i}]/span`));
    const raw = [1,2,3,4,5,6].map(i => read(panel,`/div[${4 + offset}]/div[${i}]/div[3]`));
    const pts = raw.map(s => /^\s*\(?\s*(\d+)\s*\)?\s*$/.exec(s)?.[1] ?? '');
    return {
      detail_id: panel.id,
      form_layout: offset ? 'FORM_TABS' : 'STANDARD',
      item: read(panel, itemPath),
      ability: read(panel, abilityPath),
      nature: read(panel, `/div[${3 + offset}]/span[2]`),
      move_1: moves[0], move_2: moves[1], move_3: moves[2], move_4: moves[3],
      hp_pt: pts[0], atk_pt:pts[1], def_pt:pts[2],
      spa_pt:pts[3], spd_pt:pts[4], spe_pt:pts[5],
      hp_pt_raw:raw[0], atk_pt_raw:raw[1], def_pt_raw:raw[2],
      spa_pt_raw:raw[3], spd_pt_raw:raw[4], spe_pt_raw:raw[5]
    };
  };
  const chooseDetail = (party, slot) => {
    const local = [...party.querySelectorAll('[id^="PokemonDetail_"]')].filter(visible);
    const matching = local.filter(el => el.id.endsWith('_'+(slot-1)));
    if (matching.length === 1) return matching[0];
    if (matching.length > 1) return null;
    if(local.length === 1) return local[0];
    // 상위 DOM에 상세패널이 삽입되는 사이트도 고려. 유일한 경우만 허용.
    const global = [...document.querySelectorAll('[id^="PokemonDetail_"]')].filter(visible);
    const unique = global.filter(el => el.id.endsWith('_'+(slot-1)));
    if(unique.length === 1) return unique[0];
    return global.length === 1 ? global[0] : null;
  };
  // 메가 폼을 클릭해 수집할 필요는 없다. 탭이 있다면 첫 번째 '通常' 폼만 읽는다.
  const ensureNormalForm = async (panel, party, slot) => {
    const tabs = panel.querySelector(':scope > div._form-tabs');
    if (!tabs) return panel;
    const normal = tabs.querySelector(':scope > div._form-tab:first-child');
    if (!normal) throw Error('NORMAL_FORM_TAB_NOT_FOUND');
    if (!normal.classList.contains('is-active')) {
      normal.click();
      const selected = await waitFor(() => {
        const current = chooseDetail(party, slot);
        const first = current?.querySelector(':scope > div._form-tabs > div._form-tab:first-child');
        return first?.classList.contains('is-active') ? current : null;
      }, config.detailTimeoutMs);
      if (!selected) throw Error('NORMAL_FORM_TAB_SWITCH_FAILED');
      return selected;
    }
    return panel;
  };
  const pagerData = () => {
    const p = pager();
    if(!p) return [];
    return [...p.children].map((el,i)=>({
      index:i+1,
      el,
      text:txt(el),
      title:el.getAttribute('title')||'',
      aria:el.getAttribute('aria-label')||'',
      current:el.getAttribute('aria-current')||'',
      disabled:el.hasAttribute('disabled') || el.getAttribute('aria-disabled')==='true' || el.classList.contains('_disabled'),
      visible: visible(el)
    }));
  };
  const chooseNext = target => {
    const all=pagerData().filter(b => b.visible && !b.disabled);
    const numbered=all.filter(b => {
      const value=(b.text+' '+b.aria+' '+b.title).trim();
      return new RegExp(`(?:^|\\D)${target}(?:\\D|$)`).test(value) && !/\.\.\.|…/.test(value);
    });
    if(numbered.length===1) return {el:numbered[0].el, reason:'numbered'};
    if(numbered.length>1) return {el:null, reason:'ambiguous_numbered'};
    // 사용자가 실제로 확인한 2페이지/3페이지 버튼 경로만 예외적으로 허용
    if (target===2 || target===3) {
      const el=xp(`//*[@id="PokeChampionsBuildApp"]/div/div[7]/div[1]/div[${target}]`);
      if(el && visible(el) && el.getAttribute('aria-disabled')!=='true') return {el, reason:'confirmed_xpath'};
    }
    const arrows=all.filter(b=>/次へ|次のページ|다음|next(?:\s+page)?|[›»→＞>]/i.test(b.text+' '+b.title+' '+b.aria));
    if(arrows.length===1) return {el:arrows[0].el, reason:'next_arrow'};
    return {el:null, reason:arrows.length>1?'ambiguous_next':'no_identifiable_next'};
  };
  const download = (data, name) => {
    const blob=new Blob([JSON.stringify(data,null,2)],{type:'application/json;charset=utf-8'});
    const url=URL.createObjectURL(blob);
    const a=document.createElement('a');a.href=url;a.download=name;a.style.display='none';
    document.body.appendChild(a);a.click();a.remove();
    setTimeout(()=>URL.revokeObjectURL(url),30000);
  };
  const data={
    source_url:location.href,
    captured_at: new Date().toISOString(),
    version:'PC-browser-v2-form-tabs',
    teams:[], pokemon:[], pages:[], errors:[],
    status:'STARTED'
  };
  window.__gamewithData=data;
  window.__gamewithStop=false;
  window.__gamewithRunning=true;
  console.log('GameWith 수집 시작. 중단하려면 콘솔에 window.__gamewithStop = true 입력.');
  try {
    if(!getParties().length) throw Error('파티 요소가 없습니다. 정상 화면에서 실행하세요.');
    const visited=new Set();
    for(let pageNumber=1;pageNumber<=config.maxPages;pageNumber++) {
      if(window.__gamewithStop){data.status='STOPPED_BY_USER';break;}
      const before=signature();
      if(!getParties().length){data.status='PARTIES_DISAPPEARED';break;}
      if(visited.has(before)){data.status='REPEATED_PAGE';break;}
      visited.add(before);
      const parties=getParties();
      const pageInfo={page_number:pageNumber, party_count:parties.length, party_indices:parties.map(p=>p.index), pager:pagerData().map(({el,...rest})=>rest)};
      data.pages.push(pageInfo);
      console.log(`[페이지 ${pageNumber}] 파티 ${parties.length}개 / 누적 ${data.teams.length}개`);
      for (const {index,element:party} of parties) {
        if(window.__gamewithStop)break;
        const meta=partyMeta(party,pageNumber,index);
        const team_key=`${pageNumber}|${index}|${meta.season}|${meta.rank}|${meta.player}`;
        data.teams.push({...meta,team_key});
        for (const entry of meta.pokemon) {
          if(window.__gamewithStop)break;
          const row={page_number:pageNumber, party_index:index, team_key,
            season:meta.season,rank:meta.rank,player:meta.player,points:meta.points,
            slot:entry.slot,pokemon:entry.pokemon,
            detail_found:false,error:''};
          if(!entry.pokemon){row.error='ICON_OR_NAME_NOT_FOUND';}
          else if(!entry.has_detail){row.error='NO_DETAIL_AVAILABLE';}
          else {
            const icon=itemIcon(party,entry.slot);
            try {
              icon.click();
              await sleep(config.clickDelayMs);
              let panel=await waitFor(()=>chooseDetail(party,entry.slot),config.detailTimeoutMs);
              if(!panel) row.error='DETAIL_PANEL_NOT_FOUND';
              else {
                panel = await ensureNormalForm(panel, party, entry.slot);
                const info=detailInfo(panel);
                Object.assign(row,info);
                row.detail_found=!!(info.item||info.ability||info.move_1||info.move_2);
                if (!row.detail_found)row.error='DETAIL_FIELDS_EMPTY';
                if (!info.detail_id.endsWith('_'+(entry.slot-1)))row.error=(row.error?row.error+';':'')+'DETAIL_ID_SUFFIX_UNEXPECTED';
              }
            } catch(e){row.error='CLICK_OR_PARSE_ERROR: '+String(e).slice(0,200);}
          }
          data.pokemon.push(row);
        }
      }
      if (window.__gamewithStop){data.status='STOPPED_BY_USER';break;}
      if(config.checkpointEvery>0 && pageNumber%config.checkpointEvery===0) {
        download(data,`gamewith_checkpoint_page_${pageNumber}.json`);
      }
      const chosen=chooseNext(pageNumber+1);
      pageInfo.next_page_method=chosen.reason;
      if(!chosen.el){data.status='NO_IDENTIFIABLE_NEXT_BUTTON__LAST_PAGE_UNVERIFIED';break;}
      try {chosen.el.click();}
      catch(e){data.status='NEXT_BUTTON_CLICK_FAILED';data.errors.push(String(e));break;}
      const updated=await waitFor(()=>{
        const now=signature();
        return now && now!==before ? now : null;
      },config.pageTimeoutMs);
      if(!updated){data.status='PAGE_DID_NOT_CHANGE';break;}
      await sleep(config.pageDelayMs);
    }
    if(data.status==='STARTED')data.status='SAFETY_PAGE_LIMIT_REACHED';
  } catch(e) {
    data.status='ERROR';
    data.errors.push(String(e));
    console.error('수집 중 오류:',e);
  } finally {
    data.completed_at=new Date().toISOString();
    window.__gamewithRunning=false;
    download(data,'GameWith_파티_전체데이터.json');
    console.log(`수집 종료: ${data.teams.length}파티 / ${data.pokemon.length}마리 / 상세 ${data.pokemon.filter(x=>x.detail_found).length}개 / 상태: ${data.status}`);
    console.log('결과 다운로드를 확인하세요. 상세 누락과 페이지 이동 상태는 JSON에 기록됩니다.');
  }
})();