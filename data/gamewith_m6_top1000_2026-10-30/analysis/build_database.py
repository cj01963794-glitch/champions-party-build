#!/usr/bin/env python3
"""Regenerate GameWith M6 pair/triple database from ../parties.csv.
Only composition statistics; no battle matchups, movesets or real pick records.
Usage: python build_database.py [--source ../parties.csv] [--out .]
Standard library only.
"""
import argparse, csv, itertools, json, math
from collections import Counter, defaultdict
from pathlib import Path

SEP = "\x1f"
def ky(xs): return SEP.join(sorted(xs))
def spl(k): return k.split(SEP)
def label(k): return " | ".join(spl(k))
def roundn(v):
    if v is None: return ""
    if math.isinf(v): return "INF"
    return round(v, 8)
def write(p, fields, rows):
    with p.open("w", encoding="utf-8-sig", newline="") as f:
        w=csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
def bh(rows, source="fisher_p", target="q"):
    ordered=sorted(rows,key=lambda z:z[source])
    q=1.
    for pos in range(len(ordered)-1,-1,-1):
        q=min(q,ordered[pos][source]*len(ordered)/(pos+1))
        ordered[pos][target]=min(1.,q)

def build(src,out):
    out.mkdir(parents=True,exist_ok=True)
    with src.open(encoding="utf-8-sig",newline="") as f: originals=list(csv.DictReader(f))
    records=[]
    for i,r in enumerate(originals,1):
        team=sorted((r.get("포켓몬 "+str(j)) or "").strip() for j in range(1,7) if (r.get("포켓몬 "+str(j)) or "").strip())
        if len(team)==len(set(team))==6:
            records.append(dict(id=i,rank=int(r["최종 순위"]),player=r["플레이어"],
                team=team,pdf=r["원본 PDF"],page=r["PDF 페이지"]))
    N=len(records)
    members=sorted(set(p for r in records for p in r["team"]))
    frequencies=[Counter() for _ in range(4)]
    appearances=[defaultdict(list) for _ in range(4)]
    backs=[]
    for rec in records:
        for size in range(1,5):
            for subset in itertools.combinations(rec["team"],size):
                k=ky(subset); frequencies[size-1][k]+=1
                appearances[size-1][k].append(rec)
                if size==3:
                    complement=sorted(set(rec["team"])-set(subset))
                    backs.append(dict(rank=rec["rank"],team_id=rec["id"],player=rec["player"],
                        triple_a=label(k),triple_b=" | ".join(complement),
                        source_pdf=rec["pdf"],source_page=rec["page"]))
    one,two,three,four=frequencies
    osrc,psrc,tsrc,qsrc=appearances
    logs=[math.lgamma(i+1) for i in range(N+1)]
    def choose(a,b):
        if b<0 or b>a:return float("-inf")
        return logs[a]-logs[b]-logs[a-b]
    def fisher(joint, anchor_count, target_count):
        low=max(0,anchor_count+target_count-N)
        high=min(anchor_count,target_count)
        denom=choose(N,anchor_count)
        observed=choose(target_count,joint)+choose(N-target_count,anchor_count-joint)-denom
        result=0.
        for x in range(low,high+1):
            p=choose(target_count,x)+choose(N-target_count,anchor_count-x)-denom
            if p<=observed+1e-9:result+=math.exp(p)
        return min(1.,result)
    rank_fields=["top_50","rank_51_100","rank_101_300","rank_301_1000","rank_list"]
    def rank_info(src):
        ranks=[r["rank"] for r in src]
        return dict(top_50=sum(x<=50 for x in ranks),rank_51_100=sum(50<x<=100 for x in ranks),
            rank_101_300=sum(100<x<=300 for x in ranks),
            rank_301_1000=sum(x>300 for x in ranks),
            rank_list=" | ".join(map(str,ranks)))
    mons=[dict(pokemon=p,count=one[p],rate=roundn(one[p]/N),**rank_info(osrc[p])) for p in members]
    mons.sort(key=lambda z:(-z["count"],z["pokemon"]))
    write(out/"pokemon_usage.csv",["pokemon","count","rate"]+rank_fields,mons)

    pairs=[]
    for a,b in itertools.combinations(members,2):
        k=ky((a,b)); both=two[k]; na=one[a];nb=one[b]
        b0=(nb-both)/(N-na);a0=(na-both)/(N-nb)
        pairs.append(dict(a=a,b=b,n_ab=both,n_a=na,n_b=nb,rate_ab=roundn(both/N),
            p_b_given_a=roundn(both/na),p_a_given_b=roundn(both/nb),
            p_b_without_a=roundn(b0),p_a_without_b=roundn(a0),
            rr_b_given_a=roundn((both/na)/b0 if b0 else (float("inf") if both else None)),
            rr_a_given_b=roundn((both/nb)/a0 if a0 else (float("inf") if both else None)),
            lift=roundn(both*N/(na*nb)),expected_independent=roundn(na*nb/N),
            excess_independent=roundn(both-na*nb/N),
            fisher_p=fisher(both,na,nb),**rank_info(psrc[k])))
    bh(pairs,target="q_bh_all_pairs")
    for r in pairs:
        for k in ("fisher_p","q_bh_all_pairs"):r[k]=roundn(r[k])
    pairs.sort(key=lambda r:(-r["n_ab"],-r["lift"],r["a"],r["b"]))
    fields=["a","b","n_ab","n_a","n_b","rate_ab","p_b_given_a","p_a_given_b",
        "p_b_without_a","p_a_without_b","rr_b_given_a","rr_a_given_b","lift",
        "expected_independent","excess_independent","fisher_p","q_bh_all_pairs"]+rank_fields
    write(out/"pair_statistics.csv",fields,pairs)

    triples=[]
    for k,ct in three.items():
        a,b,c=spl(k)
        triples.append(dict(a=a,b=b,c=c,n_abc=ct,pct_full_teams=roundn(ct/N),
            n_a=one[a],n_b=one[b],n_c=one[c],**rank_info(tsrc[k]),
            team_ids=" | ".join(str(r["id"]) for r in tsrc[k])))
    triples.sort(key=lambda r:(-r["n_abc"],r["a"],r["b"],r["c"]))
    write(out/"triple_statistics.csv",
        ["a","b","c","n_abc","pct_full_teams","n_a","n_b","n_c"]+rank_fields+["team_ids"],triples)
    backs.sort(key=lambda r:(r["rank"],r["team_id"],r["triple_a"]))
    write(out/"triple_complements.csv",
        ["rank","team_id","player","triple_a","triple_b","source_pdf","source_page"],backs)
    side=defaultdict(list)
    for r in backs:side[(r["triple_a"],r["triple_b"])].append(r)
    summaries=[dict(triple_a=a,triple_b=b,count=len(v),
        rank_list=" | ".join(str(z["rank"]) for z in v),
        team_ids=" | ".join(str(z["team_id"]) for z in v))
        for (a,b),v in side.items()]
    summaries.sort(key=lambda r:(-r["count"],r["triple_a"],r["triple_b"]))
    write(out/"triple_complement_counts.csv",
        ["triple_a","triple_b","count","rank_list","team_ids"],summaries)
    index=[]
    for k,ct in three.items():
        t=spl(k)
        for pair in itertools.combinations(t,2):
            index.append(dict(shared_pair=" | ".join(pair),third_pokemon=next(p for p in t if p not in pair),
                triple=label(k),triple_count=ct,rank_list=rank_info(tsrc[k])["rank_list"]))
    index.sort(key=lambda r:(r["shared_pair"],-r["triple_count"],r["third_pokemon"]))
    write(out/"triple_neighbors_by_shared_pair.csv",
        ["shared_pair","third_pokemon","triple","triple_count","rank_list"],index)

    condcols=["anchor","anchor_size","anchor_n","pokemon","pokemon_global_n","joint_n",
        "non_anchor_n","pokemon_outside_n","conditional_rate","outside_rate",
        "relative_rate","expected_from_outside","excess_from_outside","lift",
        "statistical_test","fisher_p","q_bh_per_anchor","q_bh_across_level"]
    sizes={}
    for size,anchors,nextlevel in [(2,two,three),(3,three,four)]:
        everything=[];all_tests=[]
        for ak,na in anchors.items():
            if na==N:continue
            anchor=spl(ak);local=[]
            for p in members:
                if p in anchor:continue
                all_p=one[p];observed=nextlevel[ky(anchor+[p])]
                n_out=all_p-observed;out_rate=n_out/(N-na);in_rate=observed/na
                rr=(in_rate/out_rate if out_rate else (float("inf") if observed else None))
                obj=dict(anchor=label(ak),anchor_size=size,anchor_n=na,
                    pokemon=p,pokemon_global_n=all_p,joint_n=observed,
                    non_anchor_n=N-na,pokemon_outside_n=n_out,
                    conditional_rate=roundn(in_rate),outside_rate=roundn(out_rate),
                    relative_rate=roundn(rr),expected_from_outside=roundn(na*out_rate),
                    excess_from_outside=roundn(observed-na*out_rate),
                    lift=roundn(observed*N/(na*all_p)),
                    statistical_test="tested" if na>=3 else "low_support",
                    fisher_p=fisher(observed,na,all_p) if na>=3 else "",
                    q_bh_per_anchor="",q_bh_across_level="")
                local.append(obj)
                if na>=3:all_tests.append(obj)
            if na>=3:bh(local,target="q_bh_per_anchor")
            everything.extend(local)
        bh(all_tests,target="q_bh_across_level")
        kept=[z for z in everything if z["joint_n"]>0 or
            (z["statistical_test"]=="tested" and z["q_bh_across_level"]<.05)]
        for r in kept:
            for field in ["fisher_p","q_bh_per_anchor","q_bh_across_level"]:
                if r[field]!="":r[field]=roundn(r[field])
        write(out/("conditional_pairs.csv" if size==2 else "conditional_triples.csv"),condcols,kept)
        sizes[size]=dict(rows=len(kept),tests=len(all_tests),comparisons=len(everything))

    checks=dict(source_rows_296=len(originals)==296,complete_285=N==285,
        members_6N=sum(one.values())==6*N,pairs_15N=sum(two.values())==15*N,
        triples_20N=sum(three.values())==20*N,quads_15N=sum(four.values())==15*N,
        complement_rows_20N=len(backs)==20*N,
        neighbor_rows_3per_triple=len(index)==3*len(three),
        duplicate_rank_626=sum(int(x["최종 순위"])==626 for x in originals)==2,
        pair_symmetry=all(abs(z["p_b_given_a"]*z["n_a"]-z["p_a_given_b"]*z["n_b"])<1e-5 for z in pairs),
        triple_counts_max6=all(z["n_abc"]<=N for z in triples))
    if not all(checks.values()):raise RuntimeError("Integrity check failed: "+str(checks))
    manifest=dict(title="GameWith M6 combination database",generated_date="2026-10-30",
        source_file="../parties.csv",source_url="https://gamewith.jp/pokemon-champions/560474",
        source_party_records=len(originals),complete_team_records=N,
        incomplete_team_records=len(originals)-N,
        unique_pokemon=len(members),
        unique_full_six_sets=len({ky(x["team"]) for x in records}),
        all_two_pokemon_pairs=len(pairs),observed_two_pokemon_pairs=len(two),
        observed_triples=len(three),observed_quartets=len(four),
        triple_occurrences=20*N,complement_directed_rows=len(backs),
        complement_distinct_edges=len(summaries),neighbor_index_rows=len(index),
        conditional_pairs_observed_or_q_significant=sizes[2]["rows"],
        conditional_triples_observed_or_q_significant=sizes[3]["rows"],
        conditional_pairs_tests=sizes[2]["tests"],
        conditional_triples_tests=sizes[3]["tests"],
        conditional_pair_total_comparisons=sizes[2]["comparisons"],
        conditional_triple_total_comparisons=sizes[3]["comparisons"],
        conditional_rare_anchor_rule="For anchor n<3 no significance test; only observed positive partner rows output. Missing partners must be interpreted as joint_n=0, not nonexistent hypothesis.",
        conditional_multiple_testing="BH per anchor (candidate pool includes ALL 122 minus anchor members), and separately across all tested anchors within pair/triple levels. Output includes observed positive rows and zero rows with q_bh_across_level<0.05.",
        rank_bins="1-50, 51-100, 101-300, 301-1000",checks=checks)
    (out/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    return manifest

if __name__=="__main__":
    cli=argparse.ArgumentParser()
    cli.add_argument("--source",type=Path,default=Path(__file__).resolve().parent.parent/"parties.csv")
    cli.add_argument("--out",type=Path,default=Path(__file__).resolve().parent)
    args=cli.parse_args()
    print(json.dumps(build(args.source,args.out),ensure_ascii=False,indent=2))
