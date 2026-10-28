#!/usr/bin/env python3
"""Verify JSON/CSV/shards and example source-rule outputs. stdlib only."""
import csv
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parent
def read(name):
    return json.loads((ROOT / name).read_text(encoding="utf-8"))
db = read("db.json")
index = read("index.json")
power = list(csv.DictReader((ROOT / "power.csv").open(encoding="utf-8", newline="")))
bulk = list(csv.DictReader((ROOT / "bulk.csv").open(encoding="utf-8", newline="")))
speed = list(csv.DictReader((ROOT / "speed.csv").open(encoding="utf-8", newline="")))
assert len(db["pokemon"]) == len(index["byEnglish"]) == 346
assert len(power) == db["counts"]["powerRows"] == 3417
assert len(bulk) == 4 * 346 == db["counts"]["bulkRows"]
assert len(speed) == 346 == db["counts"]["speedRows"]
seen = set()
for n in range(8):
    sh = read(f"shards/{n:02d}.json")
    for name, record in sh["pokemon"].items():
        assert name not in seen
        seen.add(name)
        assert db["pokemon"][name] == record
assert seen == set(db["pokemon"])
meta = db["pokemon"]["Mega Metagross"]
for move, correct in {
    "Psychic Fangs": [27349, 32653, 35803],
    "Bullet Punch": [12870, 15366, 16848],
}.items():
    got = next(m["values"] for m in meta["moves"] if m["name"] == move)
    assert got == correct, (move, got, correct)
assert index["byAlias"]["메메타"] == "Mega Metagross"
assert index["byAlias"]["메가플라엣테"] == "Mega Floette"
kanga = db["pokemon"]["Mega Kangaskhan"]
assert next(m["values"] for m in kanga["moves"] if m["name"] == "Fake Out") == [10875, 13275, 14550]
print(f"PASS: {len(seen)} species, {len(power)} attack entries, {len(bulk)} bulk tiers, 8 shards, sampled values.")
