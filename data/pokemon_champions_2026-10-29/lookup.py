#!/usr/bin/env python3
"""Offline Korean/English Pokémon Champions power, bulk and speed lookup."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description="M-7 Pokémon Champions precomputed stat lookup")
    parser.add_argument("pokemon", help="Korean/English name or alias, e.g. 메메타")
    parser.add_argument("move", nargs="?", help="Optional Korean/English move name")
    parser.add_argument("--json", action="store_true", help="Print full machine-readable Pokémon record")
    args = parser.parse_args()

    index = json.loads((ROOT / "index.json").read_text(encoding="utf-8"))
    key = "".join(args.pokemon.lower().split())
    english = index["byAlias"].get(key)
    if english is None:
        raise SystemExit(f"Pokémon not found in 346-species M-7 snapshot: {args.pokemon}")

    shard = ROOT / index["byEnglish"][english]["shard"]
    record = json.loads(shard.read_text(encoding="utf-8"))["pokemon"][english]
    if args.json:
        print(json.dumps(record, ensure_ascii=False, indent=2))
        return

    print(f"{record['ko']} / {english} | 특성 {record['selectedAbility']} | 기본 SP {record['defaultSp']}")
    print("스피드:", record["speed"])
    print("내구 (0SP/H32/HB32/HD32):")
    for tier, v in record["bulk"].items():
        print(f"  {tier:6s}  물리 {v['physical']:>8,}  특수 {v['special']:>8,}")

    matches = [m for m in record["moves"] if
               not args.move or args.move.lower().replace(" ", "") in
               (m["ko"].lower().replace(" ", ""), m["name"].lower().replace(" ", ""))]
    if not matches:
        raise SystemExit(f"Move not found among curated moves: {args.move}")
    print("결정력 (무보정 / 해당 스탯32 / 해당 스탯32+상승성격):")
    for m in matches:
        vals = " / ".join(f"{v:,}" if v is not None else "조건 필요" for v in m["values"])
        print(f"  {m['ko']} ({m['name']}): {vals} [{m['status']}]")
        if m["notes"]:
            print("    조건:", "; ".join(m["notes"]))


if __name__ == "__main__":
    main()
