#!/usr/bin/env python3
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
cfg=json.loads((ROOT/"docs/migrations/protect-main-migration-train-ruleset-v1.json").read_text(encoding="utf-8"))

assert cfg["ruleset_id"]==20571741
update=cfg["update"]
rollback=cfg["rollback"]

checks=[r for r in update["rules"] if r["type"]=="required_status_checks"]
assert len(checks)==1
assert checks[0]["parameters"]["strict_required_status_checks_policy"] is True
assert checks[0]["parameters"]["required_status_checks"]==[{"context":"lf-migration-merge-train"}]

assert update["bypass_actors"]==[
    {"actor_id":66433825,"actor_type":"User","bypass_mode":"pull_request"},
    {"actor_id":259964988,"actor_type":"User","bypass_mode":"pull_request"},
]

rb=[r for r in rollback["rules"] if r["type"]=="required_status_checks"]
assert len(rb)==1
assert rb[0]["parameters"]["required_status_checks"]==[]
assert rollback["bypass_actors"]==[]

for key in ("conditions","enforcement","target","name"):
    assert update[key]==rollback[key]

assert [r["type"] for r in update["rules"][:-1]]==["deletion","non_fast_forward","pull_request"]
assert [r["type"] for r in rollback["rules"][:-1]]==["deletion","non_fast_forward","pull_request"]

print("PASS_MIGRATION_MERGE_TRAIN_RULESET_POLICY=10/10")
