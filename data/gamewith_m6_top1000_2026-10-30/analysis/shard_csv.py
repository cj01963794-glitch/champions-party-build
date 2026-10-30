#!/usr/bin/env python3
"""Split generated CSV files into query-sized shards without changing their rows.

Run after build_database.py: python shard_csv.py
"""
import csv
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parent
SHARDS=ROOT/"shards"
SOURCES=("conditional_pairs.csv","conditional_triples.csv","triple_neighbors_by_shared_pair.csv")
CHAR_LIMIT=210000

def split_one(filename):
    data=(ROOT/filename).read_text(encoding="utf-8-sig").rstrip("\n")
    rows=data.splitlines()
    header,*body=rows
    SHARDS.mkdir(exist_ok=True)
    prefix=filename.removesuffix(".csv")
    for old in SHARDS.glob(prefix+"_[0-9][0-9].csv"):
        old.unlink()
    index=[];group=[];length=len(header)+2;start=1
    def write_group():
        nonlocal group,length,start
        if not group:return
        shard=f"{prefix}_{len(index)+1:02d}.csv"
        data="\ufeff"+header+"\n"+"\n".join(group)+"\n"
        (SHARDS/shard).write_text(data,encoding="utf-8")
        index.append(dict(filename=shard,start=start,end=start+len(group)-1,rows=len(group)))
        start+=len(group);group=[];length=len(header)+2
    for row in body:
        if length+len(row)+1>CHAR_LIMIT:write_group()
        group.append(row);length+=len(row)+1
    write_group()
    assert sum(x["rows"] for x in index)==len(body)
    manifest=dict(file=filename,shards=index)
    (SHARDS/(prefix+"_manifest.json")).write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    return manifest

if __name__=="__main__":
    for name in SOURCES:
        out=split_one(name)
        print(name,len(out["shards"]),"shards",sum(x["rows"] for x in out["shards"]),"rows")
